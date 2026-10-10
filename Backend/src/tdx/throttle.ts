/**
 * TDX 請求閘門：限制同時請求數與兩次請求的最短間隔。
 * TDX 依會員方案限制每把金鑰的呼叫頻率（官方未公開固定數字），所以間隔會自動調整：
 * 收到 429 就加倍（上限 maxIntervalMs），連續成功後再慢慢縮回 baseIntervalMs。
 * 同一把金鑰的所有用戶端（一般 API、MaaS）必須共用同一個閘門。
 */
export class RequestThrottle {
  private active = 0;
  private nextStartAt = 0;
  private readonly waiting: (() => void)[] = [];
  private interval: number;
  private successStreak = 0;

  constructor(
    private readonly options: {
      maxConcurrent?: number;
      baseIntervalMs?: number;
      maxIntervalMs?: number;
      /** 連續成功幾次後縮短間隔。 */
      recoverAfter?: number;
      now?: () => number;
      sleep?: (ms: number) => Promise<void>;
    } = {},
  ) {
    this.interval = this.base;
  }

  private get base(): number {
    return this.options.baseIntervalMs ?? 300;
  }

  private get now(): number {
    return (this.options.now ?? Date.now)();
  }

  /** 目前的請求間隔（毫秒），給狀態與測試用。 */
  get currentIntervalMs(): number {
    return this.interval;
  }

  async acquire(): Promise<void> {
    if (this.active >= (this.options.maxConcurrent ?? 2)) {
      await new Promise<void>((resolve) => this.waiting.push(resolve));
    }
    this.active += 1;
    const wait = this.nextStartAt - this.now;
    this.nextStartAt = Math.max(this.now, this.nextStartAt) + this.interval;
    if (wait > 0) await (this.options.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms))))(wait);
  }

  release(): void {
    this.active -= 1;
    this.waiting.shift()?.();
  }

  /** 被限流：拉長間隔。 */
  rateLimited(): void {
    this.successStreak = 0;
    this.interval = Math.min(this.options.maxIntervalMs ?? 3000, this.interval * 2);
  }

  succeeded(): void {
    if (this.interval <= this.base) return;
    this.successStreak += 1;
    if (this.successStreak >= (this.options.recoverAfter ?? 20)) {
      this.successStreak = 0;
      this.interval = Math.max(this.base, Math.round(this.interval * 0.75));
    }
  }
}
