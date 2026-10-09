import { describe, expect, it, vi } from 'vitest';
import { TDX_TOKEN_URL, TdxTokenProvider } from '../src/tdx/auth.js';
import { TdxClient, TdxError } from '../src/tdx/client.js';

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

describe('TdxTokenProvider', () => {
  it('posts client credentials to the official endpoint and caches the token', async () => {
    const fetch = vi.fn(async () => json({ access_token: 'tok-1', expires_in: 86400 }));
    const provider = new TdxTokenProvider({ clientId: 'id', clientSecret: 'secret', fetch });

    expect(await provider.token()).toBe('tok-1');
    expect(await provider.token()).toBe('tok-1');
    expect(fetch).toHaveBeenCalledTimes(1);

    const [url, init] = fetch.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe(TDX_TOKEN_URL);
    expect(String(init.body)).toContain('grant_type=client_credentials');
  });

  it('fetches only once for concurrent requests', async () => {
    const fetch = vi.fn(async () => json({ access_token: 'tok', expires_in: 86400 }));
    const provider = new TdxTokenProvider({ clientId: 'id', clientSecret: 'secret', fetch });
    await Promise.all([provider.token(), provider.token(), provider.token()]);
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it('refreshes after the recommended interval and after invalidate', async () => {
    let now = 0;
    let count = 0;
    const fetch = vi.fn(async () => json({ access_token: `tok-${++count}`, expires_in: 86400 }));
    const provider = new TdxTokenProvider({ clientId: 'id', clientSecret: 'secret', fetch, now: () => now });
    expect(await provider.token()).toBe('tok-1');
    now = 5 * 60 * 60 * 1000 + 1;
    expect(await provider.token()).toBe('tok-2');
    provider.invalidate();
    expect(await provider.token()).toBe('tok-3');
  });

  it('does not leak the secret in errors', async () => {
    const provider = new TdxTokenProvider({ clientId: 'id', clientSecret: 'super-secret', fetch: async () => json({}, 401) });
    await expect(provider.token()).rejects.toThrow(/HTTP 401/);
    await expect(provider.token()).rejects.not.toThrow(/super-secret/);
  });
});

describe('TdxClient', () => {
  const tokens = () => ({ token: vi.fn(async () => 'tok'), invalidate: vi.fn() });

  it('sends bearer token, JSON format and gzip', async () => {
    const fetch = vi.fn(async () => json([{ ok: true }]));
    const client = new TdxClient({ tokens: tokens(), fetch });
    await client.get('/v2/Bus/Stop/City/Taipei', { $top: '1' });
    const [url, init] = fetch.mock.calls[0] as unknown as [URL, RequestInit];
    expect(url.toString()).toContain('https://tdx.transportdata.tw/api/basic/v2/Bus/Stop/City/Taipei');
    expect(url.searchParams.get('$format')).toBe('JSON');
    expect(url.searchParams.get('$top')).toBe('1');
    expect((init.headers as Record<string, string>).authorization).toBe('Bearer tok');
    expect((init.headers as Record<string, string>)['accept-encoding']).toBe('br,gzip');
  });

  it('refreshes the token once on 401', async () => {
    const source = tokens();
    const fetch = vi.fn().mockResolvedValueOnce(json({}, 401)).mockResolvedValueOnce(json([]));
    await new TdxClient({ tokens: source, fetch }).get('/x');
    expect(source.invalidate).toHaveBeenCalledTimes(1);
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it('backs off and retries on 429, then succeeds', async () => {
    const sleep = vi.fn(async () => undefined);
    const fetch = vi.fn().mockResolvedValueOnce(json({}, 429)).mockResolvedValueOnce(json(['ok']));
    expect(await new TdxClient({ tokens: tokens(), fetch, sleep }).get('/x')).toEqual(['ok']);
    expect(sleep).toHaveBeenCalledWith(1000);
  });

  it('throws TdxError with only path and status', async () => {
    const fetch = vi.fn(async () => json({}, 404));
    const error = await new TdxClient({ tokens: tokens(), fetch }).get('/v2/x', { $filter: "StopUID eq 'secret-place'" }).catch((e) => e);
    expect(error).toBeInstanceOf(TdxError);
    expect(error.status).toBe(404);
    expect(error.message).not.toContain('secret-place');
  });
});

describe('TdxClient rate limiting', () => {
  const tokens = () => ({ token: vi.fn(async () => 'tok'), invalidate: vi.fn() });

  it('never runs more than maxConcurrent requests at once', async () => {
    let inFlight = 0;
    let peak = 0;
    const fetch = vi.fn(async () => {
      inFlight += 1;
      peak = Math.max(peak, inFlight);
      await new Promise((resolve) => setTimeout(resolve, 5));
      inFlight -= 1;
      return json([]);
    });
    const client = new TdxClient({ tokens: tokens(), fetch, maxConcurrent: 2, minIntervalMs: 0 });
    await Promise.all(Array.from({ length: 8 }, (_, i) => client.get(`/x/${i}`)));
    expect(fetch).toHaveBeenCalledTimes(8);
    expect(peak).toBe(2);
  });

  it('spaces request starts by minIntervalMs', async () => {
    let now = 0;
    const waits: number[] = [];
    const sleep = vi.fn(async (ms: number) => {
      waits.push(ms);
      now += ms;
    });
    const client = new TdxClient({ tokens: tokens(), fetch: async () => json([]), sleep, now: () => now, maxConcurrent: 1, minIntervalMs: 300 });
    await client.get('/a');
    await client.get('/b');
    await client.get('/c');
    expect(waits).toEqual([300, 300]);
  });

  it('honours Retry-After on 429', async () => {
    const sleep = vi.fn(async () => undefined);
    const fetch = vi
      .fn()
      .mockResolvedValueOnce(new Response('{}', { status: 429, headers: { 'retry-after': '3' } }))
      .mockResolvedValueOnce(json(['ok']));
    expect(await new TdxClient({ tokens: tokens(), fetch, sleep, minIntervalMs: 0 }).get('/x')).toEqual(['ok']);
    expect(sleep).toHaveBeenCalledWith(3000);
  });
});
