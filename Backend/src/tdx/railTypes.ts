import { z } from 'zod';

/** 軌道資料解析規則；欄位依官方 Swagger 核對（docs/TDX-FIELDS.md 軌道章節）。 */
const name = z.object({ Zh_tw: z.string().optional(), En: z.string().optional() }).partial().nullish();
const point = z.object({ PositionLat: z.number(), PositionLon: z.number() });

export const railStation = z.object({
  StationUID: z.string(),
  StationID: z.string(),
  StationName: name,
  StationPosition: point,
});
export type RailStation = z.infer<typeof railStation>;

export const metroLiveBoard = z.object({
  LineID: z.string().nullish(),
  LineName: name,
  StationID: z.string(),
  TripHeadSign: z.string().nullish(),
  DestinationStationName: name,
  ServiceStatus: z.number().int().nullish(),
  /** 分鐘 */
  EstimateTime: z.number().int().nullish(),
  SrcUpdateTime: z.string().nullish(),
  UpdateTime: z.string().nullish(),
});
export type MetroLiveBoard = z.infer<typeof metroLiveBoard>;

const serviceDay = z
  .object({
    Monday: z.boolean().nullish(),
    Tuesday: z.boolean().nullish(),
    Wednesday: z.boolean().nullish(),
    Thursday: z.boolean().nullish(),
    Friday: z.boolean().nullish(),
    Saturday: z.boolean().nullish(),
    Sunday: z.boolean().nullish(),
  })
  .nullish();
export type ServiceDay = z.infer<typeof serviceDay>;

export const metroStationTimetable = z.object({
  LineID: z.string().nullish(),
  StationID: z.string(),
  Direction: z.number().int().nullish(),
  DestinationStationName: name,
  Timetables: z.array(z.object({ DepartureTime: z.string().nullish(), ArrivalTime: z.string().nullish() })).nullish(),
  ServiceDay: serviceDay,
});
export type MetroStationTimetable = z.infer<typeof metroStationTimetable>;

export const metroFrequency = z.object({
  LineID: z.string().nullish(),
  RouteID: z.string().nullish(),
  ServiceDay: serviceDay,
  OperationTime: z.object({ StartTime: z.string().nullish(), EndTime: z.string().nullish() }).nullish(),
  Headways: z
    .array(
      z.object({
        StartTime: z.string().nullish(),
        EndTime: z.string().nullish(),
        MinHeadwayMins: z.number().int().nullish(),
        MaxHeadwayMins: z.number().int().nullish(),
      }),
    )
    .nullish(),
});
export type MetroFrequency = z.infer<typeof metroFrequency>;

const alertItem = z.object({
  AlertID: z.string(),
  Title: z.string().nullish(),
  Description: z.string().nullish(),
  Level: z.number().int().nullish(),
  Effect: z.string().nullish(),
  AlertURL: z.string().nullish(),
  StartTime: z.string().nullish(),
  EndTime: z.string().nullish(),
});

/** 捷運通阻：回應是包裝物件 `{ Alerts: [...] }`；Status 0 全線停止、1 正常、2 異常。 */
export const metroAlertWrapper = z.object({ Alerts: z.array(alertItem.extend({ Status: z.number().int().nullish() })).nullish() });

/** 高鐵通阻：Status 為字串（空白 正常、▲ 其他異常、X 全線停止）。 */
export const thsrAlert = alertItem.extend({ Status: z.string().nullish() });
export type ThsrAlert = z.infer<typeof thsrAlert>;

export const traLiveBoard = z.object({
  TrainNo: z.string(),
  Direction: z.number().int().nullish(),
  TrainTypeName: name,
  EndingStationName: name,
  ScheduledDepartureTime: z.string().nullish(),
  /** 0 準點、≥1 誤點分鐘 */
  DelayTime: z.number().int().nullish(),
  UpdateTime: z.string().nullish(),
});
export type TraLiveBoard = z.infer<typeof traLiveBoard>;

export const railStationTimetable = z.object({
  TrainNo: z.string(),
  Direction: z.number().int().nullish(),
  TrainTypeName: name,
  EndingStationName: name,
  DepartureTime: z.string().nullish(),
  /** 臺鐵：1 = 本站停駛 */
  SuspendedFlag: z.number().int().nullish(),
});
export type RailStationTimetable = z.infer<typeof railStationTimetable>;
