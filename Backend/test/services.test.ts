import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, expect, it, vi } from 'vitest';
import { cityFromTopic, alertTopic } from '../src/mqtt/alertSubscriber.js';
import { AlertStore } from '../src/services/alerts.js';
import { ArrivalService, toArrival } from '../src/services/arrivals.js';
import { buildCandidate, ESTIMATED_SECONDS_PER_STOP } from '../src/services/journeys.js';
import { findNearbyStops, findOppositeStop, matchDirectRoutes } from '../src/services/matching.js';
import { buildCityData, routeKey, StaticDataStore } from '../src/services/staticData.js';
import { parseList, tdxEstimate, tdxRoute, tdxStop, tdxStopOfRoute } from '../src/tdx/types.js';
import * as fx from './fixtures.js';

const taipei = () =>
  buildCityData(
    'Taipei',
    parseList(tdxStop, fx.stops).items,
    parseList(tdxStopOfRoute, fx.stopOfRoutes).items,
    parseList(tdxRoute, fx.routes).items,
    0,
  );
const cityHall = { lat: 25.0409, lon: 121.5655 };
const mainStation = { lat: 25.0478, lon: 121.517 };

describe('static data', () => {
  it('skips malformed rows instead of failing the batch', () => {
    const parsed = parseList(tdxStop, fx.stops);
    expect(parsed.items).toHaveLength(5);
    expect(parsed.skipped).toBe(1);
  });

  it('indexes stops, route directions and headsigns', () => {
    const data = taipei();
    const outbound = data.routes.get(routeKey('TPE265', 'TPE265A', 0));
    expect(outbound?.headsign).toBe('往台北車站');
    expect(data.routes.get(routeKey('TPE265', 'TPE265A', 1))?.headsign).toBe('往松山');
    expect(data.routesByStop.get('TPE1003')).toEqual([{ routeKey: 'TPE265|TPE265A|0', sequence: 2, boarding: 0 }]);
  });

  // 真實資料重現：臺北市 Headsign 為空時，返程不可用路線層級的終點站（會把方向說反）。
  it('uses each direction\'s own last stop when Headsign is missing', () => {
    const noHeadsign = [{ RouteUID: 'TPE265', RouteName: { Zh_tw: '265' }, DestinationStopNameZh: '台北車站', SubRoutes: [
      { SubRouteUID: 'TPE265A', Direction: 0, Headsign: null }, { SubRouteUID: 'TPE265A', Direction: 1, Headsign: null },
    ] }];
    const data = buildCityData('Taipei', parseList(tdxStop, fx.stops).items, parseList(tdxStopOfRoute, fx.stopOfRoutes).items,
      parseList(tdxRoute, noHeadsign).items, 0);
    expect(data.routes.get(routeKey('TPE265', 'TPE265A', 0))?.headsign).toBe('往台北車站');
    expect(data.routes.get(routeKey('TPE265', 'TPE265A', 1))?.headsign).toBe('往市政府');
  });

  it('downloads once and serves from disk cache afterwards', async () => {
    const dataDir = await mkdtemp(path.join(tmpdir(), 'yibuda-'));
    const api = {
      get: vi.fn(async (p: string) => (p.includes('StopOfRoute') ? fx.stopOfRoutes : p.includes('Route') ? fx.routes : fx.stops)),
    };
    const first = new StaticDataStore(api, { dataDir, now: () => 1000 });
    await first.get('Taipei');
    expect(api.get).toHaveBeenCalledTimes(3);

    const second = new StaticDataStore(api, { dataDir, now: () => 2000 });
    const data = await second.get('Taipei');
    expect(api.get).toHaveBeenCalledTimes(3);
    expect(data.stops).toHaveLength(5);
  });
});

describe('matching', () => {
  it('finds nearby stops sorted by distance', () => {
    const nearby = findNearbyStops([taipei()], cityHall, 200);
    expect(nearby.map((n) => n.stop.uid).sort()).toEqual(['TPE1001', 'TPE1002']);
  });

  // 計畫 4.1：上車站要先於下車站、方向相符；同名反向站牌不能當成可搭。
  it('only matches routes going the right direction', () => {
    const data = taipei();
    const candidates = matchDirectRoutes([data], findNearbyStops([data], cityHall, 300), findNearbyStops([data], mainStation, 300));
    expect(candidates).toHaveLength(1);
    expect(candidates[0]?.route.routeKey).toBe('TPE265|TPE265A|0');
    expect(candidates[0]?.boarding.stop.uid).toBe('TPE1001');
    expect(candidates[0]?.alighting.stop.uid).toBe('TPE1004');
    expect(candidates[0]?.stopCount).toBe(2);
  });

  // 真實資料重現（臺北市政府 → 臺北車站）：原本附近站牌只取 50 筆，市區同一根站牌每條路線各有一筆，
  // 前 50 筆只涵蓋 3 個站名，導致漏掉路線。
  it('does not truncate nearby stops used for matching', () => {
    const base = taipei();
    const crowd = Array.from({ length: 80 }, (_, i) => ({
      ...base.stopsByUID.get('TPE1002')!, uid: `CROWD${i}`, lat: 25.04092 + i * 0.000001,
    }));
    const data = { ...base, stops: [...crowd, ...base.stops] };
    const origin = findNearbyStops([data], cityHall, 300);
    expect(origin.length).toBeGreaterThan(80);
    const candidates = matchDirectRoutes([data], origin, findNearbyStops([data], mainStation, 300));
    expect(candidates.map((c) => c.route.routeName)).toContain('265');
  });

  it('merges same-name sub-routes from the same boarding station into one option', () => {
    const base = taipei();
    const twin = { ...base.routes.get('TPE265|TPE265A|0')!, routeKey: 'TPE265|TPE265B|0', subRouteUID: 'TPE265B' };
    const routes = new Map(base.routes).set(twin.routeKey, twin);
    const routesByStop = new Map(base.routesByStop);
    for (const [uid, refs] of base.routesByStop) {
      const extra = refs.filter((r) => r.routeKey === 'TPE265|TPE265A|0').map((r) => ({ ...r, routeKey: twin.routeKey }));
      routesByStop.set(uid, [...refs, ...extra]);
    }
    const data = { ...base, routes, routesByStop };
    const candidates = matchDirectRoutes([data], findNearbyStops([data], cityHall, 300), findNearbyStops([data], mainStation, 300));
    expect(candidates.filter((c) => c.route.routeName === '265')).toHaveLength(1);
  });

  it('never boards at an alight-only stop', () => {
    const data = taipei();
    const candidates = matchDirectRoutes([data], findNearbyStops([data], cityHall, 300), findNearbyStops([data], mainStation, 300));
    expect(candidates.some((c) => c.route.routeUID === 'TPE900')).toBe(false);
  });

  it('reverse trip uses the other side stop', () => {
    const data = taipei();
    const candidates = matchDirectRoutes([data], findNearbyStops([data], mainStation, 300), findNearbyStops([data], cityHall, 300));
    expect(candidates.map((c) => [c.boarding.stop.uid, c.alighting.stop.uid])).toEqual([['TPE1005', 'TPE1002']]);
  });

  // 真實資料重現（臺北「泉源3號橋」）：同一根站牌每條路線各有一個 StopUID，
  // 同站位的其他路線站牌不能被當成「對面」。
  it('never treats another route at the same pole (same StationID) as the opposite stop', () => {
    const qy = (uid: string, lat: number, lon: number, station: string, bearing: string) => ({
      StopUID: uid, StopName: { Zh_tw: '泉源3號橋' }, StopPosition: { PositionLat: lat, PositionLon: lon }, Bearing: bearing, StationID: station,
    });
    const data = buildCityData(
      'Taipei',
      parseList(tdxStop, [
        qy('TPE198097', 25.150204, 121.522434, '1165604756', 'SW'), // 小7 去程（上車站）
        qy('TPE217196', 25.15026, 121.522365, '1165604756', 'SW'), // 小8區，同一根站牌，相距 9 公尺
        qy('TPE207794', 25.149966, 121.522745, '1165606405', 'S'), // 小7 返程，對面，相距 41 公尺
      ]).items,
      parseList(tdxStopOfRoute, [
        { RouteUID: 'TPE7', RouteName: { Zh_tw: '小7' }, SubRouteUID: 'TPE7', Direction: 0, Stops: [{ StopUID: 'TPE198097', StopSequence: 5 }] },
        { RouteUID: 'TPE8Q', RouteName: { Zh_tw: '小8區' }, SubRouteUID: 'TPE8Q', Direction: 0, Stops: [{ StopUID: 'TPE217196', StopSequence: 3 }] },
        { RouteUID: 'TPE7', RouteName: { Zh_tw: '小7' }, SubRouteUID: 'TPE7', Direction: 1, Stops: [{ StopUID: 'TPE207794', StopSequence: 9 }] },
      ]).items,
      [],
      0,
    );
    const boarding = data.stopsByUID.get('TPE198097')!;
    expect(findOppositeStop(data, boarding, 'TPE7|TPE7|0')?.uid).toBe('TPE207794');
  });

  it('without StationID, requires real separation before calling a stop opposite', () => {
    const data = taipei();
    const boarding = { ...data.stopsByUID.get('TPE1001')!, stationID: null };
    const nearTwin = { ...boarding, uid: 'TPE1001B', lat: boarding.lat + 0.00005 };
    const withTwin = { ...data, stops: [...data.stops.map((s) => (s.uid === 'TPE1002' ? { ...s, stationID: null } : s)), nearTwin] };
    expect(findOppositeStop(withTwin, boarding, 'TPE265|TPE265A|0')?.uid).toBe('TPE1002');
  });

  it('finds the same-name stop across the road that this direction does not serve', () => {
    const data = taipei();
    const boarding = data.stopsByUID.get('TPE1001')!;
    expect(findOppositeStop(data, boarding, 'TPE265|TPE265A|0')?.uid).toBe('TPE1002');
  });
});

describe('arrivals', () => {
  const parse = (o: Record<string, unknown>) => toArrival(tdxEstimate.parse(fx.estimate(o)));

  it('computes absolute arrival time from source time', () => {
    const arrival = parse({});
    expect(arrival.status).toBe('normal');
    expect(arrival.arrivalAt).toBe(new Date(Date.parse('2026-10-09T08:00:00+08:00') + 300_000).toISOString());
  });

  it('never invents a time when TDX has none', () => {
    expect(parse({ EstimateTime: null, StopStatus: 1 })).toMatchObject({ arrivalAt: null, status: 'notDeparted' });
    expect(parse({ EstimateTime: null, StopStatus: 3 })).toMatchObject({ arrivalAt: null, status: 'lastBusPassed' });
    expect(parse({ EstimateTime: null, StopStatus: 4 })).toMatchObject({ arrivalAt: null, status: 'notOperating' });
    expect(parse({ PlateNumb: '-1', EstimateTime: 120 })).toMatchObject({ arrivalAt: null, status: 'noBus', plateNumber: null });
  });

  it('batches stops into one $filter request and caches briefly', async () => {
    let now = 0;
    const api = { get: vi.fn(async () => [fx.estimate({}), fx.estimate({ StopUID: 'TPE1004', EstimateTime: 900 })]) };
    const service = new ArrivalService(api, { now: () => now });
    const result = await service.arrivals('Taipei', ['TPE1001', 'TPE1004']);
    expect(api.get).toHaveBeenCalledTimes(1);
    expect(api.get.mock.calls[0]).toEqual([
      '/v2/Bus/EstimatedTimeOfArrival/City/Taipei',
      { $filter: "StopUID eq 'TPE1001' or StopUID eq 'TPE1004'" },
    ]);
    expect(result.get('TPE1004')).toHaveLength(1);

    now = 10_000;
    await service.arrivals('Taipei', ['TPE1001']);
    expect(api.get).toHaveBeenCalledTimes(1);
    now = 30_000;
    await service.arrivals('Taipei', ['TPE1001']);
    expect(api.get).toHaveBeenCalledTimes(2);
  });
});

describe('journey candidates', () => {
  const data = taipei();
  const [candidate] = matchDirectRoutes([data], findNearbyStops([data], cityHall, 300), findNearbyStops([data], mainStation, 300));

  it('uses the same vehicle for ride time when available', () => {
    const arrivals = new Map([
      ['TPE1001', [toArrival(tdxEstimate.parse(fx.estimate({ EstimateTime: 300 })))]],
      ['TPE1004', [toArrival(tdxEstimate.parse(fx.estimate({ StopUID: 'TPE1004', EstimateTime: 1020 })))]],
    ]);
    const dto = buildCandidate(candidate!, arrivals, data);
    expect(dto.rideSource).toBe('vehicle');
    expect(dto.rideSeconds).toBe(720);
    expect(dto.route.headsign).toBe('往台北車站');
    expect(dto.route.id).toBe('265');
    expect(dto.oppositeStop?.uid).toBe('TPE1002');
  });

  it('falls back to a labelled stop-count estimate', () => {
    const dto = buildCandidate(candidate!, new Map(), data);
    expect(dto.arrival).toBeNull();
    expect(dto.rideSource).toBe('stopCount');
    expect(dto.rideSeconds).toBe(2 * ESTIMATED_SECONDS_PER_STOP);
  });
});

describe('alerts', () => {
  it('ingests MQTT payloads (single or array) and filters inactive ones', async () => {
    const api = { get: vi.fn(async () => []) };
    const store = new AlertStore(api, { now: () => Date.parse('2026-10-09T08:00:00+08:00') });
    store.mqttConnected = true;
    expect(store.ingest('Taipei', fx.alert)).toBe(1);
    store.ingest('Taipei', [{ ...fx.alert, AlertID: 'A2', Status: 1 }, { ...fx.alert, AlertID: 'A3', EndTime: '2026-01-01T00:00:00+08:00' }, { bogus: true }]);
    const active = await store.active('Taipei');
    expect(active.map((a) => a.id)).toEqual(['A1']);
    expect(active[0]).toMatchObject({ effect: 1, routeIDs: ['265'], stopIDs: ['1001'] });
    expect(api.get).not.toHaveBeenCalled();
  });

  it('falls back to REST when MQTT is down', async () => {
    const api = { get: vi.fn(async () => [fx.alert]) };
    const store = new AlertStore(api, { now: () => Date.parse('2026-10-09T08:00:00+08:00') });
    const active = await store.active('Kaohsiung');
    expect(api.get).toHaveBeenCalledWith('/v2/Bus/Alert/City/Kaohsiung');
    expect(active).toHaveLength(1);
  });

  it('maps MQTT topics to cities', () => {
    expect(alertTopic('NewTaipei')).toBe('v2/Bus/Alert/City/NewTaipei');
    expect(cityFromTopic('v2/Bus/Alert/City/Keelung')).toBe('Keelung');
    expect(cityFromTopic('v2/Bus/Alert/City/Mars')).toBeUndefined();
  });
});
