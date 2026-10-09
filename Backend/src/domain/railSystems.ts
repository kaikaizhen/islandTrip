/** 支援的軌道系統（TDX 代碼，已依官方 Swagger enum 核對）。 */
export const RAIL_SYSTEMS = ['TRA', 'THSR', 'TRTC', 'NTMC', 'TYMC', 'KRTC', 'TMRT'] as const;
export type RailSystem = (typeof RAIL_SYSTEMS)[number];
export type MetroSystem = Exclude<RailSystem, 'TRA' | 'THSR'>;

export const RAIL_SYSTEM_NAMES: Record<RailSystem, string> = {
  TRA: '臺鐵',
  THSR: '高鐵',
  TRTC: '臺北捷運',
  NTMC: '新北捷運',
  TYMC: '桃園機場捷運',
  KRTC: '高雄捷運',
  TMRT: '臺中捷運',
};

/** 各捷運系統官方有提供的資料（依 Swagger 各端點的 RailSystem enum）。 */
export const METRO_CAPABILITIES: Record<MetroSystem, { liveBoard: boolean; stationTimetable: boolean; frequency: boolean; alert: boolean }> = {
  TRTC: { liveBoard: true, stationTimetable: true, frequency: true, alert: true },
  KRTC: { liveBoard: true, stationTimetable: true, frequency: true, alert: true },
  // 官方註明桃園機場捷運即時看板僅提供 A1~A21 站
  TYMC: { liveBoard: true, stationTimetable: true, frequency: true, alert: true },
  NTMC: { liveBoard: false, stationTimetable: true, frequency: true, alert: false },
  TMRT: { liveBoard: false, stationTimetable: false, frequency: true, alert: true },
};

export function isMetro(system: RailSystem): system is MetroSystem {
  return system !== 'TRA' && system !== 'THSR';
}
