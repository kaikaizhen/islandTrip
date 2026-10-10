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
