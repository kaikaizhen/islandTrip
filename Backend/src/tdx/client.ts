import type { TokenSource } from './auth.js';
import { RequestThrottle } from './throttle.js';
import { usageCategory, type UsageMeter } from './usage.js';

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
  /** 共用的請求閘門（同一把金鑰的用戶端要共用）；未提供時依下面兩個參數自建。 */
  throttle?: RequestThrottle;
  /** 同時進行的 TDX 請求上限（TDX 有頻率限制）。 */
  maxConcurrent?: number;
  /** 兩次請求開始之間的最短間隔（毫秒）。 */
  minIntervalMs?: number;
  now?: () => number;
  /** 是否加上 OData 的 $format=JSON（MaaS 不是 OData，不加）。 */
  odataFormat?: boolean;
  /** 用量統計；未提供時不計。 */
  usage?: UsageMeter;
  /** 用量類別前綴，例：MaaS。 */
  usagePrefix?: string;
}

/** TDX REST 用戶端：帶 Bearer token、gzip、逾時、退避重試；401 時重新取 token 再試一次。 */
export class TdxClient implements TdxApi {
  private readonly fetchImpl: typeof fetch;
  private readonly baseUrl: string;
  private readonly timeoutMs: number;
  private readonly maxRetries: number;
  private readonly sleep: (ms: number) => Promise<void>;
  private readonly throttle: RequestThrottle;

  constructor(private readonly options: TdxClientOptions) {
    this.fetchImpl = options.fetch ?? fetch;
    this.baseUrl = options.baseUrl ?? TDX_API_BASE;
    this.timeoutMs = options.timeoutMs ?? 20_000;
    this.maxRetries = options.maxRetries ?? 3;
    this.sleep = options.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
    this.throttle =
      options.throttle ??
      new RequestThrottle({ maxConcurrent: options.maxConcurrent, baseIntervalMs: options.minIntervalMs, now: options.now, sleep: this.sleep });
  }

  async get(path: string, query: Record<string, string> = {}): Promise<unknown> {
    const url = new URL(this.baseUrl + path);
    if (this.options.odataFormat !== false) url.searchParams.set('$format', 'JSON');
    for (const [key, value] of Object.entries(query)) url.searchParams.set(key, value);

    let refreshedToken = false;
    for (let attempt = 0; ; attempt += 1) {
      let response: Response;
      await this.throttle.acquire();
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
        this.throttle.release();
        this.options.usage?.record(usageCategory(path, this.options.usagePrefix), undefined);
        if (attempt < this.maxRetries) {
          await this.sleep(this.backoff(attempt));
          continue;
        }
        throw error;
      }
      this.throttle.release();
      this.options.usage?.record(usageCategory(path, this.options.usagePrefix), response.status);

      if (response.status === 429) this.throttle.rateLimited();
      if (response.ok) {
        this.throttle.succeeded();
        return response.json();
      }
      if (response.status === 401 && !refreshedToken) {
        refreshedToken = true;
        this.options.tokens.invalidate();
        continue;
      }
      if ((response.status === 429 || response.status >= 500) && attempt < this.maxRetries) {
        // 429 時優先依伺服器的 Retry-After（秒）等待
        const retryAfter = Number(response.headers.get('retry-after'));
        await this.sleep(response.status === 429 && retryAfter > 0 ? retryAfter * 1000 : this.backoff(attempt));
        continue;
      }
      // 只回報路徑與狀態，不含 token 或查詢內容。
      throw new TdxError(response.status, `TDX ${path} failed: HTTP ${response.status}`);
    }
  }

  private backoff(attempt: number): number {
    return 1000 * 2 ** attempt;
  }
}
