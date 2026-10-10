import { taipeiNow } from '../domain/taipeiTime.js';

export interface CategoryUsage {
  /** 實際送出的請求數（含重試）。 */
  requests: number;
  /** 被 TDX 限流（HTTP 429）的次數。 */
  rateLimited: number;
  /** 其他失敗（4xx／5xx、逾時、網路錯誤）。 */
  failed: number;
}

export interface DailyUsage {
  /** 臺北日期 yyyy-MM-dd */
  date: string;
  total: CategoryUsage;
  byCategory: Record<string, CategoryUsage>;
}

const empty = (): CategoryUsage => ({ requests: 0, rateLimited: 0, failed: 0 });

/**
 * TDX 用量統計（計畫 Phase 3：計算 API 使用量）。依臺北日期、API 類別計數，只存在記憶體，
 * 保留最近 maxDays 天；容器重啟會歸零。不記錄查詢參數（使用者位置）。
 */
export class UsageMeter {
  private readonly days = new Map<string, DailyUsage>();
  private readonly startedAt: number;

  constructor(private readonly now: () => number = Date.now, private readonly maxDays = 7) {
    this.startedAt = now();
  }

  /** @param status HTTP 狀態碼；網路錯誤或逾時為 undefined。 */
  record(category: string, status: number | undefined): void {
    const date = taipeiNow(this.now()).date;
    let day = this.days.get(date);
    if (!day) {
      day = { date, total: empty(), byCategory: {} };
      this.days.set(date, day);
      for (const old of [...this.days.keys()].sort().slice(0, Math.max(0, this.days.size - this.maxDays))) this.days.delete(old);
    }
    const bucket = (day.byCategory[category] ??= empty());
    for (const target of [bucket, day.total]) {
      target.requests += 1;
      if (status === 429) target.rateLimited += 1;
      else if (status === undefined || status >= 400) target.failed += 1;
    }
  }

  snapshot(): { since: string; days: DailyUsage[] } {
    return {
      since: new Date(this.startedAt).toISOString(),
      days: [...this.days.values()].sort((a, b) => b.date.localeCompare(a.date)),
    };
  }
}

/**
 * 路徑換成類別，不含縣市、站號等參數：
 * /v2/Bus/EstimatedTimeOfArrival/City/Taipei → Bus/EstimatedTimeOfArrival；
 * /v2/Rail/TRA/LiveBoard → Rail/TRA/LiveBoard；/routing（MaaS）→ MaaS/routing。
 */
export function usageCategory(path: string, prefix?: string): string {
  const segments = path.split('?')[0]!.split('/').filter(Boolean);
  if (/^v\d+$/i.test(segments[0] ?? '')) segments.shift();
  const depth = segments[0] === 'Rail' ? 3 : 2;
  const category = segments.slice(0, depth).join('/') || 'unknown';
  return prefix ? `${prefix}/${category}` : category;
}
