import { z } from 'zod';

/**
 * TDX 回傳資料的解析規則。欄位依官方 Swagger 核對（見 docs/TDX-FIELDS.md），只取用得到的欄位；
 * 其他欄位保留但不使用。欄位缺漏時以寬鬆方式解析，避免單筆異常讓整批資料失敗。
 */
const name = z.object({ Zh_tw: z.string().optional(), En: z.string().optional() }).partial().optional();
const point = z.object({ PositionLat: z.number(), PositionLon: z.number() });

export const tdxStop = z.object({
  StopUID: z.string(),
  StopID: z.string().optional(),
  StopName: name,
  StopPosition: point,
  Bearing: z.string().nullish(),
  StationID: z.string().nullish(),
  City: z.string().nullish(),
});
export type TdxStop = z.infer<typeof tdxStop>;

export const tdxStopOfRoute = z.object({
  RouteUID: z.string(),
  RouteID: z.string().optional(),
  RouteName: name,
  SubRouteUID: z.string().nullish(),
  SubRouteID: z.string().nullish(),
  Direction: z.number().int(),
  Stops: z.array(
    z.object({
      StopUID: z.string(),
      StopName: name,
      StopBoarding: z.number().int().nullish(),
      StopSequence: z.number().int(),
      StopPosition: point.optional(),
      StationID: z.string().nullish(),
    }),
  ),
});
export type TdxStopOfRoute = z.infer<typeof tdxStopOfRoute>;

export const tdxRoute = z.object({
  RouteUID: z.string(),
  RouteName: name,
  SubRoutes: z
    .array(
      z.object({
        SubRouteUID: z.string().nullish(),
        Headsign: z.string().nullish(),
        Direction: z.number().int().nullish(),
        DestinationStopNameZh: z.string().nullish(),
      }),
    )
    .nullish(),
  DestinationStopNameZh: z.string().nullish(),
  DepartureStopNameZh: z.string().nullish(),
});
export type TdxRoute = z.infer<typeof tdxRoute>;

export const tdxEstimate = z.object({
  PlateNumb: z.string().nullish(),
  StopUID: z.string(),
  RouteUID: z.string(),
  RouteName: name,
  SubRouteUID: z.string().nullish(),
  Direction: z.number().int().nullish(),
  EstimateTime: z.number().int().nullish(),
  StopStatus: z.number().int().nullish(),
  IsLastBus: z.boolean().nullish(),
  SrcUpdateTime: z.string().nullish(),
  SrcTransTime: z.string().nullish(),
  UpdateTime: z.string().nullish(),
});
export type TdxEstimate = z.infer<typeof tdxEstimate>;

const scopeRoute = z.object({ RouteID: z.string().nullish(), Direction: z.number().int().nullish() });
export const tdxAlert = z.object({
  AlertID: z.string(),
  Title: z.string().nullish(),
  Description: z.string().nullish(),
  Status: z.number().int().nullish(),
  Cause: z.number().int().nullish(),
  Effect: z.number().int().nullish(),
  Scope: z
    .object({
      Routes: z.array(scopeRoute).nullish(),
      SubRoutes: z.array(z.object({ SubRouteID: z.string().nullish(), Direction: z.number().int().nullish() })).nullish(),
      Stops: z.array(z.object({ StopID: z.string().nullish(), StationID: z.string().nullish() })).nullish(),
    })
    .partial()
    .nullish(),
  AlertURL: z.string().nullish(),
  PublishTime: z.string().nullish(),
  StartTime: z.string().nullish(),
  EndTime: z.string().nullish(),
  UpdateTime: z.string().nullish(),
});
export type TdxAlert = z.infer<typeof tdxAlert>;

/** 解析陣列：無法解析的單筆略過並計數，不讓整批失敗。 */
export function parseList<T>(schema: z.ZodType<T>, data: unknown): { items: T[]; skipped: number } {
  if (!Array.isArray(data)) return { items: [], skipped: 0 };
  const items: T[] = [];
  let skipped = 0;
  for (const raw of data) {
    const parsed = schema.safeParse(raw);
    if (parsed.success) items.push(parsed.data);
    else skipped += 1;
  }
  return { items, skipped };
}
