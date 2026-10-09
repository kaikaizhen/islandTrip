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
