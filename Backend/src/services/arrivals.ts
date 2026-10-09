import type { City } from '../domain/cities.js';
import type { TdxApi } from '../tdx/client.js';
import { parseList, tdxEstimate, type TdxEstimate } from '../tdx/types.js';

/** 到站狀態（對應 TDX StopStatus；PlateNumb = -1 表示目前無車）。 */
export type ArrivalStatus = 'normal' | 'notDeparted' | 'noStop' | 'lastBusPassed' | 'notOperating' | 'noBus' | 'unknown';

export interface Arrival {
  routeUID: string;
  subRouteUID: string | null;
  stopUID: string;
  plateNumber: string | null;
  /** 預估到站的絕對時間；沒有預估時為 null（不偽造）。 */
  arrivalAt: string | null;
  status: ArrivalStatus;
  isLastBus: boolean;
  /** 這筆預估的資料時間，App 用來判斷是否過期。 */
  dataTime: string | null;
}

const STATUS: Record<number, ArrivalStatus> = {
  0: 'normal',
  1: 'notDeparted',
  2: 'noStop',
  3: 'lastBusPassed',
  4: 'notOperating',
};

/**
 * 轉成 App 用的格式。官方說明：剩餘時間 = EstimateTime − (收到資料時間 − SrcTransTime)，
 * 所以以來源時間（SrcTransTime，沒有就用 SrcUpdateTime，再沒有用 UpdateTime）加上 EstimateTime 得到到站時刻。
 */
export function toArrival(estimate: TdxEstimate): Arrival {
  const dataTime = estimate.SrcTransTime ?? estimate.SrcUpdateTime ?? estimate.UpdateTime ?? null;
  const noBus = estimate.PlateNumb === '-1';
  const status: ArrivalStatus = noBus ? 'noBus' : (STATUS[estimate.StopStatus ?? -1] ?? 'unknown');
  const base = dataTime ? Date.parse(dataTime) : Number.NaN;
  const arrivalAt =
    estimate.EstimateTime != null && !Number.isNaN(base) && !noBus
      ? new Date(base + estimate.EstimateTime * 1000).toISOString()
      : null;
  return {
    routeUID: estimate.RouteUID,
    subRouteUID: estimate.SubRouteUID ?? null,
    stopUID: estimate.StopUID,
    plateNumber: noBus ? null : (estimate.PlateNumb ?? null),
    arrivalAt,
    status,
    isLastBus: estimate.IsLastBus ?? false,
    dataTime,
  };
}

export interface ArrivalServiceOptions {
  /** 同一站的預估在這段時間內共用，減少 TDX 呼叫次數。 */
  ttlMs?: number;
  /** 一次查詢最多幾個站（$filter 條件長度）。 */
  batchSize?: number;
  now?: () => number;
}

/** 依站牌查預估到站：同縣市的站一次批次查詢，並短暫快取。 */
export class ArrivalService {
  private readonly cache = new Map<string, { at: number; arrivals: Arrival[] }>();
  private readonly ttlMs: number;
  private readonly batchSize: number;
  private readonly now: () => number;

  constructor(private readonly api: TdxApi, options: ArrivalServiceOptions = {}) {
    this.ttlMs = options.ttlMs ?? 20_000;
    this.batchSize = options.batchSize ?? 15;
    this.now = options.now ?? Date.now;
  }

  async arrivals(city: City, stopUIDs: string[]): Promise<Map<string, Arrival[]>> {
    const result = new Map<string, Arrival[]>();
    const missing: string[] = [];
    for (const uid of new Set(stopUIDs)) {
      const cached = this.cache.get(`${city}|${uid}`);
      if (cached && this.now() - cached.at < this.ttlMs) result.set(uid, cached.arrivals);
      else missing.push(uid);
    }
    for (let index = 0; index < missing.length; index += this.batchSize) {
      const batch = missing.slice(index, index + this.batchSize);
      const filter = batch.map((uid) => `StopUID eq '${uid.replaceAll("'", "''")}'`).join(' or ');
      const raw = await this.api.get(`/v2/Bus/EstimatedTimeOfArrival/City/${city}`, { $filter: filter });
      const arrivals = parseList(tdxEstimate, raw).items.map(toArrival);
      const fetchedAt = this.now();
      for (const uid of batch) {
        const forStop = arrivals.filter((arrival) => arrival.stopUID === uid);
        this.cache.set(`${city}|${uid}`, { at: fetchedAt, arrivals: forStop });
        result.set(uid, forStop);
      }
    }
    return result;
  }
}
