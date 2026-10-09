import SwiftUI

/// Phase 0 首頁：開始模擬導航，驗證動態島、鎖定畫面與本機通知。
struct HomeView: View {
    @Bindable var viewModel: HomeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                header

                if let step = viewModel.currentStep {
                    InstructionCard(step: step)
                    Button("結束模擬") { Task { await viewModel.stop() } }
                        .buttonStyle(.secondary)
                } else {
                    introCard
                }

                if let notice = viewModel.notice {
                    NoticeBanner(notice: notice)
                }

                Button {
                    Task { await viewModel.sendTestNotification() }
                } label: {
                    Label("傳送測試通知", systemImage: "bell")
                }
                .buttonStyle(.secondary)
            }
            .padding(Theme.spacing)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await viewModel.performPrimaryAction() }
            } label: {
                Label(viewModel.primaryActionTitle, systemImage: viewModel.isRunning ? "arrow.right" : "location.fill")
            }
            .buttonStyle(.primary)
            .padding(Theme.spacing)
            .background(.bar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("一步搭")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("帶您輕鬆搭車・安心到達")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SimulatedBadge()
            Label("目的地：\(viewModel.script.destinationName)", systemImage: "mappin.circle.fill")
                .font(.title2.bold())
            Text("按下「開始模擬導航」後，動態島與鎖定畫面會顯示模擬指令「120 公尺後右轉」。")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}

#if DEBUG
@MainActor
private final class PreviewLiveActivity: LiveActivityControlling {
    var areActivitiesEnabled = true
    var isRunning = false
    func start(attributes: NavigationActivityAttributes, state: NavigationActivityAttributes.ContentState) throws {}
    func update(_ state: NavigationActivityAttributes.ContentState) async {}
    func end(finalState: NavigationActivityAttributes.ContentState?) async {}
}

private struct PreviewNotifications: NotificationScheduling {
    func permission() async -> NotificationPermission { .authorized }
    func requestPermission() async throws -> Bool { true }
    func schedule(_ notification: LocalNotification, after delay: TimeInterval) async throws {}
    func cancelAll() async {}
}

#Preview("首頁・明亮") {
    HomeView(viewModel: HomeViewModel(liveActivity: PreviewLiveActivity(), notifications: PreviewNotifications()))
        .preferredColorScheme(.light)
}

#Preview("首頁・暗黑") {
    HomeView(viewModel: HomeViewModel(liveActivity: PreviewLiveActivity(), notifications: PreviewNotifications()))
        .preferredColorScheme(.dark)
}
#endif
