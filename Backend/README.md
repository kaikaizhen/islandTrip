# 島行後端（NAS）

TDX 保密代理：TDX 密鑰只存在這裡，App 只知道本服務網址與 App 金鑰。部署在家中 NAS（Docker）。

- **REST**：公車到站時間、站牌、路線；軌道車站、發車、通阻（TDX MQTT 目前沒有到站資料）
- **MQTT**：常駐訂閱 `v2/Bus/Alert/City/{縣市}` 通阻消息；斷線或超過 10 分鐘沒更新時，查詢會改用 REST 補抓
- 公車縣市：臺北、新北、基隆、桃園、臺中、高雄；軌道：臺鐵、高鐵、臺北／新北／桃園機場／高雄／臺中捷運
- 軌道時間一律以臺北時區換算（NAS 可能設為 UTC）
- 所有 TDX 欄位依官方規格核對，見 [docs/TDX-FIELDS.md](docs/TDX-FIELDS.md)

## 設計重點

- 站牌、站序、路線每天下載一次並存到 `DATA_DIR`（約每天 18 次 TDX 呼叫），附近站牌搜尋與路線配對在本服務內完成
- 方向判斷用 `StopOfRoute` 站序（上車站序 < 下車站序、同一附屬路線與方向），不用到站資料的 `Direction`（官方註明該欄位是車輛方向）
- 到站預估：同縣市的站一次以 `$filter` 批次查詢，快取 20 秒；`EstimateTime` 為 null 時回傳 `arrivalAt: null` 與狀態，不偽造時間
- 搭乘時間：同一部車在下車站也有預估時相減（`rideSource: vehicle`），否則以站數 × 90 秒估計（`rideSource: stopCount`），App 需標示「估計」
- token 每 5 小時更新、併發只取一次；TDX 429/5xx 退避重試
- 安全：`/v1` 需 `x-app-key`；每 IP 每分鐘 60 次；Log 只記方法、路由與狀態碼，不記經緯度；錯誤不回傳上游細節

## 開發

```bash
export PATH=/opt/homebrew/opt/node@22/bin:$PATH
npm install
npm test            # 單元測試（合成資料，結構依官方 Swagger）
npm run typecheck
cp .env.example .env  # 填入 TDX 金鑰與 APP_API_KEY
npm run build && node --env-file=.env dist/index.js
```

## API（App 使用）

所有 `/v1` 請求帶 `x-app-key: <APP_API_KEY>`。

| 方法 | 路徑 | 說明 |
|---|---|---|
| GET | `/health` | 健康檢查（不需金鑰）：MQTT 狀態、各縣市靜態資料載入時間 |
| GET | `/v1/journeys?originLat&originLon&destinationLat&destinationLon` | 起點／目的地 500 公尺內可直達的公車方案，含路線（`uid`、`id`=RouteID、名稱、方向描述）、上下車站、對面同名站牌、到站預估、搭乘時間 |
| GET | `/v1/plan?originLat&originLon&destinationLat&destinationLon` | 跨運具方案（TDX MaaS，最多 5 條，只步行轉乘）：每段為 `walk`／`wait`／`transit`；公車段能對回 TDX 站牌（路線名＋站名＋座標＋站序方向）時附 `realtime`（`city`、`stopUID`、`routeUID`、`subRouteUID`、`arrival` 即時到站、`boardingStop` 上車站牌、`oppositeStop` 對面同名反方向站牌或 null），其他段為表定時間 |
| GET | `/v1/stops/nearby?lat&lon&radius` | 附近站牌（50–1000 公尺） |
| GET | `/v1/arrivals?city&stopUID` | 單一站牌各路線到站預估 |
| GET | `/v1/alerts?city` | 目前有效的通阻消息 |
| GET | `/v1/rail/stations/nearby?lat&lon&radius` | 附近臺鐵、高鐵、捷運車站（100–3000 公尺，預設 1500） |
| GET | `/v1/rail/departures?system&stationID` | 車站即將發車（未來 2 小時、最多 12 班），每筆標示資料等級 |
| GET | `/v1/rail/alerts?system` | 軌道通阻（捷運 TRTC/KRTC/TYMC/TMRT、高鐵）；不支援時 `supported: false` |

軌道系統 `system`：`TRA`、`THSR`、`TRTC`、`NTMC`、`TYMC`、`KRTC`、`TMRT`。

`dataLevel`（App 必須清楚標示）：
- `realtime`：臺北／高雄／桃園機場捷運即時看板（桃園僅 A1–A21）、臺鐵即時誤點
- `timetable`：高鐵、臺鐵沒有即時資料的列車、新北捷運、即時看板沒資料時的捷運
- `frequency`：臺中捷運（只有班距，`headway` 為最小／最大分鐘）

`arrival.status`：`normal`、`notDeparted`（尚未發車）、`noStop`（交管不停靠）、`lastBusPassed`（末班車已過）、`notOperating`（今日未營運）、`noBus`（目前無車）、`unknown`。

## 部署到 NAS

使用 `ssh-publish` skill（「把島行後端發佈到 NAS」）：本機建置映像 → 傳到 NAS → `docker compose up`。NAS 上需放置 `.env`。App 從外網連線需要 HTTPS（反向代理），部署前確認網域與憑證。
