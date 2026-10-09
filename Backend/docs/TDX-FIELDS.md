# TDX 欄位核對紀錄

> 核對日期：2026-10-09。依計畫規定「不要臆造交通 API 欄位」，以下皆取自官方來源；程式只使用這裡列出的欄位。官方規格更新時請重新核對。

## 來源

- 公車 Swagger（OpenAPI 3.0.4，「公共運輸-公車 v2」）：https://tdx.transportdata.tw/webapi/File/Swagger/V3/2998e851-81d0-40f5-b26d-77e2f5ac4118
- 認證與呼叫範例：https://github.com/tdxmotc/SampleCode
- MQTT 範例：https://github.com/tdxmotc/MQTTSampleCode
- 公車動態資料使用注意事項：https://motc-ptx.gitbook.io/tdx-zi-liao-shi-yong-kui-hua-bao-dian/data_notice/public_transportation_data/bus_dynamic_data

## 認證

- `POST https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token`
- `Content-Type: application/x-www-form-urlencoded`，`grant_type=client_credentials`、`client_id`、`client_secret`
- 回應 `access_token`、`expires_in`（預設 86400 秒）、`token_type=Bearer`
- 官方建議每 4–6 小時更新一次，不要每次呼叫都取 token；token 端點每 IP 每分鐘 20 次
- 呼叫 API：`Authorization: Bearer {token}`，可加 `Accept-Encoding: br,gzip`
- 計費：計次 1,500 次／1 點；訪客模式每 IP 每日 20 次

## REST（基底 `https://tdx.transportdata.tw/api/basic`）

縣市代碼（`City` 參數 enum 子集）：`Taipei`、`NewTaipei`、`Keelung`、`Taoyuan`、`Taichung`、`Kaohsiung`

共用參數：`$select`、`$filter`、`$orderby`、`$top`、`$skip`、`$format`。`Stop/City` 未列出空間查詢參數，因此不使用 `$spatialFilter`。

| 端點 | 回傳型別 |
|---|---|
| `/v2/Bus/Stop/City/{City}` | `BusStop` |
| `/v2/Bus/StopOfRoute/City/{City}` | `BusStopOfRoute` |
| `/v2/Bus/Route/City/{City}` | `BusRoute` |
| `/v2/Bus/EstimatedTimeOfArrival/City/{City}` | `BusN1EstimateTime` |
| `/v2/Bus/Alert/City/{City}` | `BusAlert` |

### 共用型別
- `NameType`：`Zh_tw`、`En`
- `PointType`：`PositionLat`、`PositionLon`（WGS84）

### BusStop
`StopUID`、`StopID`、`StopName`、`StopPosition`、`Bearing`（E/W/S/N/SE/NE/SW/NW）、`StationID`、`City`

### BusStopOfRoute
`RouteUID`、`RouteID`、`RouteName`、`SubRouteUID`、`SubRouteID`、`SubRouteName`、`Direction`（0 去程、1 返程、2 迴圈、10 循環線、255 未知）、`Stops[]`：`StopUID`、`StopName`、`StopBoarding`（-1 可下車、0 可上下車、1 可上車）、`StopSequence`、`StopPosition`、`StationID`

### BusRoute
`RouteUID`、`RouteName`、`SubRoutes[]`：`SubRouteUID`、`Headsign`、`Direction`、`DestinationStopNameZh`

### BusN1EstimateTime（預估到站）
`PlateNumb`（-1 表示該站位目前無車輛行駛）、`StopUID`、`RouteUID`、`RouteName`、`SubRouteUID`、`Direction`、`EstimateTime`（秒）、`StopStatus`、`IsLastBus`、`SrcUpdateTime`、`SrcTransTime`、`UpdateTime`

- `StopStatus`：0 正常、1 尚未發車、2 交管不停靠、3 末班車已過、4 今日未營運
- `EstimateTime`：StopStatus 2–4 或 PlateNumb = -1 時為 null；StopStatus 1 時多數為 null；StopStatus 0 時有值
- **`Direction` 是「該車輛目前所在路線」的方向，不是站牌所在路線的方向** → 方向判斷改用 StopOfRoute 站序
- 官方提示：實際剩餘時間 = `EstimateTime − (收到資料時間 − SrcTransTime)`；非公總系統沒有 `SrcTransTime`，改用 `SrcUpdateTime`
- N1 只提供距該路線最近車輛的預估

### BusAlert（通阻）
`AlertID`、`Title`、`Description`、`Status`（0 全部停止、1 全部正常、2 有異常）、`Cause`、`Effect`（1 改道／站牌不停靠、3 班次減少、4 班次取消、6 站點異動、7 重大延遲…）、`Scope`、`AlertURL`、`PublishTime`、`StartTime`、`EndTime`、`UpdateTime`

`Scope`：`Routes[]`（`RouteID`、`RouteName`、`Direction`）、`SubRoutes[]`（`SubRouteID`、`Direction`）、`Stops[]`（`StopID`、`StationID`）、`Stations[]`、`Operators[]`、`Trips[]`

## MQTT

- `mqtts://mqtt.transportdata.tw:8883`，以會員中心「資料存取金鑰」的 ClientId／Username／Password 連線
- 同一組帳密與 ClientId 只能一條連線，第二條會中斷第一條
- 公車主題：`v2/Bus/Alert/City/{縣市代碼}`、`v3/Bus/Alert/City/{縣市代碼}`、`v2/Bus/News/City/{縣市代碼}`
- **目前沒有到站時間、即時位置的主題**
- 建議 CleanSession = true；初期不收費，日後依接收量計費
- 訊息內容格式：官方說明為 JSON；實際格式需以真實連線驗證（目前程式以 BusAlert 欄位寬鬆解析，單筆或陣列皆可）
