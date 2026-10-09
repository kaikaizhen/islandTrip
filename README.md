# 島行 — Phase 3（進行中）

iOS 大眾運輸圖像導航助手。Phase 0 驗證平台能力；Phase 1 以模擬資料完成搭車流程；Phase 2 加入真實 GPS、Apple 地圖步行指引、上車側與路口過馬路提示（班次仍是模擬）。計畫全文見 [docs/島行執行計劃.md](docs/島行執行計劃.md)，已確認的決策見 [DECISIONS.md](DECISIONS.md)。

## 開發環境

| 項目 | 版本 |
|---|---|
| macOS | 27.0.1 |
| Xcode | 27.0 (27A266a) |
| Swift | 6.4（專案使用 Swift 6 語言模式，嚴格並行檢查） |
| 最低部署 | iOS 18.0（Apple Watch Smart Stack 顯示 Live Activity 需 iOS 18 / watchOS 11） |
| 專案產生 | XcodeGen 2.46（`project.yml` → `YiBuDa.xcodeproj`，`.xcodeproj` 不進 Git） |

首次設定（需 sudo，只做一次）：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch
xcodebuild -downloadPlatform iOS     # 若尚無 iOS 模擬器 runtime
brew install xcodegen
```

## 啟動

```bash
cp Config/Local.example.xcconfig Config/Local.xcconfig   # 填入 DEVELOPMENT_TEAM（實機才需要）
xcodegen generate
open YiBuDa.xcodeproj
```

命令列建置與測試（模擬器）：

```bash
xcodebuild -scheme YiBuDa -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test

# 另外執行需要網路的測試（真實 Apple 地圖搜尋、模擬器 GPS 沿真實步行路線移動）
xcrun simctl privacy booted grant location com.zhenkaikai.yibuda
TEST_RUNNER_RUN_NETWORK_TESTS=1 xcodebuild -scheme YiBuDa -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:YiBuDaUITests/RealPlaceSearchUITests -only-testing:YiBuDaUITests/GPSWalkUITests test
```

UI 測試以啟動參數 `-mockPlaceSearch`、`-mockWalking` 改用離線目的地搜尋與模擬步行段，因此完整流程測試不依賴網路。

資料模式：未設定後端時為 **Mock 模式**（`MockTransportProvider`，完全離線，畫面標示「模擬資料」）；在 `Config/Local.xcconfig` 設定 NAS 後端後為 **Real 模式**（`RemoteTransportProvider`，見下方 Phase 3）。切換只在 `AppDependencies.live()`，ViewModel 不需修改。

### Phase 1 操作流程

首頁輸入「台北」選「台北車站」（或點常用地點）→ 開始找車 → 推薦班次（主推 265，其他方案可展開、切換排序）→ 開始導航 → 步行 3 步 → 確認上車側（需過馬路）→ 候車（可改選同站其他班）→ 我已上車 → 模擬前進一站 → 準備下車 → 我已下車 → 步行 2 步 → 已抵達 → 結束導航。

目的地搜尋使用 Apple MapKit（`MKLocalSearch`），取得真實地點名稱、地址與座標，並以目前位置附近優先；需要網路。Mock 模式時**班次與站牌是固定的模擬資料**（市政府站 → 台北車站），不會隨目的地改變，推薦班次畫面會明確標示；Real 模式依起點與目的地附近 500 公尺內的站牌計算。常用地點（家／公司／學校）目前也是模擬座標。

推薦班次畫面可按「在地圖上確認」：以 Apple MapKit 顯示你的位置、正確上車站、對面同名反方向站牌（灰色「不是這個」）、下車站與目的地；步行段為 MapKit 計算的實際步行路線（需網路，失敗時以直線示意並標明），公車段尚無路線形狀資料，以虛線示意。預設放大上車站附近，可切換「全程」。

### Phase 2：GPS 與步行導航

- **出發地**：依「設定 > 位置來源」使用 GPS 或模擬位置（班次仍是模擬，預設模擬）；首頁可點出發地手動輸入，定位失敗時會說明原因。
- **步行指令**：步行段改用 Apple 地圖步行路線；轉向由路線幾何判斷，轉成「往前走 120 公尺，到路口右轉」，路名等原文以小字附上。取得失敗時改為標示「估計」的直線估計。
- **GPS 自動推進**（位置來源為 GPS、或步行導航測試時）：誤差 > 50 公尺的定位點不採用；連續 2 筆接近轉彎點才前進、一次最多一步；連續 3 筆偏離 35 公尺以上才判定走錯路，可「從這裡重新規劃路線」；保留手動「下一步／回上一步」與「依目前位置重新定位」。定位只在導航期間開啟，結束即停止。
- **路口左右側（D3）**：轉彎步驟會問「你走在馬路哪一邊」，在對側時顯示路口示意圖與走法（在路口走斑馬線過馬路，不穿越車道）。
- **上車側**：使用者回答 > 穩定 GPS 判斷（以兩側同名站牌為參考，連續 3 筆一致）> 站牌資料；都沒有就問「你旁邊這一側的站牌寫哪個方向」。
- **手機方向（D5）**：步行每一步先「對準方向」，平拿手機慢慢轉身，對準步行路線的方向時圓圈變藍並震動；地圖預覽新增「我的方向」模式（地圖跟著手機轉，位置以小手機圖示表示）。需要真實位置與指南針，模擬器無法測試指南針。
- **步行導航測試**：設定 > 步行導航測試。用真實 GPS 走到附近任一地點（不含公車），不在台北也能驗證 Phase 2。

### Phase 3：真實班次（TDX，經家中 NAS）

架構（決策 D6）：App → 家中 NAS 後端（[Backend/](Backend/README.md)，TDX 密鑰只在這裡）→ TDX REST（到站、站牌、路線）＋ MQTT（通阻消息）。支援臺北、新北、基隆、桃園、臺中、高雄。

1. 在 NAS 部署後端（見 [Backend/README.md](Backend/README.md)；可用 `ssh-publish` skill）。
2. 在 `Config/Local.xcconfig` 設定 `YIBUDA_BACKEND_URL`（寫成 `https:/$()/網域`）與 `YIBUDA_APP_KEY`（與 NAS `.env` 的 `APP_API_KEY` 相同），重新 `xcodegen generate`。
3. 未設定時 App 自動使用模擬資料；設定後「模擬資料」標示消失，設定頁顯示「班次：TDX 即時資料」，位置來源預設改為 GPS。

真實資料時：
- 沒有預估到站時間會顯示原因（尚未發車、末班車已過、今日未營運、交管不停靠、目前沒有車），不偽造分鐘數。
- 搭乘時間來自同一部車在上下車站的預估相減；沒有時依站數估計並標示「（估計）」。
- 路線有通阻消息（改道、停駛…）時，推薦班次頂端與該方案卡片會顯示。
- 上車側沒有站牌資料可依，改由 GPS（以兩側同名站牌為參考）或詢問使用者判斷。

### 臺鐵、高鐵、捷運（車站資訊）

首頁「附近車站（捷運、臺鐵、高鐵）」→ 選車站 → 即將發車看板。支援臺鐵、高鐵、臺北／新北／桃園機場／高雄／臺中捷運（決策 D8）。

- 每一班都標示資料等級：**即時**（臺北、高雄、桃園機場捷運即時看板；臺鐵誤點）、**依時刻表**（高鐵、新北捷運、沒有即時資料時）、**班距**（臺中捷運「約每 N 分鐘一班」）。
- 臺鐵即時資料顯示「誤點 N 分」或「準點」；時刻表資料不顯示準點或誤點。
- 有即時資料時每 30 秒自動更新。
- 營運異常消息：捷運（臺北、高雄、桃園機場、臺中）與高鐵；臺鐵、新北捷運目前無法提供時會說明。

### 轉乘方案（含捷運、火車；只供查看）

推薦班次頁下方的「轉乘方案」：由後端 `/v1/plan` 呼叫 TDX MaaS 旅運規劃，可組合公車、捷運、臺鐵、高鐵、輕軌（決策：與直達公車並列、分階段做）。

- 點方案可看地圖示意與逐步說明（走到哪、搭什麼往哪、在哪下車、站內步行、等車）。
- 每一段搭乘都標示 **即時** 或 **表定**：只有對得上 TDX 站牌的公車段有即時到站；捷運、火車段與對不上的公車段（例：MaaS 路網有、TDX 公車 API 查無的路線）一律標「表定」。
- MaaS 較慢（實測 2～40 秒），與直達公車分開載入，查不到時只顯示提示，不影響直達公車。
- **尚未支援轉乘導航**（Step B）：目前只能查看步驟，開始導航仍限直達公車。

Phase 0 的動態島／通知測試移到「設定（右上齒輪）→ 能力測試」。

模擬資料涵蓋計畫的測試案例：同站 307/212/265/671；307 先到但走不到；265 較晚到站卻較早抵達；212 資料過期；671 查無預估；對面同名反方向站牌的 307 不會列入。

## 架構

SwiftUI + MVVM + Protocol + `@Observable` + Swift Concurrency；單一 App target，以資料夾分層。

```
YiBuDa/                     App target
  App/                      進入點、RootView、AppRouter（畫面流程）、AppDependencies（composition root）
  Models/                   Place、Stop、RoutePattern、BoardingOption、Journey、NavigationInstruction
  Providers/                TransportProvider 等協定；Mock/ 為離線模擬資料
  Services/Transit/         TransitRankingService（能否趕上、排序、主推）、BoardingDirectionValidator（方向/站序檢查）
  Services/Navigation/      NavigationStateMachine（導航狀態轉移）
  Services/                 LiveActivity、Notifications、Simulation（Phase 0）
  Features/                 Home、Options（推薦班次）、Navigation（步行/上車側/候車/搭乘/到達）、Settings、CapabilityTest
  Features/Components/      共用按鈕、卡片、文字格式（TransitFormat）
Shared/                     同時編入 App 與 Live Activity 擴充
YiBuDaLiveActivity/         Widget Extension，只含 Live Activity（無主畫面 Widget）
YiBuDaTests/                Swift Testing 單元測試
YiBuDaUITests/              完整模擬流程、Phase 0 動態島煙霧測試
```

- **SRP**：排序（TransitRankingService）、方向檢查（BoardingDirectionValidator）、狀態轉移（NavigationStateMachine）、資料來源（Provider）各自獨立，皆為純邏輯可單元測試。
- **DIP / ISP**：ViewModel 只依賴小協定（`TransportProvider`、`PlaceSearching`、`FavoritePlacesProviding`、`CurrentPlaceProviding`）；具體實作只在 `AppDependencies` 決定。
- **OCP**：Phase 3 新增 `TDXTransportProvider`、Phase 2 新增定位實作時，不需修改 ViewModel。
- 上車、下車採手動確認（計畫 4.3）；剩餘站數只在模擬時顯示並標示「模擬」。
- Live Activity 不連網、不讀 GPS；`staleDate` 為更新後 120 秒。

## 必要權限

| 權限 | 用途 | 狀態 |
|---|---|---|
| `NSSupportsLiveActivities` | 動態島／鎖定畫面 | 已設定 |
| 通知（執行時詢問） | 測試通知 | 按「傳送測試通知」時才詢問 |
| 定位（使用 App 期間） | 出發地、導航中步行進度、上車側判斷 | 需要時才詢問；只在導航期間持續定位 |
| 背景定位模式（`UIBackgroundModes: location`） | 導航中鎖定螢幕仍能更新步行進度 | 以 `CLBackgroundActivitySession` 只在導航期間啟用 |

## 實機驗證步驟（需你在裝置上執行）

1. iPhone：設定 > 隱私權與安全性 > 開發者模式 開啟；用 USB 連 Mac。
2. Xcode > Settings > Accounts 登入 Apple ID；將 Team ID 填入 `Config/Local.xcconfig`，重新 `xcodegen generate`。
3. 選擇實體 iPhone 執行。免費 Personal Team 的描述檔約 **7 天到期**，到期需重新安裝。
4. 首次啟動後 iPhone：設定 > VPN 與裝置管理 信任開發者。
5. **Phase 2 步行導航（需走路）**：設定 > 步行導航測試 → 選一個 300 公尺～1 公里、至少轉兩個彎的地點 → 邊走邊確認：大箭頭與「還有 N 公尺」更新、到轉角後自動換下一步、停在原地或手機晃動時不會亂跳、故意走錯一段會出現「好像走錯路了」。請記錄是否至少 2 個轉向步驟依序正確（Phase 2 完成條件）。
6. **手機方向（D5，需真機）**：步行導航測試開始後，平拿手機轉一圈：箭頭會跟著轉、對準時震動並顯示「方向對了，往前走」；地圖預覽切到「我的方向」時，地圖應跟著手機轉、手機圖示朝上。請記錄在騎樓或大樓旁時指南針是否常出現「不準」。
7. **Live Activity**：按「開始模擬導航」→ 回主畫面，確認動態島（收合顯示箭頭 + 120m，長按可展開）→ 鎖定 iPhone，確認鎖定畫面顯示「前方右轉／120 公尺後右轉／模擬」→ 回 App 按「模擬下一步」，確認距離變為 80m。
8. **Apple Watch Smart Stack**：手錶 watchOS 11+、與 iPhone 配對；開始模擬後鎖定 iPhone，在手錶轉動錶冠開啟 Smart Stack，確認出現箭頭與距離。若沒出現：iPhone「Watch」App > 一般 > 智慧型疊放 > 即時動態 確認已開啟。
9. **本機通知**：按「傳送測試通知」並允許 → 5 秒內鎖定 iPhone，觀察手錶。手錶需配戴、解鎖、未開勿擾，iPhone 需鎖定且螢幕關閉，iOS 才會轉送到手錶；不保證每次都由手錶震動。
10. 記錄結果到下方表格。

## 測試結果

| 項目 | 結果 |
|---|---|
| 模擬器建置（iOS 27.0, iPhone 18 Pro） | 通過，0 warning（2026-10-09） |
| 單元測試（Swift Testing） | 131 項全數通過：軌道發車文字（即時／時刻表／班距、誤點）、後端回應轉換（真實時間、估計搭乘、無預估原因、對面站牌、異常消息）、指南針對準（滯後、繞 360 度、誤差過大不判斷、沿路線方向）、排序、反向站牌、狀態轉移、Apple 地圖步驟轉指令、GPS 合成軌跡（漂移／跳點／不準／偏離）、左右側建議、上車側 GPS 判斷 |
| UI：完整模擬流程（離線） | 通過，含「我在左邊 → 先在路口過馬路」路口示意圖 |
| UI：暗黑＋無障礙特大字 | Phase 1 通過（Phase 2 新畫面尚未以特大字跑過） |
| UI：地圖預覽、真實地點搜尋（需網路） | 通過 |
| UI：模擬器 GPS 沿真實 Apple 地圖路線走（需網路） | 通過：台北市政府 → 誠品信義店，3 個步驟依序自動前進至「已抵達」，無重複、無回跳 |
| Apple Watch Smart Stack（40mm） | 使用者實機確認文字正常 |
| **實機步行（Phase 2 完成條件）** | **尚未驗證**：需在真機用「步行導航測試」走一段至少 2 個轉彎的路 |
| 實機背景定位（鎖定螢幕後繼續推進） | **尚未驗證** |
| 後端（Backend/） | 46 項測試通過（含軌道 13 項：臺北時區、即時→時刻表→班距、通阻）（合成資料，結構依官方 Swagger）；以假金鑰啟動確認可運作、Log 不含密鑰與位置 |
| **TDX 真實資料、MQTT 實際訊息** | **尚未驗證**：需要 TDX 金鑰與 NAS 部署 |
| 指南針「對準方向」與震動、「我的方向」地圖 | **尚未驗證**（模擬器沒有指南針；判斷邏輯 9 項單元測試通過、畫面以渲染圖檢視） |
| 上車側 GPS 判斷的實際準確度 | **尚未驗證** |
| VoiceOver 實際朗讀 | **尚未驗證** |

## 已知限制與 fallback

- Phase 1 全部是模擬資料：目前位置、班次、步行指令、上車側都是固定內容，畫面皆標示「模擬」。
- 目前位置不可手動輸入（Phase 2 接 Core Location 時一併加入）；「行程」分頁未做（計畫未要求）。
- 換方案的防閃爍門檻（計畫 4.1）需即時資料，排在 Phase 3。
- 導航中尚未更新 Live Activity（計畫排在 Phase 4）。

- Live Activity 被使用者關閉或啟動失敗時，App 內仍可繼續模擬並顯示提示。
- 通知被拒絕時顯示前往設定的提示，不重複詢問。
- 通知使用一般（`active`）等級；時效性通知需額外 entitlement，待 Phase 4 確認 Personal Team 是否可用。
- 未使用遠端推播（APNs），Live Activity 只能在 App 執行或背景存活時更新。
- 模擬器上 Widget Extension 必須經過簽署（本機 ad-hoc 即可）才會顯示 Live Activity；請勿加 `CODE_SIGNING_ALLOWED=NO`。
- App Icon 由 `docs/appIcon.png` 裁切內框而成；原圖內含圓角外框，若有無外框版本效果更好。
- 機密：App 內不存放任何 TDX 憑證；`Config/Local.xcconfig` 已列入 `.gitignore`。
