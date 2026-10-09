import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import type { City } from '../domain/cities.js';
import type { TdxApi } from '../tdx/client.js';
import { parseList, tdxRoute, tdxStop, tdxStopOfRoute, type TdxRoute, type TdxStop, type TdxStopOfRoute } from '../tdx/types.js';

export interface StopRecord {
  uid: string;
  name: string;
  lat: number;
  lon: number;
  /** TDX 方位：E/W/S/N/SE/NE/SW/NW。 */
  bearing: string | null;
  stationID: string | null;
  city: City;
}

/** 某路線（附屬路線＋方向）經過某站的位置。 */
export interface RouteStopRef {
  routeKey: string;
  sequence: number;
  /** -1 只能下車、0 可上下車、1 只能上車。 */
  boarding: number;
}

export interface RouteDirection {
  routeKey: string;
  routeUID: string;
  routeID: string | null;
  routeName: string;
  subRouteUID: string | null;
  direction: number;
  /** 例：「往台北車站」的終點描述。 */
  headsign: string;
}

export interface CityStaticData {
  city: City;
  loadedAt: number;
  stops: StopRecord[];
  stopsByUID: Map<string, StopRecord>;
  routesByStop: Map<string, RouteStopRef[]>;
  routes: Map<string, RouteDirection>;
}

/** 路線（附屬路線＋方向）的唯一鍵；方向以站序資料為準，不用到站資料的 Direction。 */
export function routeKey(routeUID: string, subRouteUID: string | null | undefined, direction: number): string {
  return `${routeUID}|${subRouteUID ?? routeUID}|${direction}`;
}

/** 由 TDX 原始資料建立索引（純函式，方便測試）。 */
export function buildCityData(
  city: City,
  stops: TdxStop[],
  stopOfRoutes: TdxStopOfRoute[],
  routes: TdxRoute[],
  loadedAt: number,
): CityStaticData {
  const stopRecords: StopRecord[] = stops.map((stop) => ({
    uid: stop.StopUID,
    name: stop.StopName?.Zh_tw ?? stop.StopName?.En ?? stop.StopUID,
    lat: stop.StopPosition.PositionLat,
    lon: stop.StopPosition.PositionLon,
    bearing: stop.Bearing ?? null,
    stationID: stop.StationID ?? null,
    city,
  }));
  const stopsByUID = new Map(stopRecords.map((stop) => [stop.uid, stop]));

  const headsigns = new Map<string, string>();
  for (const route of routes) {
    for (const sub of route.SubRoutes ?? []) {
      if (sub.Direction == null) continue;
      const sign = sub.Headsign ?? sub.DestinationStopNameZh ?? route.DestinationStopNameZh;
      if (sign) headsigns.set(routeKey(route.RouteUID, sub.SubRouteUID, sub.Direction), sign);
    }
  }

  const routesByStop = new Map<string, RouteStopRef[]>();
  const routeDirections = new Map<string, RouteDirection>();
  for (const sor of stopOfRoutes) {
    const key = routeKey(sor.RouteUID, sor.SubRouteUID, sor.Direction);
    const ordered = [...sor.Stops].sort((a, b) => a.StopSequence - b.StopSequence);
    const lastStopName = ordered.at(-1)?.StopName?.Zh_tw;
    routeDirections.set(key, {
      routeKey: key,
      routeUID: sor.RouteUID,
      routeID: sor.RouteID ?? null,
      routeName: sor.RouteName?.Zh_tw ?? sor.RouteUID,
      subRouteUID: sor.SubRouteUID ?? null,
      direction: sor.Direction,
      headsign: headsigns.get(key) ?? (lastStopName ? `往${lastStopName}` : '方向未提供'),
    });
    for (const stop of ordered) {
      const refs = routesByStop.get(stop.StopUID) ?? [];
      refs.push({ routeKey: key, sequence: stop.StopSequence, boarding: stop.StopBoarding ?? 0 });
      routesByStop.set(stop.StopUID, refs);
    }
  }

  return { city, loadedAt, stops: stopRecords, stopsByUID, routesByStop, routes: routeDirections };
}

export interface StaticDataStoreOptions {
  dataDir: string;
  /** 靜態資料多久重新下載一次。 */
  maxAgeMs?: number;
  now?: () => number;
}

interface CachedRaw {
  savedAt: number;
  stops: unknown;
  stopOfRoutes: unknown;
  routes: unknown;
}

/** 各縣市站牌、站序、路線：每天下載一次並存到磁碟，重啟後不必重抓。 */
export class StaticDataStore {
  private readonly data = new Map<City, CityStaticData>();
  private readonly loading = new Map<City, Promise<CityStaticData>>();
  private readonly maxAgeMs: number;
  private readonly now: () => number;

  constructor(private readonly api: TdxApi, private readonly options: StaticDataStoreOptions) {
    this.maxAgeMs = options.maxAgeMs ?? 24 * 60 * 60 * 1000;
    this.now = options.now ?? Date.now;
  }

  loadedCities(): Record<string, string> {
    return Object.fromEntries([...this.data].map(([city, d]) => [city, new Date(d.loadedAt).toISOString()]));
  }

  async get(city: City): Promise<CityStaticData> {
    const current = this.data.get(city);
    if (current && this.now() - current.loadedAt < this.maxAgeMs) return current;
    const pending = this.loading.get(city) ?? this.load(city).finally(() => this.loading.delete(city));
    this.loading.set(city, pending);
    // 有舊資料時先用舊的，背景更新失敗也不影響服務。
    if (current) {
      pending.catch(() => undefined);
      return current;
    }
    return pending;
  }

  private async load(city: City): Promise<CityStaticData> {
    const cached = await this.readCache(city);
    const raw = cached && this.now() - cached.savedAt < this.maxAgeMs ? cached : await this.download(city);
    const stops = parseList(tdxStop, raw.stops).items;
    const stopOfRoutes = parseList(tdxStopOfRoute, raw.stopOfRoutes).items;
    const routes = parseList(tdxRoute, raw.routes).items;
    const built = buildCityData(city, stops, stopOfRoutes, routes, raw.savedAt);
    this.data.set(city, built);
    return built;
  }

  private async download(city: City): Promise<CachedRaw> {
    const [stops, stopOfRoutes, routes] = await Promise.all([
      this.api.get(`/v2/Bus/Stop/City/${city}`),
      this.api.get(`/v2/Bus/StopOfRoute/City/${city}`),
      this.api.get(`/v2/Bus/Route/City/${city}`),
    ]);
    const raw: CachedRaw = { savedAt: this.now(), stops, stopOfRoutes, routes };
    await this.writeCache(city, raw);
    return raw;
  }

  private cachePath(city: City): string {
    return path.join(this.options.dataDir, `static-${city}.json`);
  }

  private async readCache(city: City): Promise<CachedRaw | undefined> {
    try {
      return JSON.parse(await readFile(this.cachePath(city), 'utf8')) as CachedRaw;
    } catch {
      return undefined;
    }
  }

  private async writeCache(city: City, raw: CachedRaw): Promise<void> {
    await mkdir(this.options.dataDir, { recursive: true });
    await writeFile(this.cachePath(city), JSON.stringify(raw));
  }
}
