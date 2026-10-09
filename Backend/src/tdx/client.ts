import type { TokenSource } from './auth.js';

export const TDX_API_BASE = 'https://tdx.transportdata.tw/api/basic';

export class TdxError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

/** 呼叫 TDX REST 的抽象，服務層只依賴此介面，測試以假物件替代。 */
export interface TdxApi {
  get(path: string, query?: Record<string, string>): Promise<unknown>;
}

export interface TdxClientOptions {
  tokens: TokenSource;
  fetch?: typeof fetch;
  baseUrl?: string;
  timeoutMs?: number;
  /** 429 / 5xx / 網路錯誤的重試次數。 */
  maxRetries?: number;
  sleep?: (ms: number) => Promise<void>;
}

/** TDX REST 用戶端：帶 Bearer token、gzip、逾時、退避重試；401 時重新取 token 再試一次。 */
export class TdxClient implements TdxApi {
  private readonly fetchImpl: typeof fetch;
  private readonly baseUrl: string;
  private readonly timeoutMs: number;
  private readonly maxRetries: number;
  private readonly sleep: (ms: number) => Promise<void>;

  constructor(private readonly options: TdxClientOptions) {
    this.fetchImpl = options.fetch ?? fetch;
    this.baseUrl = options.baseUrl ?? TDX_API_BASE;
    this.timeoutMs = options.timeoutMs ?? 20_000;
    this.maxRetries = options.maxRetries ?? 2;
    this.sleep = options.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
  }

  async get(path: string, query: Record<string, string> = {}): Promise<unknown> {
    const url = new URL(this.baseUrl + path);
    url.searchParams.set('$format', 'JSON');
    for (const [key, value] of Object.entries(query)) url.searchParams.set(key, value);

    let refreshedToken = false;
    for (let attempt = 0; ; attempt += 1) {
      let response: Response;
      try {
        response = await this.fetchImpl(url, {
          headers: {
            authorization: `Bearer ${await this.options.tokens.token()}`,
            accept: 'application/json',
            'accept-encoding': 'br,gzip',
          },
          signal: AbortSignal.timeout(this.timeoutMs),
        });
      } catch (error) {
        if (attempt < this.maxRetries) {
          await this.sleep(this.backoff(attempt));
          continue;
        }
        throw error;
      }

      if (response.ok) return response.json();
      if (response.status === 401 && !refreshedToken) {
        refreshedToken = true;
        this.options.tokens.invalidate();
        continue;
      }
      if ((response.status === 429 || response.status >= 500) && attempt < this.maxRetries) {
        await this.sleep(this.backoff(attempt));
        continue;
      }
      // 只回報路徑與狀態，不含 token 或查詢內容。
      throw new TdxError(response.status, `TDX ${path} failed: HTTP ${response.status}`);
    }
  }

  private backoff(attempt: number): number {
    return 500 * 2 ** attempt;
  }
}
