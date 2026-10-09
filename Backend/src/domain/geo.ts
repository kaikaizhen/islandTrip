export interface Coordinate {
  lat: number;
  lon: number;
}

const EARTH_RADIUS = 6_371_000;

/** 兩點距離（公尺）。 */
export function distanceMeters(a: Coordinate, b: Coordinate): number {
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLon = toRad(b.lon - a.lon);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** 以中心點與半徑算出的經緯度範圍，用來先粗篩再算精確距離。 */
export function boundingBox(center: Coordinate, radiusMeters: number) {
  const dLat = (radiusMeters / EARTH_RADIUS) * (180 / Math.PI);
  const dLon = dLat / Math.cos((center.lat * Math.PI) / 180);
  return { minLat: center.lat - dLat, maxLat: center.lat + dLat, minLon: center.lon - dLon, maxLon: center.lon + dLon };
}
