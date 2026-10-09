import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, expect, it, vi } from 'vitest';
import { minutesOfDay, taipeiISO, taipeiNow } from '../src/domain/taipeiTime.js';
import { RailAlertService } from '../src/services/railAlerts.js';
import { RailDepartureService } from '../src/services/railDepartures.js';
import { RailStationStore } from '../src/services/railStations.js';

/**
 * 合成測試資料：結構依官方軌道 v2 Swagger（docs/TDX-FIELDS.md 軌道章節），內容是虛構的。
 * 時間：2026-10-12（星期一）臺北 08:00 = UTC 00:00。
 */
const NOW = Date.parse('2026-10-12T00:00:00Z');
const at = (hhmm: string) => taipeiISO('2026-10-12', hhmm);

function fakeApi(routes: Record<string, unknown>) {
  return {
    get: vi.fn(async (p: string, query?: Record<string, string>) => {
      const key = Object.keys(routes).find((k) => p.startsWith(k));
      if (!key) throw new Error(`unexpected ${p} ${JSON.stringify(query)}`);
      const value = routes[key];
      if (value instanceof Error) throw value;
      return value;
    }),
  };
}

describe('Taipei time', () => {
  it('converts regardless of server time zone', () => {
    expect(taipeiNow(NOW)).toEqual({ date: '2026-10-12', minutes: 8 * 60, weekday: 1 });
    expect(taipeiNow(Date.parse('2026-10-11T16:30:00Z'))).toEqual({ date: '2026-10-12', minutes: 30, weekday: 1 });
    expect(taipeiISO('2026-10-12', '08:15')).toBe('2026-10-12T00:15:00.000Z');
    expect(minutesOfDay('23:59:00')).toBe(23 * 60 + 59);
    expect(minutesOfDay('bad')).toBeUndefined();
  });
});

describe('rail stations', () => {
  it('loads every system once and finds nearby stations across systems', async () => {
    const api = fakeApi({
      '/v2/Rail/TRA/Station': [{ StationUID: 'TRA-1000', StationID: '1000', StationName: { Zh_tw: '臺北' }, StationPosition: { PositionLat: 25.0478, PositionLon: 121.517 } }],
      '/v2/Rail/THSR/Station': [{ StationUID: 'THSR-1000', StationID: '1000', StationName: { Zh_tw: '台北' }, StationPosition: { PositionLat: 25.0477, PositionLon: 121.5171 } }],
      '/v2/Rail/Metro/Station/TRTC': [{ StationUID: 'TRTC-BL12', StationID: 'BL12', StationName: { Zh_tw: '台北車站' }, StationPosition: { PositionLat: 25.0463, PositionLon: 121.5176 } }],
      '/v2/Rail/Metro/Station/TMRT': [{ StationUID: 'TMRT-103', StationID: '103', StationName: { Zh_tw: '文心崇德' }, StationPosition: { PositionLat: 24.17, PositionLon: 120.68 } }],
    });
    const store = new RailStationStore(api, ['TRA', 'THSR', 'TRTC', 'TMRT'], { dataDir: await mkdtemp(path.join(tmpdir(), 'rail-')), now: () => NOW });
    const nearby = await store.nearby({ lat: 25.0475, lon: 121.5172 }, 500);
    expect(nearby.map((s) => s.system).sort()).toEqual(['THSR', 'TRA', 'TRTC']);
    expect(nearby[0]?.distance).toBeLessThan(nearby[2]!.distance);
    await store.nearby({ lat: 25.0475, lon: 121.5172 }, 500);
    expect(api.get).toHaveBeenCalledTimes(4);
  });
});

describe('TRA departures', () => {
  const timetable = [
    { TrainNo: '111', Direction: 0, TrainTypeName: { Zh_tw: '自強' }, EndingStationName: { Zh_tw: '高雄' }, DepartureTime: '08:10:00' },
    { TrainNo: '222', Direction: 1, TrainTypeName: { Zh_tw: '區間' }, EndingStationName: { Zh_tw: '基隆' }, DepartureTime: '08:20:00', SuspendedFlag: 1 },
    { TrainNo: '000', Direction: 0, TrainTypeName: { Zh_tw: '區間' }, EndingStationName: { Zh_tw: '新竹' }, DepartureTime: '07:30:00' },
    { TrainNo: '999', Direction: 0, TrainTypeName: { Zh_tw: '區間' }, EndingStationName: { Zh_tw: '新竹' }, DepartureTime: '11:30:00' },
  ];

  it('uses live delay when available and timetable otherwise', async () => {
    const api = fakeApi({
      '/v2/Rail/TRA/DailyTimetable/Station/1000/2026-10-12': timetable,
      '/v2/Rail/TRA/LiveBoard/Station/1000': [{ TrainNo: '111', DelayTime: 5, ScheduledDepartureTime: '08:10:00' }],
    });
    const board = await new RailDepartureService(api, { now: () => NOW }).departures('TRA', '1000');
    expect(board.departures.map((d) => d.trainNo)).toEqual(['111', '222']);
    expect(board.departures[0]).toMatchObject({ dataLevel: 'realtime', delayMinutes: 5, scheduledAt: at('08:10'), expectedAt: at('08:15'), line: '自強' });
    expect(board.departures[1]).toMatchObject({ dataLevel: 'timetable', status: 'suspended', delayMinutes: null });
  });

  it('still shows live trains when the timetable fails', async () => {
    const api = fakeApi({
      '/v2/Rail/TRA/DailyTimetable': new Error('HTTP 503'),
      '/v2/Rail/TRA/LiveBoard/Station/1000': [{ TrainNo: '333', DelayTime: 0, ScheduledDepartureTime: '08:05:00', EndingStationName: { Zh_tw: '花蓮' } }],
    });
    const board = await new RailDepartureService(api, { now: () => NOW }).departures('TRA', '1000');
    expect(board.departures).toHaveLength(1);
    expect(board.departures[0]).toMatchObject({ trainNo: '333', dataLevel: 'realtime', destination: '花蓮' });
  });
});

describe('THSR departures', () => {
  it('is timetable only and says so', async () => {
    const api = fakeApi({
      '/v2/Rail/THSR/DailyTimetable/Station/1000/2026-10-12': [
        { TrainNo: '0603', Direction: 0, EndingStationName: { Zh_tw: '左營' }, DepartureTime: '08:21' },
      ],
    });
    const board = await new RailDepartureService(api, { now: () => NOW }).departures('THSR', '1000');
    expect(board.note).toContain('沒有即時');
    expect(board.departures[0]).toMatchObject({ direction: '南下', dataLevel: 'timetable', delayMinutes: null });
  });
});

describe('metro departures', () => {
  it('TRTC live board gives minutes-based real-time arrivals', async () => {
    const api = fakeApi({
      '/v2/Rail/Metro/LiveBoard/TRTC': [
        { LineID: 'BL', LineName: { Zh_tw: '板南線' }, StationID: 'BL12', TripHeadSign: '往南港展覽館', DestinationStationName: { Zh_tw: '南港展覽館' }, ServiceStatus: 0, EstimateTime: 3, SrcUpdateTime: '2026-10-12T08:00:00+08:00' },
        { LineID: 'BL', LineName: { Zh_tw: '板南線' }, StationID: 'BL12', DestinationStationName: { Zh_tw: '頂埔' }, ServiceStatus: 3, EstimateTime: null },
      ],
    });
    const board = await new RailDepartureService(api, { now: () => NOW }).departures('TRTC', 'BL12');
    expect(api.get).toHaveBeenCalledWith('/v2/Rail/Metro/LiveBoard/TRTC', { $filter: "StationID eq 'BL12'" });
    expect(board.departures[0]).toMatchObject({ line: '板南線', destination: '南港展覽館', expectedAt: at('08:03'), dataLevel: 'realtime' });
    expect(board.departures[1]).toMatchObject({ status: 'lastPassed', expectedAt: null });
  });

  it('falls back to the station timetable when the live board is empty', async () => {
    const api = fakeApi({
      '/v2/Rail/Metro/LiveBoard/TYMC': [],
      '/v2/Rail/Metro/StationTimeTable/TYMC': [
        { LineID: 'A', StationID: 'A22', Direction: 0, DestinationStationName: { Zh_tw: '老街溪' }, ServiceDay: { Monday: true }, Timetables: [{ DepartureTime: '07:50' }, { DepartureTime: '08:12' }] },
      ],
    });
    const board = await new RailDepartureService(api, { now: () => NOW }).departures('TYMC', 'A22');
    expect(board.note).toContain('時刻表');
    expect(board.departures.map((d) => d.expectedAt)).toEqual([at('08:12')]);
    expect(board.departures[0]?.dataLevel).toBe('timetable');
  });

  it('NTMC uses timetables and respects the service day', async () => {
    const api = fakeApi({
      '/v2/Rail/Metro/StationTimeTable/NTMC': [
        { LineID: 'Y', StationID: 'Y10', DestinationStationName: { Zh_tw: '新北產業園區' }, ServiceDay: { Monday: true }, Timetables: [{ DepartureTime: '08:05' }] },
        { LineID: 'Y', StationID: 'Y10', DestinationStationName: { Zh_tw: '大坪林' }, ServiceDay: { Monday: false, Saturday: true }, Timetables: [{ DepartureTime: '08:06' }] },
      ],
    });
    const board = await new RailDepartureService(api, { now: () => NOW }).departures('NTMC', 'Y10');
    expect(api.get).not.toHaveBeenCalledWith(expect.stringContaining('LiveBoard'), expect.anything());
    expect(board.departures.map((d) => d.destination)).toEqual(['新北產業園區']);
  });

  it('TMRT only has headways', async () => {
    const api = fakeApi({
      '/v2/Rail/Metro/Frequency/TMRT': [
        { LineID: 'G', ServiceDay: { Monday: true }, OperationTime: { StartTime: '06:00', EndTime: '24:00' },
          Headways: [{ StartTime: '07:00', EndTime: '09:00', MinHeadwayMins: 4, MaxHeadwayMins: 6 }, { StartTime: '09:00', EndTime: '17:00', MinHeadwayMins: 8, MaxHeadwayMins: 10 }] },
      ],
    });
    const board = await new RailDepartureService(api, { now: () => NOW }).departures('TMRT', '103');
    expect(board.note).toContain('班距');
    expect(board.departures).toEqual([expect.objectContaining({ line: 'G', headway: { minMinutes: 4, maxMinutes: 6 }, dataLevel: 'frequency', expectedAt: null })]);
  });

  it('TMRT outside operating hours is reported as not operating', async () => {
    const api = fakeApi({
      '/v2/Rail/Metro/Frequency/TMRT': [{ LineID: 'G', OperationTime: { StartTime: '06:00', EndTime: '24:00' }, Headways: [] }],
    });
    const lateNight = Date.parse('2026-10-11T19:00:00Z'); // 臺北 03:00
    const board = await new RailDepartureService(api, { now: () => lateNight }).departures('TMRT', '103');
    expect(board.departures[0]).toMatchObject({ status: 'notOperating', headway: null });
  });
});

describe('rail alerts', () => {
  it('parses the metro wrapper and keeps only active disruptions', async () => {
    const api = fakeApi({
      '/v2/Rail/Metro/Alert/TRTC': {
        UpdateTime: '2026-10-12T07:59:00+08:00',
        Alerts: [
          { AlertID: 'M1', Title: '板南線延誤', Description: '號誌異常', Status: 2, EndTime: '2026-10-12T12:00:00+08:00' },
          { AlertID: 'M2', Title: '全線正常', Status: 1 },
          { AlertID: 'M3', Title: '已結束', Status: 2, EndTime: '2026-10-11T12:00:00+08:00' },
        ],
      },
    });
    const result = await new RailAlertService(api, () => NOW).alerts('TRTC');
    expect(result.supported).toBe(true);
    expect(result.alerts.map((a) => [a.id, a.severity])).toEqual([['M1', 'disrupted']]);
  });

  it('maps THSR status symbols', async () => {
    const api = fakeApi({
      '/v2/Rail/THSR/AlertInfo': [
        { AlertID: 'H1', Title: '全線停駛', Status: 'X' },
        { AlertID: 'H2', Title: '部分延誤', Status: '▲' },
        { AlertID: 'H3', Title: '正常', Status: '' },
      ],
    });
    const result = await new RailAlertService(api, () => NOW).alerts('THSR');
    expect(result.alerts.map((a) => [a.id, a.severity])).toEqual([['H1', 'suspended'], ['H2', 'disrupted']]);
  });

  it('reports systems without verified alert data as unsupported', async () => {
    const api = fakeApi({});
    const service = new RailAlertService(api, () => NOW);
    expect(await service.alerts('TRA')).toEqual({ supported: false, alerts: [] });
    expect(await service.alerts('NTMC')).toEqual({ supported: false, alerts: [] });
    expect(api.get).not.toHaveBeenCalled();
  });
});
