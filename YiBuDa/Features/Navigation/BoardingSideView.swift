import SwiftUI

/// 確認上車側（草圖 C）：簡化的道路兩側示意，標出你在這裡、正確站牌與搭乘方向。
/// 依序採用：使用者的回答 → 穩定的 GPS 判斷 → 站牌資料；都沒有就問使用者，不硬猜。
struct BoardingSideView: View {
    let bus: BusLeg
    let details: StopDetails?
    let resolution: BoardingSideResolution
    let onAnswer: (BoardingSideAnswer?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(headline)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("搭 \(bus.option.routeName)　\(bus.option.direction)")
                        .font(.title2.weight(.semibold))
                }
                .accessibilityElement(children: .combine)

                switch resolution {
                case .known(let needsToCross, let source):
                    RoadSideDiagram(correctStop: bus.boardingStop, oppositeStop: details?.oppositeStop,
                                    direction: bus.option.direction, needsToCross: needsToCross)
                    VStack(alignment: .leading, spacing: 8) {
                        SafetyNote(text: guidance(needsToCross: needsToCross, source: source))
                        Label(sourceText(source), systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if source != .stopData {
                            Button("不對？重新回答") { onAnswer(nil) }
                                .font(.headline)
                                .frame(minHeight: 44)
                        }
                    }
                    .card()
                case .ask(let reason):
                    question(reason: reason)
                case .cannotTell:
                    signGuide
                }
            }
            .padding(Theme.spacing)
        }
    }

    private var headline: String {
        switch resolution {
        case .known(needsToCross: true, _): "請到對面站牌搭車"
        case .known(needsToCross: false, _): "就在這一側搭車"
        default: "確認站牌方向"
        }
    }

    private func guidance(needsToCross: Bool, source: BoardingSideResolution.Source) -> String {
        if source == .stopData, case .confirmed(_, let text) = details?.side { return text }
        return needsToCross
            ? "請到路口或斑馬線過馬路，再到對面站牌搭車。不要直接穿越車道。"
            : "站牌在你這一側，確認站牌上有「\(bus.option.routeName)」就可以等車。"
    }

    private func sourceText(_ source: BoardingSideResolution.Source) -> String {
        switch source {
        case .gps(let accuracy): "依 GPS 判斷（誤差約 \(accuracy) 公尺）"
        case .manual: "依你的回答"
        case .stopData: "依站牌資料"
        }
    }

    /// 問使用者看得到的事：旁邊這一側的站牌寫哪個方向。
    private func question(reason: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let reason {
                Label(reason, systemImage: "location.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("你旁邊這一側的站牌，寫的是哪個方向？")
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            Button { onAnswer(.nearbyIsCorrect) } label: {
                Text(bus.boardingStop.directionDescription)
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("answer-correct")
            Button { onAnswer(.nearbyIsOpposite) } label: {
                Text(details?.oppositeStop?.directionDescription ?? "別的方向")
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("answer-opposite")
            Button { onAnswer(.cannotSeeSign) } label: {
                Text("看不到站牌")
            }
            .buttonStyle(.secondary)
        }
        .card()
    }

    private var signGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            SafetyNote(text: "無法確認站牌在馬路哪一側，請找到站牌，查看站名與行駛方向。")
            Divider()
            Label("\(bus.boardingStop.name)", systemImage: "signpost.right.fill")
                .font(.title.bold())
            Text(bus.boardingStop.directionDescription)
                .font(.title2)
            Text("站牌上要有「\(bus.option.routeName)」，方向是「\(bus.option.direction)」才對。")
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            Button("看到站牌了，重新回答") { onAnswer(nil) }
                .font(.headline)
                .frame(minHeight: 44)
        }
        .card()
    }
}

/// 道路兩側示意圖。只表示「哪一側」，不代表真實車道數或斑馬線位置。
struct RoadSideDiagram: View {
    let correctStop: Stop
    let oppositeStop: Stop?
    let direction: String
    let needsToCross: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 遠側
            sidewalk {
                if needsToCross {
                    stopChip(correctStop, isCorrect: true)
                } else if let oppositeStop {
                    stopChip(oppositeStop, isCorrect: false)
                }
            }
            road
            // 近側（你在這裡）
            sidewalk {
                HStack {
                    Label("你在這裡", systemImage: "figure.stand")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.background, in: Capsule())
                    Spacer(minLength: 8)
                    if !needsToCross {
                        stopChip(correctStop, isCorrect: true)
                    } else if let oppositeStop {
                        stopChip(oppositeStop, isCorrect: false)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var road: some View {
        ZStack {
            Color(white: 0.28)
            VStack(spacing: 0) {
                Spacer()
                HStack(spacing: 14) {
                    ForEach(0..<8, id: \.self) { _ in
                        Capsule().fill(.white.opacity(0.8)).frame(width: 22, height: 4)
                    }
                }
                Spacer()
            }
            if needsToCross {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 36, weight: .bold))
                    Text("走行人穿越道過馬路")
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .padding(10)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.vertical, 16)
            }
        }
        // 用最小高度而非固定高度，字體放大時道路會跟著變高，文字不被裁切。
        .frame(minHeight: 140)
    }

    private func sidewalk(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(Color(.systemGray5))
    }

    private func stopChip(_ stop: Stop, isCorrect: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(isCorrect ? "正確站牌" : "不是這個", systemImage: isCorrect ? "checkmark.circle.fill" : "xmark.circle")
                .font(.headline)
            Text("\(stop.name)・\(stop.directionDescription)")
                .font(.subheadline)
        }
        .padding(10)
        .foregroundStyle(isCorrect ? Color.white : Color.secondary)
        .background(isCorrect ? Theme.accent : Color(.systemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var accessibilityText: String {
        needsToCross
            ? "正確站牌在馬路對面，\(correctStop.name)\(correctStop.directionDescription)。請走行人穿越道過馬路。"
            : "正確站牌在你這一側，\(correctStop.name)\(correctStop.directionDescription)。"
    }
}
