import SwiftUI

/// 設定：資料來源說明與 Phase 0 能力測試入口。
struct SettingsView: View {
    let makeCapabilityTestViewModel: () -> CapabilityTestViewModel

    var body: some View {
        List {
            Section("資料來源") {
                Label("模擬資料（不是即時班次）", systemImage: "testtube.2")
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
