/** 官方 token 端點（tdxmotc/SampleCode）。 */
export const TDX_TOKEN_URL = 'https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token';

export interface TokenSource {
  token(): Promise<string>;
  /** API 回 401 時呼叫，下次重新取得。 */
  invalidate(): void;
}

export interface TokenProviderOptions {
  clientId: string;
  clientSecret: string;
  fetch?: typeof fetch;
  now?: () => number;
  /** 官方建議 4–6 小時更新一次。 */
  refreshAfterMs?: number;
}

/**
 * TDX access token：快取並定期更新；同時多個請求只會取一次。
 * 不記錄 token 或 secret。
 */
export class TdxTokenProvider implements TokenSource {
  private cached?: { token: string; usableUntil: number };
  private inflight?: Promise<string>;
  private readonly fetchImpl: typeof fetch;
  private readonly now: () => number;
  private readonly refreshAfterMs: number;

  constructor(private readonly options: TokenProviderOptions) {
    this.fetchImpl = options.fetch ?? fetch;
    this.now = options.now ?? Date.now;
    this.refreshAfterMs = options.refreshAfterMs ?? 5 * 60 * 60 * 1000;
  }

  async token(): Promise<string> {
    if (this.cached && this.now() < this.cached.usableUntil) return this.cached.token;
    this.inflight ??= this.fetchToken().finally(() => {
      this.inflight = undefined;
    });
    return this.inflight;
  }

  invalidate(): void {
    this.cached = undefined;
  }

  private async fetchToken(): Promise<string> {
    const body = new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: this.options.clientId,
      client_secret: this.options.clientSecret,
    });
    const response = await this.fetchImpl(TDX_TOKEN_URL, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body,
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) throw new Error(`TDX token request failed: HTTP ${response.status}`);
    const json = (await response.json()) as { access_token?: unknown; expires_in?: unknown };
    if (typeof json.access_token !== 'string') throw new Error('TDX token response missing access_token');
    const expiresInMs = (typeof json.expires_in === 'number' ? json.expires_in : 86_400) * 1000;
    // 在官方建議的更新時間與實際到期前 1 分鐘，取較早者。
    const usableFor = Math.min(this.refreshAfterMs, expiresInMs - 60_000);
    this.cached = { token: json.access_token, usableUntil: this.now() + usableFor };
    return json.access_token;
  }
}
