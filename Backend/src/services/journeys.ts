import { SUPPORTED_CITIES, type City } from '../domain/cities.js';
import type { Coordinate } from '../domain/geo.js';
import type { Arrival, ArrivalService } from './arrivals.js';
import { findNearbyStops, findOppositeStop, matchDirectRoutes, type DirectCandidate } from './matching.js';
import type { CityStaticData, StaticDataStore, StopRecord } from './staticData.js';

/** 沒有同一部車在下車站的預估時，每站平均行車秒數（估計值，回應中會標示）。 */
export const ESTIMATED_SECONDS_PER_STOP = 90;

export interface StopDTO {
  uid: string;
  name: string;
  lat: number;
  lon: number;
  bearing: string | null;
  city: City;
}

export interface BusCandidateDTO {
  id: string;
  city: City;
  route: { uid: string; name: string; subRouteUID: string | null; headsign: string };
  boardingStop: StopDTO;
  alightingStop: StopDTO;
  /** 馬路對面同名、反方向的站牌；找不到時為 null。 */
  oppositeStop: StopDTO | null;
  stopCount: number;
  arrival: Arrival | null;
  rideSeconds: number;
  /** vehicle：同一部車在上下車站的預估相減；stopCount：依站數估計。 */
  rideSource: 'vehicle' | 'stopCount';
}

export interface JourneyResponse {
  generatedAt: string;
  candidates: BusCandidateDTO[];
}

export interface JourneyServiceOptions {
  cities?: readonly City[];
  /** 起點、目的地附近多遠內的站牌可以走過去。 */
  walkRadius?: number;
  now?: () => number;
}

/** 找出直達公車方案並附上到站預估。步行段由 App 用 Apple 地圖計算。 */
export class JourneyService {
  private readonly cities: readonly City[];
  private readonly walkRadius: number;
  private readonly now: () => number;

  constructor(
    private readonly staticData: StaticDataStore,
    private readonly arrivals: ArrivalService,
    options: JourneyServiceOptions = {},
  ) {
    this.cities = options.cities ?? SUPPORTED_CITIES;
    this.walkRadius = options.walkRadius ?? 500;
    this.now = options.now ?? Date.now;
  }

  async nearbyStops(center: Coordinate, radius: number): Promise<StopDTO[]> {
    const data = await this.loadCities();
    return findNearbyStops(data, center, radius).map(({ stop }) => toStopDTO(stop));
  }

  async findJourneys(origin: Coordinate, destination: Coordinate): Promise<JourneyResponse> {
    const data = await this.loadCities();
    const originStops = findNearbyStops(data, origin, this.walkRadius);
    const destinationStops = findNearbyStops(data, destination, this.walkRadius);
    const candidates = matchDirectRoutes(data, originStops, destinationStops);

    // 每個縣市只查一次到站預估（上車站與下車站一起查）。
    const arrivalsByCity = new Map<City, Map<string, Arrival[]>>();
    for (const city of new Set(candidates.map((candidate) => candidate.boarding.stop.city))) {
      const stopUIDs = candidates
        .filter((candidate) => candidate.boarding.stop.city === city)
        .flatMap((candidate) => [candidate.boarding.stop.uid, candidate.alighting.stop.uid]);
      arrivalsByCity.set(city, await this.arrivals.arrivals(city, stopUIDs));
    }

    return {
      generatedAt: new Date(this.now()).toISOString(),
      candidates: candidates.map((candidate) => {
        const cityData = data.find((d) => d.city === candidate.boarding.stop.city);
        return buildCandidate(candidate, arrivalsByCity.get(candidate.boarding.stop.city), cityData);
      }),
    };
  }

  private async loadCities(): Promise<CityStaticData[]> {
    const settled = await Promise.allSettled(this.cities.map((city) => this.staticData.get(city)));
    const loaded = settled.flatMap((result) => (result.status === 'fulfilled' ? [result.value] : []));
    if (loaded.length === 0) throw new Error('No city data available');
    return loaded;
  }
}

export function buildCandidate(
  candidate: DirectCandidate,
  arrivals: Map<string, Arrival[]> | undefined,
  cityData: CityStaticData | undefined,
): BusCandidateDTO {
  const { route, boarding, alighting } = candidate;
  const matches = (arrival: Arrival) =>
    arrival.routeUID === route.routeUID && (route.subRouteUID == null || arrival.subRouteUID == null || arrival.subRouteUID === route.subRouteUID);
  const boardArrival = (arrivals?.get(boarding.stop.uid) ?? []).find(matches) ?? null;
  const alightArrival =
    boardArrival?.plateNumber != null
      ? (arrivals?.get(alighting.stop.uid) ?? []).find((a) => matches(a) && a.plateNumber === boardArrival.plateNumber)
      : undefined;

  const vehicleRide =
    boardArrival?.arrivalAt && alightArrival?.arrivalAt
      ? (Date.parse(alightArrival.arrivalAt) - Date.parse(boardArrival.arrivalAt)) / 1000
      : undefined;
  const useVehicle = vehicleRide != null && vehicleRide > 0;
  const opposite = cityData ? findOppositeStop(cityData, boarding.stop, route.routeKey) : undefined;

  return {
    id: `${route.routeKey}@${boarding.stop.uid}>${alighting.stop.uid}`,
    city: boarding.stop.city,
    route: { uid: route.routeUID, name: route.routeName, subRouteUID: route.subRouteUID, headsign: route.headsign },
    boardingStop: toStopDTO(boarding.stop),
    alightingStop: toStopDTO(alighting.stop),
    oppositeStop: opposite ? toStopDTO(opposite) : null,
    stopCount: candidate.stopCount,
    arrival: boardArrival,
    rideSeconds: useVehicle ? Math.round(vehicleRide) : candidate.stopCount * ESTIMATED_SECONDS_PER_STOP,
    rideSource: useVehicle ? 'vehicle' : 'stopCount',
  };
}

function toStopDTO(stop: StopRecord): StopDTO {
  return { uid: stop.uid, name: stop.name, lat: stop.lat, lon: stop.lon, bearing: stop.bearing, city: stop.city };
}
