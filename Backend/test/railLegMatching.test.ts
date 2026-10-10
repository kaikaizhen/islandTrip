import { describe, expect, it } from 'vitest';
import type { Departure } from '../src/services/railDepartures.js';
import { matchDeparture, matchStation, normalizeStationName } from '../src/services/railLegMatching.js';
import type { RailStationRecord } from '../src/services/railStations.js';

const station = (system: RailStationRecord['system'], id: string, name: string, lat: number, lon: number): RailStationRecord => ({
  system, systemName: system, uid: `${system}-${id}`, id, name, lat, lon,
});
const stations = [
  station('TRTC', 'R22', '北投', 25.13208, 121.49856),
  station('TRTC', 'R10', '台北車站', 25.04636, 121.51761),
  station('TRA', '1000', '臺北', 25.04775, 121.51711),
  station('NTMC', 'V01', '紅樹林', 25.15464, 121.45913),
];
const now = Date.parse('2026-10-10T00:00:00Z');
const departure = (over: Partial<Departure>): Departure => ({
  line: '淡水信義線', trainNo: null, destination: '象山', direction: null, scheduledAt: null,
  expectedAt: new Date(now + 4 * 60_000).toISOString(), delayMinutes: null, headway: null, status: 'normal', dataLevel: 'realtime', ...over,
});

describe('normalizeStationName', () => {
  it('unifies 臺/台 and drops 站/車站/往', () => {
    expect(normalizeStationName('臺北車站')).toBe('台北');
    expect(normalizeStationName('往象山')).toBe('象山');
    expect(normalizeStationName('北投站')).toBe('北投');
  });
});

describe('matchStation', () => {
  it('matches metro by name and distance, TRA separately', () => {
    // MaaS 座標與 TDX 差約 50 公尺
    expect(matchStation(stations, 'metro', { name: '北投', lat: 25.131819, lon: 121.49865 })?.id).toBe('R22');
    expect(matchStation(stations, 'tra', { name: '台北', lat: 25.0478, lon: 121.5170 })?.id).toBe('1000');
    // 捷運「台北車站」不能配到臺鐵
    expect(matchStation(stations, 'metro', { name: '台北車站', lat: 25.0461, lon: 121.5174 })?.system).toBe('TRTC');
  });

  it('does not match a different-name station unless almost the same point', () => {
    expect(matchStation(stations, 'metro', { name: '新北投', lat: 25.13695, lon: 121.50283 })).toBeUndefined();
    expect(matchStation(stations, 'metro', { name: null, lat: 25.13210, lon: 121.49860 })?.id).toBe('R22');
  });
});

describe('matchDeparture', () => {
  it('metro: same line and terminus, earliest first; ignores timetable rows', () => {
    const departures = [
      departure({ destination: '大安', expectedAt: new Date(now + 60_000).toISOString() }),
      departure({ expectedAt: new Date(now + 9 * 60_000).toISOString() }),
      departure({}),
      departure({ dataLevel: 'timetable', expectedAt: new Date(now + 30_000).toISOString() }),
    ];
    const match = matchDeparture('metro', { line: '淡水信義線', headsign: '象山', departAt: null }, departures, now);
    expect(match?.expectedAt).toBe(new Date(now + 4 * 60_000).toISOString());
  });

  it('metro: no headsign means no match', () => {
    expect(matchDeparture('metro', { line: '淡水信義線', headsign: null, departAt: null }, [departure({})], now)).toBeUndefined();
  });

  it('TRA: the only train scheduled within 2 minutes, with delay', () => {
    const departAt = new Date(now + 10 * 60_000).toISOString();
    const train = departure({ line: '區間', trainNo: '1234', destination: '基隆', scheduledAt: departAt,
      expectedAt: new Date(now + 15 * 60_000).toISOString(), delayMinutes: 5 });
    const other = departure({ trainNo: '111', scheduledAt: new Date(now + 30 * 60_000).toISOString() });
    expect(matchDeparture('tra', { line: '區間', headsign: '基隆', departAt }, [train, other], now)?.trainNo).toBe('1234');
    // 兩班都在 2 分鐘內：不確定就不配
    const twin = departure({ trainNo: '1236', scheduledAt: new Date(now + 11 * 60_000).toISOString() });
    expect(matchDeparture('tra', { line: '區間', headsign: '基隆', departAt }, [train, twin], now)).toBeUndefined();
  });
});
