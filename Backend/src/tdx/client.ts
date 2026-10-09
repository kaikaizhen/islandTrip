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
  /** 同時進行的 TDX 請求上限（TDX 有頻率限制）。 */
  maxConcurrent?: number;
  /** 兩次請求開始之間的最短間隔（毫秒）。 */
  minIntervalMs?: number;
  now?: () => number;
  /** 是否加上 OData 的 $format=JSON（MaaS 不是 OData，不加）。 */
  odataFormat?: boolean;
}

/** TDX REST 用戶端：帶 Bearer token、gzip、逾時、退避重試；401 時重新取 token 再試一次。 */
export class TdxClient implements TdxApi {
  private readonly fetchImpl: typeof fetch;
  private readonly baseUrl: string;
  private readonly timeoutMs: number;
  private readonly maxRetries: number;
  private readonly sleep: (ms: number) => Promise<void>;
  private readonly maxConcurrent: number;
  private readonly minIntervalMs: number;
  private readonly now: () => number;
  private active = 0;
  private nextStartAt = 0;
  private readonly waiting: (() => void)[] = [];

  constructor(private readonly options: TdxClientOptions) {
    this.fetchImpl = options.fetch ?? fetch;
    this.baseUrl = options.baseUrl ?? TDX_API_BASE;
    this.timeoutMs = options.timeoutMs ?? 20_000;
    this.maxRetries = options.maxRetries ?? 3;
    this.sleep = options.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
    this.maxConcurrent = options.maxConcurrent ?? 2;
    this.minIntervalMs = options.minIntervalMs ?? 300;
    this.now = options.now ?? Date.now;
  }

  /** 取得送出請求的名額：同時上限＋最短間隔，避免觸發 TDX 的 429。 */
  private async acquire(): Promise<void> {
    if (this.active >= this.maxConcurrent) {
      await new Promise<void>((resolve) => this.waiting.push(resolve));
    }
    this.active += 1;
    const wait = this.nextStartAt - this.now();
    this.nextStartAt = Math.max(this.now(), this.nextStartAt) + this.minIntervalMs;
    if (wait > 0) await this.sleep(wait);
  }

  private release(): void {
    this.active -= 1;
    this.waiting.shift()?.();
  }

  async get(path: string, query: Record<string, string> = {}): Promise<unknown> {
    const url = new URL(this.baseUrl + path);
    if (this.options.odataFormat !== false) url.searchParams.set('$format', 'JSON');
    for (const [key, value] of Object.entries(query)) url.searchParams.set(key, value);

    let refreshedToken = false;
    for (let attempt = 0; ; attempt += 1) {
      let response: Response;
      await this.acquire();
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
        this.release();
        if (attempt < this.maxRetries) {
          await this.sleep(this.backoff(attempt));
          continue;
        }
        throw error;
      }
      this.release();

      if (response.ok) return response.json();
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
