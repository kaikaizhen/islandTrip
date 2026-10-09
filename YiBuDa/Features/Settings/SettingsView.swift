import SwiftUI

/// 設定：資料來源說明與 Phase 0 能力測試入口。
struct SettingsView: View {
    @Bindable var settings: AppSettings
    let makeCapabilityTestViewModel: () -> CapabilityTestViewModel

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
                Text("班次目前是模擬資料，站牌在台北市政府附近。不在台北時，可用「模擬」走完公車流程；「步行導航測試」則一律使用 GPS。")
            }
            Section("資料來源") {
                Label("班次：模擬資料（不是即時班次）", systemImage: "testtube.2")
                    .font(.title3)
                Label("地點搜尋、步行路線：Apple 地圖", systemImage: "map")
                    .font(.title3)
            }
            Section("開發者") {
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
