import SwiftUI

/// 路口示意圖（D3）：目前這條路（直向）與要轉進去的路，標出你在哪一邊、要去的路角。
/// 只表示相對位置，不代表真實車道數或斑馬線位置；需要過馬路時一律畫在路口。
struct IntersectionDiagram: View {
    let turn: WalkSide
    let userSide: WalkSide

    private var needsCrossing: Bool { userSide != turn }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let road = size.width * 0.28
            let centerX = size.width / 2
            let crossY = size.height * 0.38
            let userX = centerX + (userSide == .left ? -1 : 1) * (road / 2 + 22)
            let targetX = centerX + (turn == .left ? -1 : 1) * (road / 2 + 22)

            ZStack {
                Color(.systemGray5)
                // 目前這條路（直向）
                Rectangle()
                    .fill(Color(white: 0.3))
                    .frame(width: road)
                    .position(x: centerX, y: size.height / 2)
                // 要轉進去的路（往轉彎方向）
                Rectangle()
                    .fill(Color(white: 0.3))
                    .frame(width: size.width / 2, height: road)
                    .position(x: turn == .left ? size.width / 4 : size.width * 3 / 4, y: crossY)

                let walkY = crossY + road / 2 + 14
                if needsCrossing {
                    // 在路口過馬路：斑馬線畫在路口，不在路段中間。
                    crosswalk(width: road, y: walkY, centerX: centerX)
                }

                // 建議的走法：往前到路口 →（需要時）走斑馬線過馬路 → 轉進去。
                Path { path in
                    path.move(to: CGPoint(x: userX, y: size.height * 0.85 - 30))
                    path.addLine(to: CGPoint(x: userX, y: walkY))
                    path.addLine(to: CGPoint(x: turn == .left ? 8 : size.width - 8, y: walkY))
                }
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [2, 10]))
                Image(systemName: turn == .left ? "arrowtriangle.left.fill" : "arrowtriangle.right.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .position(x: turn == .left ? 16 : size.width - 16, y: walkY)

                marker(title: "你", symbol: "figure.stand", filled: false)
                    .position(x: userX, y: size.height * 0.85)
                marker(title: "轉到這邊", symbol: "flag.fill", filled: true)
                    .position(x: targetX + (turn == .left ? -40 : 40), y: walkY + 44)
            }
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func crosswalk(width: CGFloat, y: CGFloat, centerX: CGFloat) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { _ in
                Rectangle().fill(.white).frame(width: 7, height: 22)
            }
        }
        .frame(width: width)
        .position(x: centerX, y: y)
    }

    private func marker(title: String, symbol: String, filled: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.title2.bold())
            Text(title)
                .font(.caption.bold())
                .fixedSize()
        }
        .padding(6)
        .foregroundStyle(filled ? Color.white : Color.primary)
        .background(filled ? Theme.accent : Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var accessibilityText: String {
        needsCrossing
            ? "示意圖：你在馬路\(userSide.title)，要轉往\(turn.title)。請先在路口的斑馬線過到\(turn.title)，再轉彎。"
            : "示意圖：你在馬路\(userSide.title)，到路口直接往\(turn.title)轉。"
    }
}

/// 轉彎前的左右側提示卡：不知道就問、同側說直接轉、對側畫路口示意圖。
struct WalkingSideCard: View {
    let advice: TurnSideAdvice
    let onSelect: (WalkSide?) -> Void

    var body: some View {
        switch advice {
        case .none:
            EmptyView()
        case .askSide(let turn):
            VStack(alignment: .leading, spacing: 12) {
                Text("到路口要\(turn.short)轉。你現在走在馬路的哪一邊？")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.spacing) {
                    sideButton(.left)
                    sideButton(.right)
                }
            }
            .card()
        case .sameSide(let turn):
            VStack(alignment: .leading, spacing: 8) {
                Label("你在\(turn.title)，到路口直接\(turn.short)轉", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                changeButton
            }
            .card()
        case .crossFirst(let turn):
            VStack(alignment: .leading, spacing: 12) {
                SafetyNote(text: "先在路口的斑馬線過到\(turn.title)，再\(turn.short)轉。不要直接穿越車道。")
                IntersectionDiagram(turn: turn, userSide: turn == .left ? .right : .left)
                Text("示意圖，實際請依路口號誌與斑馬線。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                changeButton
            }
            .card()
        }
    }

    private func sideButton(_ side: WalkSide) -> some View {
        Button {
            onSelect(side)
        } label: {
            Label(side.title, systemImage: side == .left ? "arrow.left.circle.fill" : "arrow.right.circle.fill")
        }
        .buttonStyle(.secondary)
        .accessibilityIdentifier("side-\(side == .left ? "left" : "right")")
    }

    private var changeButton: some View {
        Button("不對？重新選擇我在哪一邊") { onSelect(nil) }
            .font(.headline)
            .frame(minHeight: 44)
            .accessibilityIdentifier("resetSide")
    }
}
