import SwiftUI

/// 轉乘導航全螢幕：依目前階段顯示對應畫面，每個畫面只有一個主要按鈕。
struct PlanNavigationView: View {
    @Bindable var viewModel: PlanNavigationViewModel
    let onFinish: () -> Void

    @State private var confirmsCancel = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let progress = viewModel.flow.transitProgress {
                    Text(progress)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .accessibilityIdentifier("transitProgress")
                }
                if let warning = viewModel.transferWarning {
                    TransferWarningBanner(warning: warning, canReplan: viewModel.canReplan, isReplanning: viewModel.isReplanning) {
                        Task { await viewModel.replan() }
                    }
                    .padding(.horizontal, Theme.spacing)
                }
                if let message = viewModel.replanMessage {
                    Label(message, systemImage: "info.circle")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.spacing)
                        .accessibilityIdentifier("replanMessage")
                }
                content
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("結束") { confirmsCancel = true }
                        .accessibilityLabel("結束導航")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SimulatedBadge()
                }
            }
            .confirmationDialog("要結束導航嗎？", isPresented: $confirmsCancel, titleVisibility: .visible) {
                Button("結束導航", role: .destructive) { viewModel.cancel() }
                Button("繼續導航", role: .cancel) {}
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .presentationBackground(Color(.systemBackground))
        .sensoryFeedback(.warning, trigger: viewModel.alertCount)
        .task { await viewModel.start() }
        .onChange(of: viewModel.isFinished) { _, finished in
            if finished { onFinish() }
        }
    }

    private var title: String {
        switch viewModel.stage {
        case .walk: "步行"
        case .stationWalk: "車站內"
        case .boardingSide: "確認上車側"
        case .waiting: "候車"
        case .riding: "搭乘中"
        case .arrived: "到達"
        }
    }

    private var backAction: (title: String, action: () -> Void)? {
        guard viewModel.canGoBack else { return nil }
        return ("回上一步", { viewModel.previous() })
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.stage {
        case .walk:
            walkContent
        case .stationWalk(let from, let to, let seconds):
            let upcoming = Self.isExit(viewModel.flow) ? nil : viewModel.flow.upcomingTransit
            StationWalkView(from: from, to: to, seconds: seconds, upcoming: upcoming)
                .bottomAction(upcoming == nil ? "我出站了" : "我到月台了", systemImage: "arrow.right", secondary: backAction) {
                    viewModel.next()
                }
        case .boardingSide:
            boardingContent
        case .waiting:
            waitingContent
        case .riding:
            ridingContent
        case .arrived:
            ArrivedView(destinationName: viewModel.destination.name)
                .bottomAction("結束導航", systemImage: "flag.checkered") {
                    viewModel.cancel()
                }
        }
    }

    /// 站內步行後面沒有搭乘（下一個是戶外步行或到達）就是出站。
    private static func isExit(_ flow: PlanNavigationFlow) -> Bool {
        switch flow.stages[safe: flow.index + 1] {
        case .boardingSide, .waiting, .riding: false
        default: true
        }
    }

    @ViewBuilder
    private var walkContent: some View {
        if let instruction = viewModel.flow.currentInstruction {
            WalkingStepView(
                instruction: instruction, progress: viewModel.stepProgress, nextStep: viewModel.nextStepText,
                liveRemainingMeters: viewModel.liveRemainingMeters, gpsStatus: gpsStatus,
                isRerouting: viewModel.isRerouting,
                onReroute: viewModel.canReroute ? { Task { await viewModel.reroute() } } : nil,
                onRelocate: { viewModel.relocate() },
                turnAdvice: viewModel.turnAdvice,
                onSelectSide: { viewModel.setWalkingSide($0) },
                directionGuidance: viewModel.directionGuidance,
                directionAngle: viewModel.directionRelativeAngle
            )
            .bottomAction(viewModel.walkingPrimaryTitle, systemImage: "arrow.right", secondary: backAction) {
                viewModel.next()
            }
        }
    }

    @ViewBuilder
    private var boardingContent: some View {
        if let target = viewModel.boardingTarget {
            BoardingSideView(target: target, details: viewModel.boardingDetails, resolution: viewModel.boardingResolution) { answer in
                viewModel.answerBoardingSide(answer)
            }
            .bottomAction("我在正確的站牌了", systemImage: "checkmark", secondary: backAction) {
                viewModel.next()
            }
        }
    }

    @ViewBuilder
    private var waitingContent: some View {
        if let leg = viewModel.currentTransit {
            // 捷運、臺鐵即使目前是表定，也定期到即時看板找這班車。
            let hasLive = leg.realtime != nil || leg.railRealtime != nil || leg.mode == .tra || leg.mode == .metro
            let refresh: (title: String, action: () -> Void)? = !hasLive
                ? backAction
                : ("更新到站時間", { Task { await viewModel.refreshArrival() } })
            PlanWaitingView(leg: leg, now: viewModel.currentTime, notice: viewModel.notice)
                .bottomAction("我已上車", systemImage: leg.mode.symbolName, secondary: refresh) {
                    viewModel.next()
                }
                .task(id: viewModel.flow.index) {
                    // 有即時資料時每 30 秒更新倒數。
                    while !Task.isCancelled, hasLive {
                        try? await Task.sleep(for: .seconds(30))
                        await viewModel.refreshArrival()
                    }
                }
        }
    }

    @ViewBuilder
    private var ridingContent: some View {
        if let leg = viewModel.currentTransit {
            PlanRidingView(leg: leg, status: viewModel.alightStatus, now: viewModel.currentTime)
                .bottomAction("我已下車", systemImage: "figure.walk") {
                    viewModel.next()
                }
                .task(id: viewModel.flow.index) {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(30))
                        viewModel.tick()
                    }
                }
        }
    }

    private var gpsStatus: WalkGPSStatus {
        if let problem = viewModel.locationProblem { return .unavailable(problem) }
        guard viewModel.isTrackingGPS else { return .manual }
        if viewModel.isOffRoute { return .offRoute }
        if viewModel.isLowAccuracy { return .lowAccuracy }
        return .tracking
    }
}
