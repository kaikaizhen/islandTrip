import SwiftUI

/// 設定：資料來源說明與 Phase 0 能力測試入口。
struct SettingsView: View {
    @Bindable var settings: AppSettings
    let makeCapabilityTestViewModel: () -> CapabilityTestViewModel
    let onOpenWalkTest: () -> Void
    @Environment(\.isMockTransit) private var isMockTransit

    var body: some View {
        List {
            Section {
                Picker("出發地位置", selection: $settings.locationSource) {
                    ForEach(LocationSource.allCases, id: \.self) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("位置來源")
            } footer: {
                Text(isMockTransit ? "班次目前是模擬資料，站牌在台北市政府附近。不在台北時，可用「模擬」走完公車流程；「步行導航測試」則一律使用 GPS。" : "使用真實班次時請選 GPS；「模擬」只適合沒有網路時展示流程。")
            }
            Section {
                Picker("轉乘方案排序", selection: $settings.planPreference) {
                    ForEach(PlanPreference.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("planPreference")
                Picker("步行速度", selection: $settings.walkingPace) {
                    ForEach(WalkingPace.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("walkingPace")
                Picker("趕車預留時間", selection: $settings.bufferMinutes) {
                    ForEach(AppSettings.bufferChoices, id: \.self) { Text("\($0) 分鐘").tag($0) }
                }
                .accessibilityIdentifier("bufferMinutes")
            } header: {
                Text("路線偏好")
            } footer: {
                Text("慢慢走會把步行時間多抓一些；預留時間越長，「趕得上」的判斷越保守。")
            }
            Section("資料來源") {
                if isMockTransit {
                    Label("班次：模擬資料（不是即時班次）", systemImage: "testtube.2")
                        .font(.title3)
                } else {
                    Label("班次：TDX 即時資料（經家中 NAS）", systemImage: "bus.fill")
                        .font(.title3)
                }
                Label("地點搜尋、步行路線：Apple 地圖", systemImage: "map")
                    .font(.title3)
            }
            Section("開發者") {
                Button(action: onOpenWalkTest) {
                    Label("步行導航測試（真實 GPS）", systemImage: "figure.walk")
                        .font(.title3)
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("walkTest")
                NavigationLink {
                    CapabilityTestScreen(viewModel: makeCapabilityTestViewModel())
                } label: {
                    Label("能力測試：動態島與通知", systemImage: "iphone.radiowaves.left.and.right")
                        .font(.title3)
                        .frame(minHeight: 44)
                }
            }
        }
        .navigationTitle("設定")
    }
}

private struct CapabilityTestScreen: View {
    @State var viewModel: CapabilityTestViewModel

    var body: some View {
        CapabilityTestView(viewModel: viewModel)
            .navigationTitle("能力測試")
            .navigationBarTitleDisplayMode(.inline)
    }
}
