import { distanceMeters } from '../domain/geo.js';
import { isMetro, type RailSystem } from '../domain/railSystems.js';
import type { Departure } from './railDepartures.js';
import type { RailStationRecord } from './railStations.js';

/** 軌道段的即時資訊；對不上時為 null（App 標示「表定」）。 */
export interface RailLegRealtime {
  system: RailSystem;
  stationID: string;
  /** 預估開車時間（已含誤點）。 */
  expectedAt: string;
  /** 臺鐵誤點分鐘；捷運為 null。 */
  delayMinutes: number | null;
  /** 臺鐵車次（重新整理時用來找同一班車）；捷運為 null。 */
  trainNo: string | null;
  destination: string | null;
}

/** 站名比對：臺／台、去掉「車站」「站」與空白。 */
export function normalizeStationName(name: string | null | undefined): string {
  return (name ?? '').replace(/\s+/g, '').replace(/臺/g, '台').replace(/^往/, '').replace(/(車站|站)$/, '');
}

/**
 * 找上車站對應的 TDX 車站（由近到遠）：同系統類別（捷運／臺鐵）、站名相同且在 400 公尺內；
 * 站名不同時只接受 80 公尺內（同一站不同寫法）。都不符就回傳空陣列（不硬配）。
 * 轉乘站每條線各有一筆（例：台北車站 R10 淡水信義線、BL12 板南線，距離相同），所以回傳全部，由班次比對決定。
 */
export function matchStations(
  stations: RailStationRecord[],
  mode: 'metro' | 'tra',
  place: { name: string | null; lat: number; lon: number },
): RailStationRecord[] {
  const wanted = normalizeStationName(place.name);
  return stations
    .flatMap((station) => {
      const fits = mode === 'tra' ? station.system === 'TRA' : isMetro(station.system);
      if (!fits) return [];
      const distance = distanceMeters({ lat: place.lat, lon: place.lon }, station);
      const sameName = wanted !== '' && normalizeStationName(station.name) === wanted;
      return (sameName ? distance <= 400 : distance <= 80) ? [{ station, distance }] : [];
    })
    .sort((a, b) => a.distance - b.distance)
    .map(({ station }) => station);
}

/**
 * 從車站發車資料中找出這一段要搭的班次。只採用即時資料：
 * - 捷運：同路線、同終點（MaaS headsign），取最早一班。
 * - 臺鐵：表定開車時間與 MaaS 出發時間相差 2 分鐘內且只有一班。
 */
export function matchDeparture(
  mode: 'metro' | 'tra',
  leg: { line: string; headsign: string | null; departAt: string | null },
  departures: Departure[],
  nowMs: number,
): Departure | undefined {
  const live = departures.filter((d) => d.dataLevel === 'realtime' && d.expectedAt && Date.parse(d.expectedAt) >= nowMs - 60_000);
  if (mode === 'metro') {
    const headsign = normalizeStationName(leg.headsign);
    if (!headsign) return undefined;
    return live
      .filter((d) => normalizeStationName(d.destination) === headsign && (!d.line || !leg.line || d.line === leg.line))
      .sort((a, b) => Date.parse(a.expectedAt!) - Date.parse(b.expectedAt!))[0];
  }
  if (!leg.departAt) return undefined;
  const planned = Date.parse(leg.departAt);
  const candidates = live.filter((d) => d.scheduledAt && Math.abs(Date.parse(d.scheduledAt) - planned) <= 120_000);
  return candidates.length === 1 ? candidates[0] : undefined;
}

export function toRailLegRealtime(station: RailStationRecord, departure: Departure): RailLegRealtime {
  return {
    system: station.system,
    stationID: station.id,
    expectedAt: departure.expectedAt!,
    delayMinutes: departure.delayMinutes,
    trainNo: departure.trainNo,
    destination: departure.destination,
  };
}
