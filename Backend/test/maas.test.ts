import { readFileSync } from 'node:fs';
import { describe, expect, it, vi } from 'vitest';
import { MaasPlanner, maasTime, matchBusLeg, normalizeStopName, toPlanRoute, transitMode } from '../src/services/maasPlanner.js';
import { buildCityData } from '../src/services/staticData.js';
import { maasRoute } from '../src/tdx/maasTypes.js';
import { parseList, tdxRoute, tdxStop, tdxStopOfRoute } from '../src/tdx/types.js';

/** 2026-10-10 以真實金鑰取得的 MaaS 回應（泉源3號橋附近 → 臺北車站，公開路線資訊）。 */
const sample = JSON.parse(readFileSync(new URL('./fixtures/maas-quanyuan-to-taipei.json', import.meta.url), 'utf8'));

/** 依真實站位座標合成的 TDX 靜態資料：小26 返程（往北投）經泉源3號橋南行站位到中央南路。 */
function taipeiData({ withReverse = true } = {}) {
  const stop = (uid: string, name: string, lat: number, lon: number, station: string) => ({
    StopUID: uid, StopName: { Zh_tw: name }, StopPosition: { PositionLat: lat, PositionLon: lon }, StationID: station,
  });
  return buildCityData(
    'Taipei',
    parseList(tdxStop, [
      stop('TPE207800', '泉源3號橋', 25.149966, 121.522745, 'S-SOUTH'), // 小26 往北投（正確方向）
      stop('TPE300001', '泉源3號橋', 25.150204, 121.522434, 'S-WEST'), // 小26 往頂湖（反方向）
      stop('TPE300002', '中央南路', 25.132154, 121.50132, 'S-C1'), // 座標同真實 MaaS 回應
    ]).items,
    parseList(tdxStopOfRoute, [
      { RouteUID: 'TPE26', RouteName: { Zh_tw: '小26' }, SubRouteUID: 'TPE26', Direction: 1,
        Stops: [{ StopUID: 'TPE207800', StopSequence: 5 }, { StopUID: 'TPE300002', StopSequence: 18 }] },
      ...(withReverse
        ? [{ RouteUID: 'TPE26', RouteName: { Zh_tw: '小26' }, SubRouteUID: 'TPE26', Direction: 0,
             Stops: [{ StopUID: 'TPE300002', StopSequence: 3 }, { StopUID: 'TPE300001', StopSequence: 16 }] }]
        : []),
    ]).items,
    parseList(tdxRoute, []).items,
    0,
  );
}

describe('MaaS response mapping (real sample)', () => {
  const routes = parseList(maasRoute, sample.data.routes).items;

  it('parses every real route', () => {
    expect(routes).toHaveLength(3);
  });

  it('maps sections to walk / wait / transit legs', () => {
    const plan = toPlanRoute(routes[0]!, 0)!;
    expect(plan.legs.map((leg) => (leg.kind === 'transit' ? `${leg.kind}:${leg.mode}:${leg.line}` : leg.kind))).toEqual([
      'walk', 'transit:bus:小26', 'walk', 'wait', 'transit:metro:淡水信義線', 'walk', 'walk',
    ]);
    const bus = plan.legs[1];
    expect(bus?.kind === 'transit' && bus.from.name).toBe('泉源3號橋');
    expect(bus?.kind === 'transit' && bus.stops.length).toBeGreaterThan(5);
    expect(plan.legs[5]).toMatchObject({ kind: 'walk', inStation: true });
    expect(plan.transfers).toBe(1);
  });

  it('treats MaaS times as Taipei local time', () => {
    expect(maasTime('2026-10-12T08:20:00')).toBe('2026-10-12T00:20:00.000Z');
    expect(maasTime('2026-10-12T08:20:00.0000000+08:00')).toBe('2026-10-12T00:20:00.000Z');
    expect(maasTime(null)).toBeNull();
  });

  it('drops routes that use taxi or bike legs', () => {
    const withTaxi = { ...routes[0]!, sections: [{ ...routes[0]!.sections[0]!, type: 'drive' }, ...routes[0]!.sections.slice(1)] };
    expect(toPlanRoute(withTaxi, 0)).toBeUndefined();
  });

  it('normalises modes and stop names', () => {
    expect(transitMode('MRT')).toBe('metro');
    expect(transitMode('TRA')).toBe('tra');
    expect(transitMode('Bus')).toBe('bus');
    expect(normalizeStopName('臺北車站（忠孝）')).toBe(normalizeStopName('台北車站(忠孝)'));
  });
});

describe('matching MaaS bus legs to TDX stops', () => {
  const plan = toPlanRoute(parseList(maasRoute, sample.data.routes).items[0]!, 0)!;
  const bus = plan.legs.find((leg) => leg.kind === 'transit' && leg.mode === 'bus');

  it('matches the correct-direction pole, not the same-name pole across the road', () => {
    if (bus?.kind !== 'transit') throw new Error('no bus leg');
    const match = matchBusLeg([taipeiData()], bus.line, bus.from, bus.to);
    expect(match?.boarding.uid).toBe('TPE207800');
  });

  it('does not match when no direction of the route goes from boarding to alighting', () => {
    if (bus?.kind !== 'transit') throw new Error('no bus leg');
    // 只有往北投的方向：反向行程（中央南路 → 泉源3號橋）不可對到任何站牌
    expect(matchBusLeg([taipeiData({ withReverse: false })], bus.line, bus.to, bus.from)).toBeUndefined();
  });

  it('a reverse trip matches the pole on the other side of the road', () => {
    if (bus?.kind !== 'transit') throw new Error('no bus leg');
    expect(matchBusLeg([taipeiData()], bus.line, bus.to, bus.from)?.boarding.uid).toBe('TPE300002');
  });

  it('planner attaches real-time arrival to matched bus legs and calls MaaS with walking-only options', async () => {
    const maas = { get: vi.fn(async () => sample) };
    const staticData = { get: vi.fn(async () => taipeiData()) };
    const arrivals = {
      arrivals: vi.fn(async () =>
        new Map([['TPE207800', [{ routeUID: 'TPE26', subRouteUID: 'TPE26', stopUID: 'TPE207800', plateNumber: 'ABC', arrivalAt: '2026-10-12T00:21:00.000Z', status: 'normal', isLastBus: false, dataTime: null }]]]),
      ),
    };
    const planner = new MaasPlanner(maas, staticData as never, arrivals as never, ['Taipei']);
    const result = await planner.plan({ lat: 25.1501, lon: 121.5222 }, { lat: 25.0478, lon: 121.517 });

    const query = maas.get.mock.calls[0]?.[1] as Record<string, string>;
    expect(query).toMatchObject({ first_mile_mode: '0', last_mile_mode: '0', transit: '3,4,5,6,7' });
    const busLeg = result.routes[0]!.legs.find((leg) => leg.kind === 'transit' && leg.mode === 'bus');
    expect(busLeg?.kind === 'transit' && busLeg.realtime?.arrival?.arrivalAt).toBe('2026-10-12T00:21:00.000Z');
    const metroLeg = result.routes[0]!.legs.find((leg) => leg.kind === 'transit' && leg.mode === 'metro');
    expect(metroLeg?.kind === 'transit' && metroLeg.realtime).toBeNull();
  });

  it('reports MaaS failures instead of returning an empty plan', async () => {
    const maas = { get: vi.fn(async () => ({ result: 'fail', error: { code: 20001, msg: 'origin is required' } })) };
    const planner = new MaasPlanner(maas, { get: vi.fn() } as never, { arrivals: vi.fn() } as never, ['Taipei']);
    await expect(planner.plan({ lat: 0, lon: 0 }, { lat: 0, lon: 0 })).rejects.toThrow(/origin is required/);
  });
});
