import { boundingBox, distanceMeters, type Coordinate } from '../domain/geo.js';
import type { CityStaticData, RouteDirection, StopRecord } from './staticData.js';

export interface NearbyStop {
  stop: StopRecord;
  distance: number;
}

/** 找出半徑內的站牌（跨縣市），由近到遠。 */
export function findNearbyStops(cities: CityStaticData[], center: Coordinate, radius: number, limit = 50): NearbyStop[] {
  const box = boundingBox(center, radius);
  const result: NearbyStop[] = [];
  for (const data of cities) {
    for (const stop of data.stops) {
      if (stop.lat < box.minLat || stop.lat > box.maxLat || stop.lon < box.minLon || stop.lon > box.maxLon) continue;
      const distance = distanceMeters(center, stop);
      if (distance <= radius) result.push({ stop, distance });
    }
  }
  return result.sort((a, b) => a.distance - b.distance).slice(0, limit);
}

export interface DirectCandidate {
  route: RouteDirection;
  boarding: NearbyStop;
  alighting: NearbyStop;
  stopCount: number;
}

/**
 * 找出「起點附近上車、目的地附近下車」的直達路線。
 * 方向以站序判斷：同一附屬路線＋方向中，上車站序要小於下車站序；不只看路線號碼（計畫 4.1）。
 * 同名但方向相反的站牌是不同 StopUID，不會被合併。
 */
export function matchDirectRoutes(
  cities: CityStaticData[],
  originStops: NearbyStop[],
  destinationStops: NearbyStop[],
  maxCandidates = 12,
): DirectCandidate[] {
  const best = new Map<string, DirectCandidate>();
  for (const data of cities) {
    for (const boarding of originStops) {
      if (boarding.stop.city !== data.city) continue;
      const boardRefs = data.routesByStop.get(boarding.stop.uid) ?? [];
      for (const ref of boardRefs) {
        if (ref.boarding === -1) continue; // 只能下車的站
        for (const alighting of destinationStops) {
          if (alighting.stop.city !== data.city || alighting.stop.uid === boarding.stop.uid) continue;
          const alightRef = (data.routesByStop.get(alighting.stop.uid) ?? []).find(
            (candidate) => candidate.routeKey === ref.routeKey && candidate.sequence > ref.sequence && candidate.boarding !== 1,
          );
          if (!alightRef) continue;
          const route = data.routes.get(ref.routeKey);
          if (!route) continue;
          const candidate: DirectCandidate = { route, boarding, alighting, stopCount: alightRef.sequence - ref.sequence };
          const existing = best.get(ref.routeKey);
          if (!existing || score(candidate) < score(existing)) best.set(ref.routeKey, candidate);
        }
      }
    }
  }
  return [...best.values()].sort((a, b) => score(a) - score(b)).slice(0, maxCandidates);
}

/** 步行越少越好；步行相同時站數少的優先。 */
function score(candidate: DirectCandidate): number {
  return candidate.boarding.distance + candidate.alighting.distance + candidate.stopCount;
}

/**
 * 馬路對面同名、反方向的站牌（給上車側判斷用）。
 * TDX 臺北市資料「同一根站牌、每條路線各有一個 StopUID」，所以必須用站位（StationID）分辨實體位置：
 * 同站位＝同一根站牌（同一側），不能當成對面。沒有站位資料時至少要相距 minSeparation 公尺。
 * 找不到時回傳 undefined，不硬猜。
 */
export function findOppositeStop(
  data: CityStaticData,
  boarding: StopRecord,
  routeKey: string,
  maxDistance = 120,
  minSeparation = 15,
): StopRecord | undefined {
  let best: { stop: StopRecord; score: number } | undefined;
  for (const stop of data.stops) {
    if (stop.uid === boarding.uid || stop.name !== boarding.name) continue;
    if (boarding.stationID && stop.stationID && stop.stationID === boarding.stationID) continue;
    const distance = distanceMeters(boarding, stop);
    if (distance > maxDistance) continue;
    if ((!boarding.stationID || !stop.stationID) && distance < minSeparation) continue;
    const servesSameDirection = (data.routesByStop.get(stop.uid) ?? []).some((ref) => ref.routeKey === routeKey);
    if (servesSameDirection) continue;
    // 方位不同（例如西南行 vs 南行）優先，其次是距離近。
    const sameBearing = boarding.bearing != null && stop.bearing === boarding.bearing;
    const score = distance + (sameBearing ? 1000 : 0);
    if (!best || score < best.score) best = { stop, score };
  }
  return best?.stop;
}
