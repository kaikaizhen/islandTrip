/**
 * 合成測試資料：結構依官方 Swagger 欄位（docs/TDX-FIELDS.md），內容是虛構的，不是真實班次或站點。
 * 情境：市政府站兩側同名站牌（往台北車站／往松山），265 去程經過「市政府(東側)」到台北車站；返程反向。
 */
export const stops = [
  { StopUID: 'TPE1001', StopName: { Zh_tw: '市政府' }, StopPosition: { PositionLat: 25.04128, PositionLon: 121.566 }, Bearing: 'W', StationID: 'S1' },
  { StopUID: 'TPE1002', StopName: { Zh_tw: '市政府' }, StopPosition: { PositionLat: 25.04092, PositionLon: 121.5662 }, Bearing: 'E', StationID: 'S2' },
  { StopUID: 'TPE1003', StopName: { Zh_tw: '忠孝復興' }, StopPosition: { PositionLat: 25.0415, PositionLon: 121.5436 }, Bearing: 'W', StationID: 'S3' },
  { StopUID: 'TPE1004', StopName: { Zh_tw: '台北車站' }, StopPosition: { PositionLat: 25.0477, PositionLon: 121.5173 }, Bearing: 'W', StationID: 'S4' },
  { StopUID: 'TPE1005', StopName: { Zh_tw: '台北車站' }, StopPosition: { PositionLat: 25.0479, PositionLon: 121.5174 }, Bearing: 'E', StationID: 'S5' },
  // 缺少座標的不完整資料：應被略過，不影響整批。
  { StopUID: 'TPE9999', StopName: { Zh_tw: '壞資料' } },
];

export const stopOfRoutes = [
  {
    RouteUID: 'TPE265', RouteID: '265', RouteName: { Zh_tw: '265' }, SubRouteUID: 'TPE265A', Direction: 0,
    Stops: [
      { StopUID: 'TPE1001', StopName: { Zh_tw: '市政府' }, StopSequence: 1, StopBoarding: 0 },
      { StopUID: 'TPE1003', StopName: { Zh_tw: '忠孝復興' }, StopSequence: 2, StopBoarding: 0 },
      { StopUID: 'TPE1004', StopName: { Zh_tw: '台北車站' }, StopSequence: 3, StopBoarding: 0 },
    ],
  },
  {
    RouteUID: 'TPE265', RouteID: '265', RouteName: { Zh_tw: '265' }, SubRouteUID: 'TPE265A', Direction: 1,
    Stops: [
      { StopUID: 'TPE1005', StopName: { Zh_tw: '台北車站' }, StopSequence: 1, StopBoarding: 0 },
      { StopUID: 'TPE1002', StopName: { Zh_tw: '市政府' }, StopSequence: 2, StopBoarding: 0 },
    ],
  },
  {
    // 只能下車的站不能當上車站
    RouteUID: 'TPE900', RouteID: '900', RouteName: { Zh_tw: '900' }, SubRouteUID: 'TPE900A', Direction: 0,
    Stops: [
      { StopUID: 'TPE1001', StopName: { Zh_tw: '市政府' }, StopSequence: 1, StopBoarding: -1 },
      { StopUID: 'TPE1004', StopName: { Zh_tw: '台北車站' }, StopSequence: 2, StopBoarding: 0 },
    ],
  },
];

export const routes = [
  {
    RouteUID: 'TPE265', RouteName: { Zh_tw: '265' }, DestinationStopNameZh: '台北車站',
    SubRoutes: [
      { SubRouteUID: 'TPE265A', Direction: 0, Headsign: '往台北車站' },
      { SubRouteUID: 'TPE265A', Direction: 1, Headsign: '往松山' },
    ],
  },
];

export function estimate(overrides: Record<string, unknown>) {
  return {
    PlateNumb: 'KKA-0001',
    StopUID: 'TPE1001',
    RouteUID: 'TPE265',
    RouteName: { Zh_tw: '265' },
    SubRouteUID: 'TPE265A',
    Direction: 0,
    EstimateTime: 300,
    StopStatus: 0,
    IsLastBus: false,
    SrcUpdateTime: '2026-10-09T08:00:00+08:00',
    UpdateTime: '2026-10-09T08:00:05+08:00',
    ...overrides,
  };
}

export const alert = {
  AlertID: 'A1',
  Title: '265 改道',
  Description: '因施工改道，市政府站暫不停靠',
  Status: 2,
  Effect: 1,
  Scope: { Routes: [{ RouteID: '265', Direction: 0 }], Stops: [{ StopID: '1001' }] },
  StartTime: '2026-10-01T00:00:00+08:00',
  EndTime: '2026-12-31T23:59:59+08:00',
};
