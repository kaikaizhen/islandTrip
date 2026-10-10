import type { City } from '../domain/cities.js';
import { distanceMeters, type Coordinate } from '../domain/geo.js';
import type { TdxApi } from '../tdx/client.js';
import { maasResponse, maasRoute, type MaasRoute, type MaasSection } from '../tdx/maasTypes.js';
import { parseList } from '../tdx/types.js';
import type { Arrival, ArrivalService } from './arrivals.js';
import { toStopDTO, type StopDTO } from './journeys.js';
import { findOppositeStop } from './matching.js';
import { TtlCache } from './ttlCache.js';
import type { CityStaticData, StaticDataStore, StopRecord } from './staticData.js';

export interface PlacePoint {
  name: string | null;
  lat: number;
  lon: number;
}

export type TransitMode = 'bus' | 'metro' | 'tra' | 'thsr' | 'lightRail' | 'ferry' | 'other';

/** 公車段對回 TDX 後的即時資訊；對不上時為 null（App 標示「表定」）。 */
export interface LegRealtime {
  city: string;
  stopUID: string;
  /** 用來更新到站時間（/v1/arrivals 回傳整站，App 依路線篩選）。 */
  routeUID: string;
  subRouteUID: string | null;
  arrival: Arrival | null;
  /** 上車站牌與馬路對面同名反方向站牌（App 判斷上車側用）；找不到對面時為 null，不硬猜。 */
  boardingStop: StopDTO;
  oppositeStop: StopDTO | null;
}

export type PlanLeg =
  | { kind: 'walk'; from: PlacePoint; to: PlacePoint; seconds: number; meters: number; inStation: boolean }
  | { kind: 'wait'; at: PlacePoint; seconds: number }
  | {
      kind: 'transit';
      mode: TransitMode;
      line: string;
      headsign: string | null;
      color: string | null;
      from: PlacePoint;
      to: PlacePoint;
      departAt: string | null;
      arriveAt: string | null;
      /** 中途站（含座標，給 App 畫路線示意）。 */
      stops: PlacePoint[];
      realtime: LegRealtime | null;
    };

export interface PlanRoute {
  id: string;
  durationSeconds: number;
  startAt: string | null;
  endAt: string | null;
  transfers: number;
  legs: PlanLeg[];
}

export interface PlanResponse {
  generatedAt: string;
  routes: PlanRoute[];
}

/** MaaS 的時間是臺北時間、沒有時區：補上 +08:00 再轉 ISO。 */
export function maasTime(value: string | null | undefined): string | null {
  if (!value) return null;
  const trimmed = value.replace(/\.\d+$/, '');
  const date = new Date(/[zZ]|[+-]\d{2}:?\d{2}$/.test(trimmed) ? trimmed : `${trimmed}+08:00`);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

export function transitMode(mode: string | null | undefined): TransitMode {
  switch ((mode ?? '').toLowerCase()) {
    case 'bus':
      return 'bus';
    case 'mrt':
    case 'metro':
      return 'metro';
    case 'tra':
      return 'tra';
    case 'thsr':
    case 'hsr':
      return 'thsr';
    case 'lrt':
    case 'lightrail':
      return 'lightRail';
    case 'ferry':
      return 'ferry';
    default:
      return 'other';
  }
}

function point(section: { place: { name?: string | null; location: { lat: number; lng: number } } }): PlacePoint {
  return { name: section.place.name ?? null, lat: section.place.location.lat, lon: section.place.location.lng };
}

/** 站名比對用：去空白、臺／台、全形括號。 */
export function normalizeStopName(name: string | null | undefined): string {
  return (name ?? '').replace(/\s+/g, '').replace(/臺/g, '台').replace(/（/g, '(').replace(/）/g, ')');
}

/**
 * 把 MaaS 的公車段對回 TDX 站牌：上車站要在座標附近、站名相同、有這條路線停靠，
 * 而且同一個路線方向中下車站在上車站之後（方向正確）。任何一項不符就不對（不硬配）。
 */
export function matchBusLeg(
  cities: CityStaticData[],
  line: string,
  from: PlacePoint,
  to: PlacePoint,
  maxDistance = 60,
): { city: CityStaticData; boarding: StopRecord; routeKey: string } | undefined {
  const near = (target: PlacePoint, stop: StopRecord) =>
    distanceMeters({ lat: target.lat, lon: target.lon }, stop) <= maxDistance &&
    (target.name == null || normalizeStopName(stop.name) === normalizeStopName(target.name));
  for (const city of cities) {
    const boardings = city.stops.filter((stop) => near(from, stop));
    const alightings = city.stops.filter((stop) => near(to, stop));
    for (const boarding of boardings) {
      for (const ref of city.routesByStop.get(boarding.uid) ?? []) {
        const route = city.routes.get(ref.routeKey);
        if (!route || normalizeStopName(route.routeName) !== normalizeStopName(line)) continue;
        const forward = alightings.some((stop) =>
          (city.routesByStop.get(stop.uid) ?? []).some((r) => r.routeKey === ref.routeKey && r.sequence > ref.sequence),
        );
        if (forward) return { city, boarding, routeKey: ref.routeKey };
      }
    }
  }
  return undefined;
}

export function toPlanRoute(route: MaasRoute, index: number): PlanRoute | undefined {
  const legs: PlanLeg[] = [];
  for (const section of route.sections) {
    const leg = toLeg(section);
    // 計程車、腳踏車等不適合長輩的段落（理論上已用參數排除）：整條方案不採用。
    if (leg === 'unsupported') return undefined;
    if (leg) legs.push(leg);
  }
  return {
    id: `maas-${index}-${route.start_time}`,
    durationSeconds: Math.round(route.travel_time),
    startAt: maasTime(route.start_time),
    endAt: maasTime(route.end_time),
    transfers: route.transfers ?? Math.max(0, legs.filter((l) => l.kind === 'transit').length - 1),
    legs,
  };
}

function toLeg(section: MaasSection): PlanLeg | 'unsupported' | undefined {
  const seconds = Math.round(section.travelSummary?.duration ?? 0);
  switch (section.type) {
    case 'pedestrian':
    case 'pedestrian-station':
      return {
        kind: 'walk',
        from: point(section.departure),
        to: point(section.arrival),
        seconds,
        meters: Math.round(section.travelSummary?.length ?? 0),
        inStation: section.type === 'pedestrian-station',
      };
    case 'waiting':
      return { kind: 'wait', at: point(section.departure), seconds };
    case 'transit':
      return {
        kind: 'transit',
        mode: transitMode(section.transport?.mode),
        line: section.transport?.shortName ?? section.transport?.name ?? '大眾運輸',
        headsign: section.transport?.headsign ?? null,
        color: section.transport?.route_color ? `#${section.transport.route_color.replace(/^#/, '')}` : null,
        from: point(section.departure),
        to: point(section.arrival),
        departAt: maasTime(section.departure.time),
        arriveAt: maasTime(section.arrival.time),
        stops: (section.intermediateStops ?? []).flatMap((stop) =>
          stop.departure?.place ? [{ name: stop.departure.place.name ?? null, lat: stop.departure.place.location.lat, lon: stop.departure.place.location.lng }] : [],
        ),
        realtime: null,
      };
    case 'drive':
    case 'cycle':
      return 'unsupported';
    default:
      return undefined;
  }
}

export interface MaasPlannerOptions {
  now?: () => number;
  /** 回傳幾條方案（MaaS 上限 10）。 */
  top?: number;
  /** 第一哩／最後一哩最多走幾分鐘。 */
  maxWalkMinutes?: number;
  /** 同一起訖點（約 100 公尺內）的方案共用多久；即時到站每次重新附上。 */
  cacheTtlMs?: number;
}

/** 跨運具規劃：MaaS 給方案（表定時間），公車段能對回 TDX 的就補上即時到站。 */
export class MaasPlanner {
  private readonly now: () => number;
  private readonly top: number;
  private readonly maxWalkMinutes: number;
  private readonly cache: TtlCache<PlanRoute[]>;

  constructor(
    private readonly maas: TdxApi,
    private readonly staticData: StaticDataStore,
    private readonly arrivals: ArrivalService,
    private readonly cities: readonly City[],
    options: MaasPlannerOptions = {},
  ) {
    this.now = options.now ?? Date.now;
    this.top = options.top ?? 5;
    this.maxWalkMinutes = options.maxWalkMinutes ?? 15;
    this.cache = new TtlCache(options.cacheTtlMs ?? 60_000, this.now);
  }

  /**
   * MaaS 呼叫慢又容易被限流（真實量測：4 次查詢送出 18 次、10 次 429），
   * App 重新整理或重進畫面時同一趟行程不重查；同時查同一趟只送一次。
   */
  async plan(origin: Coordinate, destination: Coordinate): Promise<PlanResponse> {
    const key = [origin.lat, origin.lon, destination.lat, destination.lon].map((v) => v.toFixed(3)).join(',');
    const cached = await this.cache.get(key, () => this.fetchRoutes(origin, destination));
    // 快取的是表定方案；附即時資料會改動段落，所以每次用複本。
    const routes = structuredClone(cached);
    await this.attachRealtime(routes);
    return { generatedAt: new Date(this.now()).toISOString(), routes };
  }

  private async fetchRoutes(origin: Coordinate, destination: Coordinate): Promise<PlanRoute[]> {
    const raw = await this.maas.get('/routing', {
      origin: `${origin.lat},${origin.lon}`,
      destination: `${destination.lat},${destination.lon}`,
      gc: '1',
      top: String(this.top),
      // 3 高鐵、4 臺鐵、5 公車、6 捷運、7 輕軌
      transit: '3,4,5,6,7',
      // 只步行：未指定時 MaaS 會排計程車或腳踏車（真實回應觀察）
      first_mile_mode: '0',
      first_mile_time: String(this.maxWalkMinutes),
      last_mile_mode: '0',
      last_mile_time: String(this.maxWalkMinutes),
    });
    const parsed = maasResponse.safeParse(raw);
    if (!parsed.success || parsed.data.result !== 'success') {
      throw new Error(`MaaS failed: ${parsed.success ? (parsed.data.error?.msg ?? parsed.data.result) : 'invalid response'}`);
    }
    return parseList(maasRoute, parsed.data.data?.routes ?? [])
      .items.map(toPlanRoute)
      .flatMap((route) => (route ? [route] : []));
  }

  /** 公車段：對回 TDX 站牌並查即時到站（同縣市一次批次查詢）。 */
  private async attachRealtime(routes: PlanRoute[]): Promise<void> {
    const loaded = (
      await Promise.allSettled(this.cities.map((city) => this.staticData.get(city)))
    ).flatMap((result) => (result.status === 'fulfilled' ? [result.value] : []));
    if (loaded.length === 0) return;

    const matches: { leg: Extract<PlanLeg, { kind: 'transit' }>; city: CityStaticData; stop: StopRecord; routeKey: string }[] = [];
    for (const route of routes) {
      for (const leg of route.legs) {
        if (leg.kind !== 'transit' || leg.mode !== 'bus') continue;
        const match = matchBusLeg(loaded, leg.line, leg.from, leg.to);
        if (match) matches.push({ leg, city: match.city, stop: match.boarding, routeKey: match.routeKey });
      }
    }
    for (const city of new Set(matches.map((m) => m.city))) {
      const forCity = matches.filter((m) => m.city === city);
      const byStop = await this.arrivals.arrivals(city.city, forCity.map((m) => m.stop.uid)).catch(() => new Map<string, Arrival[]>());
      for (const match of forCity) {
        const route = city.routes.get(match.routeKey);
        const arrival =
          (byStop.get(match.stop.uid) ?? []).find(
            (a) => a.routeUID === route?.routeUID && (route?.subRouteUID == null || a.subRouteUID == null || a.subRouteUID === route.subRouteUID),
          ) ?? null;
        const opposite = findOppositeStop(city, match.stop, match.routeKey);
        match.leg.realtime = {
          city: city.city,
          stopUID: match.stop.uid,
          routeUID: route?.routeUID ?? '',
          subRouteUID: route?.subRouteUID ?? null,
          arrival,
          boardingStop: toStopDTO(match.stop),
          oppositeStop: opposite ? toStopDTO(opposite) : null,
        };
      }
    }
  }
}

