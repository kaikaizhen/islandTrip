import SwiftUI

/// 步行導航測試入口。
struct WalkTestView: View {
    @Bindable var viewModel: WalkTestViewModel
    let onStart: (Journey) -> Void

    @State private var showsPicker = false

    var body: some View {
        List {
            Section {
                Text("用真實 GPS，跟著 Apple 地圖的步行路線走到附近任一地點（不含公車）。建議選 300 公尺到 1 公里、至少轉兩個彎的地點。")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                SafetyNote(text: "走路時請注意周圍與車輛，不要一直盯著手機。")
            }
            Section("目前位置") {
                switch viewModel.state {
                case .locating:
                    ProgressView("正在定位…")
                case .planning:
                    ProgressView("正在規劃步行路線…")
                case .ready(let sample):
                    Label("已定位，誤差約 \(Int(sample.horizontalAccuracy.rounded())) 公尺", systemImage: "location.fill")
                case .failed(let message):
                    SafetyNote(text: message)
                    Button("再試一次") { Task { await viewModel.locate() } }
                }
            }
        }
        .navigationTitle("步行導航測試")
        .bottomAction("選擇要走去的地點", systemImage: "figure.walk", isEnabled: viewModel.currentSample != nil) {
            showsPicker = true
        }
        .sheet(isPresented: $showsPicker) {
            PlacePickerView(title: "走去哪裡？", search: viewModel.search, near: viewModel.currentSample?.coordinate) { place in
                Task {
                    if let journey = await viewModel.makeJourney(to: place) { onStart(journey) }
                }
            }
        }
        .task { await viewModel.locate() }
    }
}
