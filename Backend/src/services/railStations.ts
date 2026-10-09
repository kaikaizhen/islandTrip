import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { boundingBox, distanceMeters, type Coordinate } from '../domain/geo.js';
import { RAIL_SYSTEM_NAMES, type RailSystem } from '../domain/railSystems.js';
import type { TdxApi } from '../tdx/client.js';
import { railStation } from '../tdx/railTypes.js';
import { parseList } from '../tdx/types.js';

export interface RailStationRecord {
  system: RailSystem;
  systemName: string;
  uid: string;
  id: string;
  name: string;
  lat: number;
  lon: number;
}

export function stationPath(system: RailSystem): string {
  if (system === 'TRA') return '/v2/Rail/TRA/Station';
  if (system === 'THSR') return '/v2/Rail/THSR/Station';
  return `/v2/Rail/Metro/Station/${system}`;
}

export function toStationRecords(system: RailSystem, raw: unknown): RailStationRecord[] {
  return parseList(railStation, raw).items.map((station) => ({
    system,
    systemName: RAIL_SYSTEM_NAMES[system],
    uid: station.StationUID,
    id: station.StationID,
    name: station.StationName?.Zh_tw ?? station.StationName?.En ?? station.StationID,
    lat: station.StationPosition.PositionLat,
    lon: station.StationPosition.PositionLon,
  }));
}

/** 各軌道系統的車站：每天下載一次並存到磁碟。 */
export class RailStationStore {
  private readonly stations = new Map<RailSystem, { at: number; records: RailStationRecord[] }>();
  private readonly maxAgeMs: number;
  private readonly now: () => number;

  constructor(
    private readonly api: TdxApi,
    private readonly systems: readonly RailSystem[],
    private readonly options: { dataDir: string; maxAgeMs?: number; now?: () => number },
  ) {
    this.maxAgeMs = options.maxAgeMs ?? 24 * 60 * 60 * 1000;
    this.now = options.now ?? Date.now;
  }

  async all(): Promise<RailStationRecord[]> {
    // 依序載入：首次啟動要下載七個系統，同時送出容易被 TDX 限流。
    const records: RailStationRecord[] = [];
    for (const system of this.systems) {
      try {
        records.push(...(await this.load(system)));
      } catch {
        // 單一系統失敗不影響其他系統；下次查詢會再試。
      }
    }
    return records;
  }

  async find(system: RailSystem, stationID: string): Promise<RailStationRecord | undefined> {
    return (await this.load(system)).find((station) => station.id === stationID);
  }

  async nearby(center: Coordinate, radius: number, limit = 20): Promise<(RailStationRecord & { distance: number })[]> {
    const box = boundingBox(center, radius);
    return (await this.all())
      .filter((s) => s.lat >= box.minLat && s.lat <= box.maxLat && s.lon >= box.minLon && s.lon <= box.maxLon)
      .map((s) => ({ ...s, distance: Math.round(distanceMeters(center, s)) }))
      .filter((s) => s.distance <= radius)
      .sort((a, b) => a.distance - b.distance)
      .slice(0, limit);
  }

  private async load(system: RailSystem): Promise<RailStationRecord[]> {
    const current = this.stations.get(system);
    if (current && this.now() - current.at < this.maxAgeMs) return current.records;
    const file = path.join(this.options.dataDir, `rail-stations-${system}.json`);
    let saved: { savedAt: number; raw: unknown } | undefined;
    try {
      saved = JSON.parse(await readFile(file, 'utf8'));
    } catch {
      saved = undefined;
    }
    if (!saved || this.now() - saved.savedAt >= this.maxAgeMs) {
      saved = { savedAt: this.now(), raw: await this.api.get(stationPath(system)) };
      await mkdir(this.options.dataDir, { recursive: true });
      await writeFile(file, JSON.stringify(saved));
    }
    const records = toStationRecords(system, saved.raw);
    this.stations.set(system, { at: saved.savedAt, records });
    return records;
  }
}

