import { METRO_CAPABILITIES, isMetro, type RailSystem } from '../domain/railSystems.js';
import type { TdxApi } from '../tdx/client.js';
import { metroAlertWrapper, thsrAlert } from '../tdx/railTypes.js';
import { parseList } from '../tdx/types.js';
import { TtlCache } from './ttlCache.js';

export interface RailAlertDTO {
  system: RailSystem;
  id: string;
  title: string;
  description: string;
  /** normal / disrupted / suspended */
  severity: 'normal' | 'disrupted' | 'suspended';
  effect: string | null;
  url: string | null;
  startTime: string | null;
  endTime: string | null;
}

export interface RailAlerts {
  /** false：此系統官方沒有提供通阻資料（或欄位尚未核對）。 */
  supported: boolean;
  alerts: RailAlertDTO[];
}

/** 軌道通阻：捷運（TRTC/KRTC/TYMC/TMRT）與高鐵依官方欄位；臺鐵 v3 欄位尚未核對，暫不提供。 */
export class RailAlertService {
  private readonly cache: TtlCache<unknown>;

  constructor(private readonly api: TdxApi, private readonly now: () => number = Date.now) {
    this.cache = new TtlCache(5 * 60 * 1000, now);
  }

  async alerts(system: RailSystem): Promise<RailAlerts> {
    if (system === 'THSR') {
      const raw = await this.cache.get('THSR', () => this.api.get('/v2/Rail/THSR/AlertInfo'));
      const alerts = parseList(thsrAlert, raw).items.map((alert) => ({
        system,
        id: alert.AlertID,
        title: alert.Title ?? '高鐵營運消息',
        description: alert.Description ?? '',
        severity: thsrSeverity(alert.Status),
        effect: alert.Effect ?? null,
        url: alert.AlertURL ?? null,
        startTime: alert.StartTime ?? null,
        endTime: alert.EndTime ?? null,
      }));
      return { supported: true, alerts: this.active(alerts) };
    }
    if (isMetro(system) && METRO_CAPABILITIES[system].alert) {
      const raw = await this.cache.get(system, () => this.api.get(`/v2/Rail/Metro/Alert/${system}`));
      const parsed = metroAlertWrapper.safeParse(raw);
      const alerts = (parsed.success ? (parsed.data.Alerts ?? []) : []).map((alert) => ({
        system,
        id: alert.AlertID,
        title: alert.Title ?? '捷運營運消息',
        description: alert.Description ?? '',
        severity: alert.Status === 0 ? ('suspended' as const) : alert.Status === 2 ? ('disrupted' as const) : ('normal' as const),
        effect: alert.Effect ?? null,
        url: alert.AlertURL ?? null,
        startTime: alert.StartTime ?? null,
        endTime: alert.EndTime ?? null,
      }));
      return { supported: true, alerts: this.active(alerts) };
    }
    return { supported: false, alerts: [] };
  }

  /** 只留下異常且尚未結束的消息。 */
  private active(alerts: RailAlertDTO[]): RailAlertDTO[] {
    const now = this.now();
    return alerts.filter((alert) => alert.severity !== 'normal' && (alert.endTime == null || Date.parse(alert.endTime) > now));
  }
}

/** 高鐵 Status：空白 正常、▲ 其他異常、X 全線停止。 */
function thsrSeverity(status: string | null | undefined): RailAlertDTO['severity'] {
  const value = status?.trim() ?? '';
  if (value === 'X') return 'suspended';
  if (value === '') return 'normal';
  return 'disrupted';
}

