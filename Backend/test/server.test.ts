import { describe, expect, it, vi } from 'vitest';
import { loadConfig } from '../src/config.js';
import { buildServer, type ServerDependencies } from '../src/http/server.js';

const KEY = 'test-app-key-0123456789abcdef';

function makeServer(overrides: Partial<ServerDependencies> = {}) {
  const logs: string[] = [];
  const deps = {
    appApiKey: KEY,
    journeys: {
      findJourneys: vi.fn(async () => ({ generatedAt: 'now', candidates: [] })),
      nearbyStops: vi.fn(async () => []),
    },
    arrivals: { arrivals: vi.fn(async () => new Map([['TPE1001', []]])) },
    alerts: { active: vi.fn(async () => []), mqttConnected: false },
    staticData: { loadedCities: () => ({ Taipei: '2026-10-09T00:00:00.000Z' }) },
    railStations: { nearby: vi.fn(async () => []) },
    railDepartures: { departures: vi.fn(async () => ({ system: 'TRTC', stationID: 'BL12', departures: [], note: null })) },
    railAlerts: { alerts: vi.fn(async () => ({ supported: true, alerts: [] })) },
    planner: { plan: vi.fn(async () => ({ generatedAt: 'now', routes: [] })) },
    log: (message: string) => logs.push(message),
    ...overrides,
  } as unknown as ServerDependencies;
  return { app: buildServer(deps), deps, logs };
}

const journeyUrl = '/v1/journeys?originLat=25.0409&originLon=121.5655&destinationLat=25.0478&destinationLon=121.517';

describe('HTTP API', () => {
  it('requires the app key on /v1 routes', async () => {
    const { app } = makeServer();
    expect((await app.inject({ url: journeyUrl })).statusCode).toBe(401);
    expect((await app.inject({ url: journeyUrl, headers: { 'x-app-key': 'wrong' } })).statusCode).toBe(401);
    expect((await app.inject({ url: journeyUrl, headers: { 'x-app-key': KEY } })).statusCode).toBe(200);
  });

  it('health is open and reports data status', async () => {
    const { app } = makeServer();
    const response = await app.inject({ url: '/health' });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ ok: true, mqttConnected: false });
  });

  it('validates input', async () => {
    const { app } = makeServer();
    const bad = await app.inject({ url: '/v1/journeys?originLat=abc', headers: { 'x-app-key': KEY } });
    expect(bad.statusCode).toBe(400);
    const badCity = await app.inject({ url: '/v1/alerts?city=Mars', headers: { 'x-app-key': KEY } });
    expect(badCity.statusCode).toBe(400);
  });

  it('validates rail systems and serves rail routes', async () => {
    const { app } = makeServer();
    const ok = await app.inject({ url: '/v1/rail/departures?system=TRTC&stationID=BL12', headers: { 'x-app-key': KEY } });
    expect(ok.statusCode).toBe(200);
    const bad = await app.inject({ url: '/v1/rail/departures?system=MRT&stationID=BL12', headers: { 'x-app-key': KEY } });
    expect(bad.statusCode).toBe(400);
    const nearby = await app.inject({ url: '/v1/rail/stations/nearby?lat=25.04&lon=121.51', headers: { 'x-app-key': KEY } });
    expect(nearby.statusCode).toBe(200);
    expect((await app.inject({ url: '/v1/rail/alerts?system=THSR' })).statusCode).toBe(401);
  });

  it('rate limits per client', async () => {
    const { app } = makeServer({ rateLimitPerMinute: 2 });
    const call = () => app.inject({ url: '/v1/alerts?city=Taipei', headers: { 'x-app-key': KEY } });
    expect((await call()).statusCode).toBe(200);
    expect((await call()).statusCode).toBe(200);
    expect((await call()).statusCode).toBe(429);
  });

  // 計畫：不可在 Log 暴露使用者位置。
  it('never logs coordinates', async () => {
    const { app, logs } = makeServer();
    await app.inject({ url: journeyUrl, headers: { 'x-app-key': KEY } });
    expect(logs.join('\n')).toContain('GET /v1/journeys 200');
    expect(logs.join('\n')).not.toMatch(/25\.04|121\.5/);
  });

  it('hides upstream errors behind 502', async () => {
    const { app } = makeServer({
      journeys: { findJourneys: async () => { throw new Error('TDX down'); }, nearbyStops: async () => [] } as never,
    });
    const response = await app.inject({ url: journeyUrl, headers: { 'x-app-key': KEY } });
    expect(response.statusCode).toBe(502);
    expect(response.body).not.toContain('TDX down');
  });
});

describe('config', () => {
  const base = { TDX_CLIENT_ID: 'id', TDX_CLIENT_SECRET: 'very-secret-value', APP_API_KEY: KEY };

  it('defaults to the six requested cities and REST-only alerts', () => {
    const config = loadConfig(base);
    expect(config.CITIES).toEqual(['Taipei', 'NewTaipei', 'Keelung', 'Taoyuan', 'Taichung', 'Kaohsiung']);
    expect(config.mqtt).toBeUndefined();
  });

  it('rejects bad settings without echoing secrets', () => {
    expect(() => loadConfig({ ...base, APP_API_KEY: 'short' })).toThrow(/APP_API_KEY/);
    expect(() => loadConfig({ ...base, CITIES: 'Taipei,Mars' })).toThrow(/Mars/);
    try {
      loadConfig({ ...base, APP_API_KEY: 'short' });
    } catch (error) {
      expect(String(error)).not.toContain('very-secret-value');
    }
  });
});
