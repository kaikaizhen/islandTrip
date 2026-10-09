import SwiftUI

/// 導航全螢幕：依目前階段顯示對應畫面，每個畫面只有一個主要按鈕。
struct NavigationSessionView: View {
    @Bindable var viewModel: NavigationSessionViewModel
    let onFinish: () -> Void

    @State private var confirmsCancel = false

    var body: some View {
        NavigationStack {
            content
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
        .task { await viewModel.start() }
        .onChange(of: viewModel.isFinished) { _, finished in
            if finished { onFinish() }
        }
    }

    private var title: String {
        switch viewModel.phase {
        case .idle: ""
        case .walkingToStop: "走到站牌"
        case .checkingBoardingSide: "確認上車側"
        case .waitingAtStop: "候車"
        case .onVehicle: "搭乘中"
        case .walkingToDestination: "走到目的地"
        case .arrived: "到達"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            ProgressView()
        case .walkingToStop, .walkingToDestination:
            walkingContent
        case .checkingBoardingSide:
            boardingSideContent
        case .waitingAtStop:
            waitingContent
        case .onVehicle(let approaching):
            onVehicleContent(isApproaching: approaching)
        case .arrived:
            arrivedContent
        }
    }

    private var backAction: (title: String, action: () -> Void)? {
        guard viewModel.canGoBack else { return nil }
        return ("回上一步", { viewModel.previousStep() })
    }

    @ViewBuilder
    private var walkingContent: some View {
        if let instruction = viewModel.currentInstruction {
            WalkingStepView(instruction: instruction, progress: viewModel.stepProgress, nextStep: viewModel.nextStepText)
                .bottomAction(viewModel.walkingPrimaryTitle, systemImage: "arrow.right", secondary: backAction) {
                    viewModel.nextStep()
                }
        }
    }

    @ViewBuilder
    private var boardingSideContent: some View {
        if let bus = viewModel.bus {
            BoardingSideView(bus: bus, details: viewModel.stopDetails)
                .bottomAction("我在正確的站牌了", systemImage: "checkmark", secondary: backAction) {
                    Task { await viewModel.confirmBoardingSide() }
                }
        }
    }

    @ViewBuilder
    private var waitingContent: some View {
        if let bus = viewModel.bus {
            let refresh: (title: String, action: () -> Void) = ("更新到站時間", { Task { await viewModel.refreshArrivals() } })
            WaitingView(bus: bus, options: viewModel.waitingOptions, selectedID: viewModel.selectedWaitingID,
                        now: viewModel.currentTime, notice: viewModel.notice) { option in
                viewModel.selectWaitingOption(option)
            }
            .bottomAction(boardTitle, systemImage: "bus.fill", secondary: refresh) {
                viewModel.board()
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    viewModel.rerankWaitingOptions()
                }
            }
        }
    }

    @ViewBuilder
    private func onVehicleContent(isApproaching: Bool) -> some View {
        if let bus = viewModel.bus {
            let simulate: (title: String, action: () -> Void)? =
                isApproaching ? nil : ("模擬：前進一站", { viewModel.simulateNextStop() })
            OnVehicleView(bus: bus, remainingStops: viewModel.remainingStops, isApproaching: isApproaching)
                .bottomAction("我已下車", systemImage: "figure.walk", secondary: simulate) {
                    viewModel.alighted()
                }
        }
    }

    private var arrivedContent: some View {
        ArrivedView(destinationName: viewModel.journey.destination.name)
            .bottomAction("結束導航", systemImage: "flag.checkered") {
                viewModel.cancel()
            }
    }

    private var boardTitle: String {
        let route = viewModel.waitingOptions.first { $0.id == viewModel.selectedWaitingID }?.option?.routeName
        return route.map { "我已上車（\($0)）" } ?? "我已上車"
    }
}
