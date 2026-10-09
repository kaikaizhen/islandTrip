import { METRO_CAPABILITIES, isMetro, type MetroSystem, type RailSystem } from '../domain/railSystems.js';
import { minutesOfDay, taipeiISO, taipeiNow, type TaipeiNow } from '../domain/taipeiTime.js';
import type { TdxApi } from '../tdx/client.js';
import {
  metroFrequency,
  metroLiveBoard,
  metroStationTimetable,
  railStationTimetable,
  traLiveBoard,
  type MetroFrequency,
  type MetroLiveBoard,
  type MetroStationTimetable,
  type RailStationTimetable,
  type ServiceDay,
  type TraLiveBoard,
} from '../tdx/railTypes.js';
import { parseList } from '../tdx/types.js';
import { TtlCache } from './ttlCache.js';

/** 資料等級：App 必須清楚標示，不可把時刻表或班距當成即時資訊（計畫 Phase 5）。 */
export type DataLevel = 'realtime' | 'timetable' | 'frequency';

export type DepartureStatus = 'normal' | 'notDeparted' | 'noStop' | 'lastPassed' | 'notOperating' | 'suspended' | 'unknown';

export interface Departure {
  /** 路線或車種，例：「淡水信義線」「自強」。 */
  line: string | null;
  trainNo: string | null;
  destination: string | null;
  /** 例：「南下」「往淡水」。 */
  direction: string | null;
  scheduledAt: string | null;
  /** 預估開車（或到站）時間；即時資料才有誤點修正。 */
  expectedAt: string | null;
  delayMinutes: number | null;
  /** 班距（只有班距資料時）。 */
  headway: { minMinutes: number; maxMinutes: number } | null;
  status: DepartureStatus;
  dataLevel: DataLevel;
}

export interface StationDepartures {
  system: RailSystem;
  stationID: string;
  generatedAt: string;
  departures: Departure[];
  /** 給使用者看的資料說明，例：「臺中捷運只提供班距」。 */
  note: string | null;
}

const METRO_STATUS: Record<number, DepartureStatus> = { 0: 'normal', 1: 'notDeparted', 2: 'noStop', 3: 'lastPassed', 4: 'notOperating' };
const SERVICE_DAY_KEYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'] as const;

/** 依星期判斷是否營運（國定假日資料未納入，回應中會說明）。 */
function runsOn(serviceDay: ServiceDay, weekday: number): boolean {
  if (!serviceDay) return true;
  const value = serviceDay[SERVICE_DAY_KEYS[weekday]!];
  return value !== false;
}

function escapeOData(value: string): string {
  return value.replaceAll("'", "''");
}

export interface RailDepartureOptions {
  now?: () => number;
  /** 往後列出多久內的班次（分鐘）。 */
  windowMinutes?: number;
  limit?: number;
}

/** 車站即將發車資訊：有即時看板用即時，沒有就用時刻表，再沒有就用班距。 */
export class RailDepartureService {
  private readonly now: () => number;
  private readonly windowMinutes: number;
  private readonly limit: number;
  private readonly live: TtlCache<unknown>;
  private readonly daily: TtlCache<unknown>;

  constructor(private readonly api: TdxApi, options: RailDepartureOptions = {}) {
    this.now = options.now ?? Date.now;
    this.windowMinutes = options.windowMinutes ?? 120;
    this.limit = options.limit ?? 12;
    this.live = new TtlCache(20_000, this.now);
    this.daily = new TtlCache(6 * 60 * 60 * 1000, this.now);
  }

  async departures(system: RailSystem, stationID: string): Promise<StationDepartures> {
    const now = taipeiNow(this.now());
    const result = (departures: Departure[], note: string | null = null): StationDepartures => ({
      system,
      stationID,
      generatedAt: new Date(this.now()).toISOString(),
      departures: departures.slice(0, this.limit),
      note,
    });

    if (system === 'TRA') return result(await this.tra(stationID, now));
    if (system === 'THSR') return result(await this.thsr(stationID, now), '高鐵沒有即時誤點資料，以下依時刻表。');
    if (isMetro(system)) {
      const { departures, note } = await this.metro(system, stationID, now);
      return result(departures, note);
    }
    return result([]);
  }

  // MARK: 臺鐵：時刻表為底，即時看板補上誤點

  private async tra(stationID: string, now: TaipeiNow): Promise<Departure[]> {
    const id = escapeOData(stationID);
    const [timetableRaw, liveRaw] = await Promise.allSettled([
      this.daily.get(`TRA:${stationID}:${now.date}`, () => this.api.get(`/v2/Rail/TRA/DailyTimetable/Station/${id}/${now.date}`)),
      this.live.get(`TRA-live:${stationID}`, () => this.api.get(`/v2/Rail/TRA/LiveBoard/Station/${id}`)),
    ]);
    const live = liveRaw.status === 'fulfilled' ? parseList(traLiveBoard, liveRaw.value).items : [];
    const timetable = timetableRaw.status === 'fulfilled' ? parseList(railStationTimetable, timetableRaw.value).items : [];
    if (timetableRaw.status === 'rejected' && liveRaw.status === 'rejected') throw timetableRaw.reason;

    const liveByTrain = new Map(live.map((entry) => [entry.TrainNo, entry]));
    const rows: Departure[] = timetable.map((row) => traDeparture(row, liveByTrain.get(row.TrainNo), now.date));
    // 只有即時看板、沒有時刻表的列車也列出
    for (const entry of live) {
      if (!timetable.some((row) => row.TrainNo === entry.TrainNo)) rows.push(traLiveOnly(entry, now.date));
    }
    return this.upcoming(rows);
  }

  // MARK: 高鐵：只有時刻表

  private async thsr(stationID: string, now: TaipeiNow): Promise<Departure[]> {
    const raw = await this.daily.get(`THSR:${stationID}:${now.date}`, () =>
      this.api.get(`/v2/Rail/THSR/DailyTimetable/Station/${escapeOData(stationID)}/${now.date}`),
    );
    const rows = parseList(railStationTimetable, raw).items.map((row) => {
      const scheduledAt = row.DepartureTime ? taipeiISO(now.date, row.DepartureTime) : null;
      return {
        line: '高鐵',
        trainNo: row.TrainNo,
        destination: row.EndingStationName?.Zh_tw ?? null,
        direction: row.Direction === 0 ? '南下' : row.Direction === 1 ? '北上' : null,
        scheduledAt,
        expectedAt: scheduledAt,
        delayMinutes: null,
        headway: null,
        status: 'normal' as const,
        dataLevel: 'timetable' as const,
      };
    });
    return this.upcoming(rows);
  }

  // MARK: 捷運：即時看板 → 站別時刻表 → 班距

  private async metro(system: MetroSystem, stationID: string, now: TaipeiNow): Promise<{ departures: Departure[]; note: string | null }> {
    const capability = METRO_CAPABILITIES[system];
    const filter = { $filter: `StationID eq '${escapeOData(stationID)}'` };

    if (capability.liveBoard) {
      const raw = await this.live
        .get(`${system}-live:${stationID}`, () => this.api.get(`/v2/Rail/Metro/LiveBoard/${system}`, filter))
        .catch(() => []);
      const rows = parseList(metroLiveBoard, raw).items.map((entry) => metroLiveDeparture(entry, this.now()));
      if (rows.length > 0) return { departures: rows, note: null };
    }
    if (capability.stationTimetable) {
      const raw = await this.daily.get(`${system}-tt:${stationID}`, () => this.api.get(`/v2/Rail/Metro/StationTimeTable/${system}`, filter));
      const rows = parseList(metroStationTimetable, raw).items.flatMap((table) => metroTimetableDepartures(table, now));
      return {
        departures: this.upcoming(rows),
        note: capability.liveBoard ? '這一站目前沒有即時資料，以下依時刻表。' : '此系統沒有即時到站資料，以下依時刻表（未計入國定假日異動）。',
      };
    }
    if (capability.frequency) {
      const raw = await this.daily.get(`${system}-freq`, () => this.api.get(`/v2/Rail/Metro/Frequency/${system}`));
      const rows = parseList(metroFrequency, raw).items.flatMap((entry) => metroFrequencyDeparture(entry, now));
      return { departures: dedupeHeadways(rows), note: '此系統只提供班距，沒有每班時間。' };
    }
    return { departures: [], note: '此系統沒有提供發車資料。' };
  }

  /** 只留下現在到之後一段時間內的班次，依預估時間排序。 */
  private upcoming(rows: Departure[]): Departure[] {
    const nowMs = this.now();
    const until = nowMs + this.windowMinutes * 60_000;
    return rows
      .filter((row) => {
        const at = row.expectedAt ? Date.parse(row.expectedAt) : Number.NaN;
        return !Number.isNaN(at) && at >= nowMs - 60_000 && at <= until;
      })
      .sort((a, b) => Date.parse(a.expectedAt!) - Date.parse(b.expectedAt!));
  }
}

export function traDeparture(row: RailStationTimetable, live: TraLiveBoard | undefined, date: string): Departure {
  const scheduledAt = row.DepartureTime ? taipeiISO(date, row.DepartureTime) : null;
  const delay = live?.DelayTime ?? null;
  const expectedAt = scheduledAt && delay != null ? new Date(Date.parse(scheduledAt) + delay * 60_000).toISOString() : scheduledAt;
  return {
    line: row.TrainTypeName?.Zh_tw ?? null,
    trainNo: row.TrainNo,
    destination: row.EndingStationName?.Zh_tw ?? null,
    direction: row.Direction === 0 ? '順行' : row.Direction === 1 ? '逆行' : null,
    scheduledAt,
    expectedAt,
    delayMinutes: delay,
    headway: null,
    status: row.SuspendedFlag === 1 ? 'suspended' : 'normal',
    dataLevel: live ? 'realtime' : 'timetable',
  };
}

function traLiveOnly(entry: TraLiveBoard, date: string): Departure {
  return traDeparture(
    { TrainNo: entry.TrainNo, Direction: entry.Direction, TrainTypeName: entry.TrainTypeName, EndingStationName: entry.EndingStationName, DepartureTime: entry.ScheduledDepartureTime },
    entry,
    date,
  );
}

/** 捷運即時看板：EstimateTime 是「分鐘」，以資料時間為基準換算。 */
export function metroLiveDeparture(entry: MetroLiveBoard, nowMs: number): Departure {
  const base = Date.parse(entry.SrcUpdateTime ?? entry.UpdateTime ?? '');
  const baseMs = Number.isNaN(base) ? nowMs : base;
  const status = METRO_STATUS[entry.ServiceStatus ?? 0] ?? 'unknown';
  const expectedAt = entry.EstimateTime != null && status === 'normal' ? new Date(baseMs + entry.EstimateTime * 60_000).toISOString() : null;
  return {
    line: entry.LineName?.Zh_tw ?? entry.LineID ?? null,
    trainNo: null,
    destination: entry.DestinationStationName?.Zh_tw ?? entry.TripHeadSign ?? null,
    direction: entry.TripHeadSign ?? null,
    scheduledAt: null,
    expectedAt,
    delayMinutes: null,
    headway: null,
    status,
    dataLevel: 'realtime',
  };
}

function metroTimetableDepartures(table: MetroStationTimetable, now: TaipeiNow): Departure[] {
  if (!runsOn(table.ServiceDay, now.weekday)) return [];
  return (table.Timetables ?? []).flatMap((slot) => {
    const time = slot.DepartureTime ?? slot.ArrivalTime;
    const at = time ? taipeiISO(now.date, time) : null;
    if (!at) return [];
    return [{
      line: table.LineID ?? null,
      trainNo: null,
      destination: table.DestinationStationName?.Zh_tw ?? null,
      direction: table.DestinationStationName?.Zh_tw ? `往${table.DestinationStationName.Zh_tw}` : null,
      scheduledAt: at,
      expectedAt: at,
      delayMinutes: null,
      headway: null,
      status: 'normal' as const,
      dataLevel: 'timetable' as const,
    }];
  });
}

function metroFrequencyDeparture(entry: MetroFrequency, now: TaipeiNow): Departure[] {
  if (!runsOn(entry.ServiceDay, now.weekday)) return [];
  const start = minutesOfDay(entry.OperationTime?.StartTime);
  const end = minutesOfDay(entry.OperationTime?.EndTime);
  const operating = start == null || end == null || (end > start ? now.minutes >= start && now.minutes < end : now.minutes >= start || now.minutes < end);
  const headway = (entry.Headways ?? []).find((h) => {
    const s = minutesOfDay(h.StartTime);
    const e = minutesOfDay(h.EndTime);
    return s != null && e != null && now.minutes >= s && now.minutes < e;
  });
  return [{
    line: entry.LineID ?? entry.RouteID ?? null,
    trainNo: null,
    destination: null,
    direction: null,
    scheduledAt: null,
    expectedAt: null,
    delayMinutes: null,
    headway:
      operating && headway?.MinHeadwayMins != null
        ? { minMinutes: headway.MinHeadwayMins, maxMinutes: headway.MaxHeadwayMins ?? headway.MinHeadwayMins }
        : null,
    status: operating ? 'normal' : 'notOperating',
    dataLevel: 'frequency',
  }];
}

/** 同一路線可能有多筆（不同車種），保留一筆。 */
function dedupeHeadways(rows: Departure[]): Departure[] {
  const seen = new Set<string>();
  return rows.filter((row) => {
    const key = `${row.line}|${row.headway?.minMinutes}|${row.status}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
