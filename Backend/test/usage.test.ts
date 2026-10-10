import { describe, expect, it, vi } from 'vitest';
import { TdxClient } from '../src/tdx/client.js';
import { UsageMeter, usageCategory } from '../src/tdx/usage.js';

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status });

describe('usageCategory', () => {
  it('drops version, city and station parameters', () => {
    expect(usageCategory('/v2/Bus/EstimatedTimeOfArrival/City/Taipei')).toBe('Bus/EstimatedTimeOfArrival');
    expect(usageCategory('/v2/Rail/TRA/LiveBoard/Station/1000')).toBe('Rail/TRA/LiveBoard');
    expect(usageCategory('/routing', 'MaaS')).toBe('MaaS/routing');
  });
});

describe('UsageMeter', () => {
  it('counts per Taipei day and category, with 429 and failures', () => {
    // 2026-10-09T16:30Z 是臺北 10/10 00:30
    let now = Date.parse('2026-10-09T15:59:00Z');
    const meter = new UsageMeter(() => now);
    meter.record('Bus/Stop', 200);
    now = Date.parse('2026-10-09T16:30:00Z');
    meter.record('Bus/Stop', 429);
    meter.record('Bus/Stop', undefined);
    meter.record('MaaS/routing', 200);
    const { days } = meter.snapshot();
    expect(days.map((d) => d.date)).toEqual(['2026-10-10', '2026-10-09']);
    expect(days[0]!.total).toEqual({ requests: 3, rateLimited: 1, failed: 1 });
    expect(days[0]!.byCategory['Bus/Stop']).toEqual({ requests: 2, rateLimited: 1, failed: 1 });
  });

  it('keeps only the most recent days', () => {
    let now = Date.parse('2026-10-01T04:00:00Z');
    const meter = new UsageMeter(() => now, 2);
    for (let i = 0; i < 4; i += 1) {
      meter.record('Bus/Stop', 200);
      now += 24 * 60 * 60 * 1000;
    }
    expect(meter.snapshot().days.map((d) => d.date)).toEqual(['2026-10-04', '2026-10-03']);
  });

  it('TdxClient records every attempt including retries, without query values', async () => {
    const meter = new UsageMeter();
    const fetch = vi.fn().mockResolvedValueOnce(json({}, 429)).mockResolvedValueOnce(json([]));
    const client = new TdxClient({ tokens: { token: async () => 't', invalidate: () => undefined }, fetch, usage: meter,
      sleep: async () => undefined, minIntervalMs: 0 });
    await client.get('/v2/Bus/EstimatedTimeOfArrival/City/Taipei', { $filter: "StopUID eq 'TPE1'" });
    const today = meter.snapshot().days[0]!;
    expect(today.byCategory).toEqual({ 'Bus/EstimatedTimeOfArrival': { requests: 2, rateLimited: 1, failed: 0 } });
    expect(JSON.stringify(meter.snapshot())).not.toContain('TPE1');
  });
});

describe('RequestThrottle', () => {
  it('doubles the interval on 429 (capped) and recovers after successes', async () => {
    const { RequestThrottle } = await import('../src/tdx/throttle.js');
    const throttle = new RequestThrottle({ baseIntervalMs: 300, maxIntervalMs: 1000, recoverAfter: 2 });
    throttle.rateLimited();
    expect(throttle.currentIntervalMs).toBe(600);
    throttle.rateLimited();
    throttle.rateLimited();
    expect(throttle.currentIntervalMs).toBe(1000);
    throttle.succeeded();
    throttle.succeeded();
    expect(throttle.currentIntervalMs).toBe(750);
    for (let i = 0; i < 20; i += 1) throttle.succeeded();
    expect(throttle.currentIntervalMs).toBe(300);
  });

  it('is shared: two clients never exceed the combined concurrency', async () => {
    const { RequestThrottle } = await import('../src/tdx/throttle.js');
    const throttle = new RequestThrottle({ maxConcurrent: 1, baseIntervalMs: 0 });
    let inFlight = 0;
    let peak = 0;
    const fetch = vi.fn(async () => {
      inFlight += 1;
      peak = Math.max(peak, inFlight);
      await new Promise((resolve) => setTimeout(resolve, 5));
      inFlight -= 1;
      return json([]);
    });
    const tokens = { token: async () => 't', invalidate: () => undefined };
    const a = new TdxClient({ tokens, fetch, throttle });
    const b = new TdxClient({ tokens, fetch, throttle, baseUrl: 'https://example.com', odataFormat: false });
    await Promise.all([a.get('/x'), b.get('/y'), a.get('/z')]);
    expect(peak).toBe(1);
  });
});
