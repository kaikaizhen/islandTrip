import SwiftUI

/// 步行時 GPS 的狀態，決定畫面上的提示。
enum WalkGPSStatus: Equatable {
    /// 沒有 GPS（模擬位置或模擬步行段）：完全手動。
    case manual
    case tracking
    case lowAccuracy
    case offRoute
    case unavailable(String)
}

/// 步行（草圖 B）：上方一個超大箭頭、中央一句現在指令、下方下一步與安全提示。
struct WalkingStepView: View {
    let instruction: NavigationInstruction
    let progress: String?
    let nextStep: String?
    var liveRemainingMeters: Int?
    var gpsStatus: WalkGPSStatus = .manual
    var isRerouting = false
    var onReroute: (() -> Void)?
    var onRelocate: (() -> Void)?
    var turnAdvice: TurnSideAdvice = .none
    var onSelectSide: ((WalkSide?) -> Void)?

    @ScaledMetric(relativeTo: .largeTitle) private var arrowSize: CGFloat = 120

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                if gpsStatus == .offRoute {
                    offRouteBanner
                }

                VStack(spacing: Theme.spacing) {
                    HStack {
                        if let progress {
                            Text(progress)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        gpsBadge
                    }
                    ManeuverArrow(maneuver: instruction.kind, size: arrowSize)
                        .padding(.vertical, Theme.spacing)
                    if let liveRemainingMeters {
                        Text("還有 \(WalkInstructionBuilder.spoken(liveRemainingMeters))")
                            .font(.system(.largeTitle, design: .rounded).bold())
                            .foregroundStyle(Theme.accent)
                            .accessibilityIdentifier("liveRemaining")
                    }
                    Text(instruction.displayText)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("currentInstruction")
                    if let detail = instruction.detailText {
                        Text(detail)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let safetyNote = instruction.safetyNote {
                        SafetyNote(text: safetyNote)
                    }
                }
                .frame(maxWidth: .infinity)
                .card()
                .accessibilityElement(children: .combine)

                if let onSelectSide {
                    WalkingSideCard(advice: turnAdvice, onSelect: onSelectSide)
                }

                if let nextStep {
                    NextStepCard(text: nextStep)
                }

                statusNote
                #if DEBUG
                uiTestTarget
                #endif
            }
            .padding(Theme.spacing)
        }
    }

    @ViewBuilder
    private var gpsBadge: some View {
        switch gpsStatus {
        case .tracking, .offRoute:
            Label("GPS 導航中", systemImage: "location.fill")
                .font(.footnote.bold())
                .foregroundStyle(Theme.accent)
        case .lowAccuracy:
            Label("定位不準", systemImage: "location.slash")
                .font(.footnote.bold())
                .foregroundStyle(.secondary)
        case .manual, .unavailable:
            Label("手動", systemImage: "hand.tap")
                .font(.footnote.bold())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusNote: some View {
        switch gpsStatus {
        case .lowAccuracy:
            SafetyNote(text: "定位不夠準，請依指示走，到了路口再按「下一步」。")
                .card()
        case .unavailable(let message):
            SafetyNote(text: message)
                .card()
        case .tracking:
            if let onRelocate {
                Button(action: onRelocate) {
                    Label("步驟不對？依目前位置重新定位", systemImage: "scope")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("relocate")
            }
        case .manual, .offRoute:
            EmptyView()
        }
    }

    private var offRouteBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            SafetyNote(text: "好像走錯路了。先停下來，確認周圍是否安全。")
            if let onReroute {
                Button(action: onReroute) {
                    if isRerouting {
                        ProgressView("正在重新規劃…")
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("從這裡重新規劃路線", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.primary)
                .disabled(isRerouting)
                .accessibilityIdentifier("reroute")
            }
        }
        .card()
    }

    #if DEBUG
    /// 只在 UI 測試（啟動參數 -uiTestExposeTarget）時，提供這一步的目標座標讓測試模擬走路；VoiceOver 不會讀到。
    @ViewBuilder
    private var uiTestTarget: some View {
        if ProcessInfo.processInfo.arguments.contains("-uiTestExposeTarget"), let target = instruction.targetCoordinate {
            Text("\(target.latitude),\(target.longitude)")
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("uiTestTarget")
        }
    }
    #endif
}
