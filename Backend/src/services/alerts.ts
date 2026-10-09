import type { City } from '../domain/cities.js';
import type { TdxApi } from '../tdx/client.js';
import { parseList, tdxAlert, type TdxAlert } from '../tdx/types.js';

export interface AlertDTO {
  id: string;
  city: City;
  title: string;
  description: string;
  /** 0 全部停止、1 全部正常、2 有異常。 */
  status: number | null;
  /** 1 改道／站牌不停靠、3 班次減少、4 班次取消、6 站點異動、7 重大延遲… */
  effect: number | null;
  routeIDs: string[];
  stopIDs: string[];
  url: string | null;
  startTime: string | null;
  endTime: string | null;
  updatedAt: string | null;
}

export function toAlertDTO(city: City, alert: TdxAlert): AlertDTO {
  return {
    id: alert.AlertID,
    city,
    title: alert.Title ?? '公車營運消息',
    description: alert.Description ?? '',
    status: alert.Status ?? null,
    effect: alert.Effect ?? null,
    routeIDs: (alert.Scope?.Routes ?? []).flatMap((route) => (route.RouteID ? [route.RouteID] : [])),
    stopIDs: (alert.Scope?.Stops ?? []).flatMap((stop) => (stop.StopID ? [stop.StopID] : [])),
    url: alert.AlertURL ?? null,
    startTime: alert.StartTime ?? null,
    endTime: alert.EndTime ?? null,
    updatedAt: alert.UpdateTime ?? null,
  };
}

export interface AlertStoreOptions {
  /** 這段時間沒有收到 MQTT 更新就改用 REST 補抓。 */
  staleAfterMs?: number;
  now?: () => number;
}

/**
 * 通阻／異常消息：平常由 MQTT 推播更新；MQTT 斷線或太久沒更新時，查詢時以 REST 補抓。
 * 只回傳「目前有效且不是全部正常」的消息。
 */
export class AlertStore {
  private readonly alerts = new Map<City, Map<string, AlertDTO>>();
  private readonly lastUpdate = new Map<City, number>();
  private readonly staleAfterMs: number;
  private readonly now: () => number;
  mqttConnected = false;

  constructor(private readonly api: TdxApi, options: AlertStoreOptions = {}) {
    this.staleAfterMs = options.staleAfterMs ?? 10 * 60 * 1000;
    this.now = options.now ?? Date.now;
  }

  /** MQTT 訊息：單筆或陣列皆可；無法解析的內容略過。 */
  ingest(city: City, payload: unknown): number {
    const items = Array.isArray(payload) ? payload : [payload];
    const parsed = parseList(tdxAlert, items).items;
    const map = this.alerts.get(city) ?? new Map<string, AlertDTO>();
    for (const alert of parsed) map.set(alert.AlertID, toAlertDTO(city, alert));
    this.alerts.set(city, map);
    if (parsed.length > 0) this.lastUpdate.set(city, this.now());
    return parsed.length;
  }

  async active(city: City): Promise<AlertDTO[]> {
    const last = this.lastUpdate.get(city);
    if (!this.mqttConnected || last == null || this.now() - last > this.staleAfterMs) {
      await this.refreshFromRest(city);
    }
    const now = this.now();
    return [...(this.alerts.get(city)?.values() ?? [])].filter(
      (alert) => alert.status !== 1 && (alert.endTime == null || Date.parse(alert.endTime) > now),
    );
  }

  private async refreshFromRest(city: City): Promise<void> {
    const raw = await this.api.get(`/v2/Bus/Alert/City/${city}`);
    const parsed = parseList(tdxAlert, raw).items;
    // REST 回傳的是完整清單：整批取代。
    this.alerts.set(city, new Map(parsed.map((alert) => [alert.AlertID, toAlertDTO(city, alert)])));
    this.lastUpdate.set(city, this.now());
  }
}
