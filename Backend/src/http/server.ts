import { timingSafeEqual } from 'node:crypto';
import Fastify, { type FastifyInstance } from 'fastify';
import { z } from 'zod';
import { SUPPORTED_CITIES } from '../domain/cities.js';
import { RAIL_SYSTEMS } from '../domain/railSystems.js';
import type { AlertStore } from '../services/alerts.js';
import type { ArrivalService } from '../services/arrivals.js';
import type { JourneyService } from '../services/journeys.js';
import type { MaasPlanner } from '../services/maasPlanner.js';
import type { RailAlertService } from '../services/railAlerts.js';
import type { RailDepartureService } from '../services/railDepartures.js';
import type { RailStationStore } from '../services/railStations.js';
import type { StaticDataStore } from '../services/staticData.js';
import type { UsageMeter } from '../tdx/usage.js';

export interface ServerDependencies {
  appApiKey: string;
  journeys: JourneyService;
  arrivals: ArrivalService;
  alerts: AlertStore;
  staticData: StaticDataStore;
  railStations: RailStationStore;
  railDepartures: RailDepartureService;
  railAlerts: RailAlertService;
  planner: MaasPlanner;
  usage?: UsageMeter;
  /** 每個 IP 每分鐘最多幾次請求。 */
  rateLimitPerMinute?: number;
  now?: () => number;
  log?: (message: string) => void;
}

const lat = z.coerce.number().min(-90).max(90);
const lon = z.coerce.number().min(-180).max(180);
const journeyQuery = z.object({ originLat: lat, originLon: lon, destinationLat: lat, destinationLon: lon });
const nearbyQuery = z.object({ lat, lon, radius: z.coerce.number().min(50).max(1000).default(400) });
const cityQuery = z.object({ city: z.enum(SUPPORTED_CITIES) });
const arrivalsQuery = cityQuery.extend({ stopUID: z.string().min(1).max(40) });
const railSystemQuery = z.object({ system: z.enum(RAIL_SYSTEMS) });
const railDeparturesQuery = railSystemQuery.extend({ stationID: z.string().min(1).max(20) });
const railNearbyQuery = z.object({ lat, lon, radius: z.coerce.number().min(100).max(3000).default(1500) });

/** 給 App 的精簡 API。所有 /v1 路徑都需要 App 金鑰。 */
export function buildServer(deps: ServerDependencies): FastifyInstance {
  // 不用 Fastify 內建紀錄：預設會記錄完整網址，裡面有使用者的經緯度。
  const app = Fastify({ logger: false });
  const log = deps.log ?? (() => undefined);
  const now = deps.now ?? Date.now;
  const limit = deps.rateLimitPerMinute ?? 60;
  const hits = new Map<string, { windowStart: number; count: number }>();
  const expectedKey = Buffer.from(deps.appApiKey);

  app.addHook('onRequest', async (request, reply) => {
    if (!request.url.startsWith('/v1/')) return;
    const provided = Buffer.from(String(request.headers['x-app-key'] ?? ''));
    if (provided.length !== expectedKey.length || !timingSafeEqual(provided, expectedKey)) {
      return reply.code(401).send({ error: 'unauthorized' });
    }
    const key = request.ip;
    const entry = hits.get(key);
    const time = now();
    if (!entry || time - entry.windowStart >= 60_000) {
      hits.set(key, { windowStart: time, count: 1 });
    } else if (++entry.count > limit) {
      return reply.code(429).send({ error: 'too_many_requests' });
    }
  });

  // 只記錄方法、路由樣板與狀態碼，不含查詢參數（位置）。
  app.addHook('onResponse', async (request, reply) => {
    log(`${request.method} ${request.routeOptions.url ?? 'unknown'} ${reply.statusCode}`);
  });

  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof z.ZodError) {
      return reply.code(400).send({ error: 'invalid_request', issues: error.issues.map((issue) => issue.path.join('.')) });
    }
    log(`error: ${error instanceof Error ? error.message : String(error)}`);
    return reply.code(502).send({ error: 'upstream_unavailable' });
  });

  app.get('/health', async () => ({
    ok: true,
    mqttConnected: deps.alerts.mqttConnected,
    staticData: deps.staticData.loadedCities(),
  }));

  // TDX 用量（需 App 金鑰）：今天與最近幾天各類 API 的實際請求數、限流與失敗次數。
  app.get('/v1/usage', async () => deps.usage?.snapshot() ?? { since: null, days: [] });

  app.get('/v1/journeys', async (request) => {
    const q = journeyQuery.parse(request.query);
    return deps.journeys.findJourneys({ lat: q.originLat, lon: q.originLon }, { lat: q.destinationLat, lon: q.destinationLon });
  });

  app.get('/v1/stops/nearby', async (request) => {
    const q = nearbyQuery.parse(request.query);
    return { stops: await deps.journeys.nearbyStops({ lat: q.lat, lon: q.lon }, q.radius) };
  });

  app.get('/v1/arrivals', async (request) => {
    const q = arrivalsQuery.parse(request.query);
    const arrivals = await deps.arrivals.arrivals(q.city, [q.stopUID]);
    return { generatedAt: new Date(now()).toISOString(), arrivals: arrivals.get(q.stopUID) ?? [] };
  });

  app.get('/v1/alerts', async (request) => {
    const q = cityQuery.parse(request.query);
    return { alerts: await deps.alerts.active(q.city), mqttConnected: deps.alerts.mqttConnected };
  });

  // 跨運具方案（MaaS；公車段盡量補上即時到站）
  app.get('/v1/plan', async (request) => {
    const q = journeyQuery.parse(request.query);
    return deps.planner.plan({ lat: q.originLat, lon: q.originLon }, { lat: q.destinationLat, lon: q.destinationLon });
  });

  // 軌道（臺鐵、高鐵、捷運）
  app.get('/v1/rail/stations/nearby', async (request) => {
    const q = railNearbyQuery.parse(request.query);
    return { stations: await deps.railStations.nearby({ lat: q.lat, lon: q.lon }, q.radius) };
  });

  app.get('/v1/rail/departures', async (request) => {
    const q = railDeparturesQuery.parse(request.query);
    return deps.railDepartures.departures(q.system, q.stationID);
  });

  app.get('/v1/rail/alerts', async (request) => {
    const q = railSystemQuery.parse(request.query);
    return deps.railAlerts.alerts(q.system);
  });

  return app;
}
