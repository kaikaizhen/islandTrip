# 一步搭（暫定名）— Phase 0

iOS 大眾運輸圖像導航助手。本階段只驗證平台能力：SwiftUI App、**僅 Live Activity 的 Widget Extension**、本機通知。計畫全文見 [docs/島行執行計劃.md](docs/島行執行計劃.md)，已確認的決策見 [DECISIONS.md](DECISIONS.md)。

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
xcodebuild -scheme YiBuDa -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

目前只有 **Mock 模式**：所有導航內容來自 `SimulatedNavigationScript.phase0`，App 與 Live Activity 都會標示「模擬」。Real 模式（TDX + Cloudflare Workers）在 Phase 3 才加入。

## 架構

SwiftUI + MVVM + Protocol + `@Observable` + Swift Concurrency；單一 App target，以資料夾分層。

```
YiBuDa/                     App target
  App/                      進入點、AppDependencies（composition root，唯一決定具體實作的地方）
  Features/Home/            View + ViewModel
  Features/Components/      共用按鈕樣式、卡片、提示
  Services/                 協定 + 系統實作（LiveActivity、Notifications、Simulation）
Shared/                     同時編入 App 與 Live Activity 擴充
  Models/                   Maneuver（箭頭種類）、DistanceFormatter
  LiveActivity/             NavigationActivityAttributes（App ↔ 擴充的資料契約）
  DesignSystem/             Theme（單一藍色、24pt 圓角、60pt 按鈕）、ManeuverArrow
YiBuDaLiveActivity/         Widget Extension，只含 Live Activity（無主畫面 Widget）
YiBuDaTests/                Swift Testing 單元測試與假物件
```

- `HomeViewModel` 只依賴 `LiveActivityControlling`、`NotificationScheduling` 協定（DIP），測試時注入假物件。
- 新的資料來源或服務以新增實作加入，不修改 ViewModel（OCP）；Phase 3 的 `TransportProvider` 沿用同一模式。
- Live Activity 不連網、不讀 GPS，所有內容由 App 推送；`staleDate` 設為更新後 120 秒，過期顯示「資訊可能過期」。

## 必要權限

| 權限 | 用途 | 狀態 |
|---|---|---|
| `NSSupportsLiveActivities` | 動態島／鎖定畫面 | 已設定 |
| 通知（執行時詢問） | 測試通知 | 按「傳送測試通知」時才詢問 |
| 定位 | Phase 2 才加入 | 未使用 |

## 實機驗證步驟（需你在裝置上執行）

1. iPhone：設定 > 隱私權與安全性 > 開發者模式 開啟；用 USB 連 Mac。
2. Xcode > Settings > Accounts 登入 Apple ID；將 Team ID 填入 `Config/Local.xcconfig`，重新 `xcodegen generate`。
3. 選擇實體 iPhone 執行。免費 Personal Team 的描述檔約 **7 天到期**，到期需重新安裝。
4. 首次啟動後 iPhone：設定 > VPN 與裝置管理 信任開發者。
5. **Live Activity**：按「開始模擬導航」→ 回主畫面，確認動態島（收合顯示箭頭 + 120m，長按可展開）→ 鎖定 iPhone，確認鎖定畫面顯示「前方右轉／120 公尺後右轉／模擬」→ 回 App 按「模擬下一步」，確認距離變為 80m。
6. **Apple Watch Smart Stack**：手錶 watchOS 11+、與 iPhone 配對；開始模擬後鎖定 iPhone，在手錶轉動錶冠開啟 Smart Stack，確認出現箭頭與距離。若沒出現：iPhone「Watch」App > 一般 > 智慧型疊放 > 即時動態 確認已開啟。
7. **本機通知**：按「傳送測試通知」並允許 → 5 秒內鎖定 iPhone，觀察手錶。手錶需配戴、解鎖、未開勿擾，iPhone 需鎖定且螢幕關閉，iOS 才會轉送到手錶；不保證每次都由手錶震動。
8. 記錄結果到下方表格。

## 測試結果

| 項目 | 結果 |
|---|---|
| 模擬器建置（iOS 27.0, iPhone 18 Pro） | 通過，0 warning（2026-10-09） |
| 單元測試（Swift Testing） | 16 項 / 18 案例全數通過 |
| UI 煙霧測試 | 通過：開始 → 主畫面 → 下一步 → 結束 |
| 模擬器動態島（收合） | 通過：顯示右轉箭頭 + 120m，按下一步後更新為 80m（截圖目視確認） |
| 實機 Live Activity / 動態島 | **尚未驗證**（需實體 iPhone） |
| 鎖定畫面 | **尚未驗證** |
| Apple Watch Smart Stack | **尚未驗證**（需實體手錶） |
| 本機通知轉送到 Watch | **尚未驗證** |
| Personal Team 能否使用 Live Activity | **尚未驗證** |

## 已知限制與 fallback

- Live Activity 被使用者關閉或啟動失敗時，App 內仍可繼續模擬並顯示提示。
- 通知被拒絕時顯示前往設定的提示，不重複詢問。
- 通知使用一般（`active`）等級；時效性通知需額外 entitlement，待 Phase 4 確認 Personal Team 是否可用。
- 未使用遠端推播（APNs），Live Activity 只能在 App 執行或背景存活時更新。
- 模擬器上 Widget Extension 必須經過簽署（本機 ad-hoc 即可）才會顯示 Live Activity；請勿加 `CODE_SIGNING_ALLOWED=NO`。
- App Icon 由 `docs/appIcon.png` 裁切內框而成；原圖內含圓角外框，若有無外框版本效果更好。
- 機密：App 內不存放任何 TDX 憑證；`Config/Local.xcconfig` 已列入 `.gitignore`。
