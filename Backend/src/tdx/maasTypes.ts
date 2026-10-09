import { z } from 'zod';

/**
 * MaaS 旅運規劃回應。官方範例的 sections 為空，以下依 2026-10-10 真實回應觀察（docs/TDX-FIELDS.md），
 * 一律寬鬆解析：缺欄位不視為錯誤。
 */
const place = z
  .object({
    name: z.string().nullish(),
    type: z.string().nullish(),
    location: z.object({ lat: z.number(), lng: z.number() }),
  })
  .passthrough();

const endpoint = z.object({ time: z.string().nullish(), place }).passthrough();

export const maasSection = z
  .object({
    type: z.string(),
    departure: endpoint,
    arrival: endpoint,
    travelSummary: z.object({ duration: z.number().nullish(), length: z.number().nullish() }).partial().nullish(),
    transport: z
      .object({
        mode: z.string().nullish(),
        name: z.string().nullish(),
        headsign: z.string().nullish(),
        shortName: z.string().nullish(),
        route_color: z.string().nullish(),
      })
      .passthrough()
      .nullish(),
    intermediateStops: z.array(z.object({ departure: endpoint.partial() }).passthrough()).nullish(),
  })
  .passthrough();
export type MaasSection = z.infer<typeof maasSection>;

export const maasRoute = z
  .object({
    travel_time: z.number(),
    start_time: z.string(),
    end_time: z.string(),
    transfers: z.number().int().nullish(),
    sections: z.array(maasSection),
  })
  .passthrough();
export type MaasRoute = z.infer<typeof maasRoute>;

export const maasResponse = z
  .object({
    result: z.string(),
    data: z.object({ routes: z.array(z.unknown()).nullish() }).passthrough().nullish(),
    error: z.object({ code: z.number().nullish(), msg: z.string().nullish() }).passthrough().nullish(),
  })
  .passthrough();
