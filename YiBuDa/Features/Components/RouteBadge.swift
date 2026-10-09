import SwiftUI

/// 公車圖示 + 路線號。
struct RouteBadge: View {
    let routeName: String
    var size: Font = .largeTitle

    var body: some View {
        Label {
            Text(routeName)
                .font(size.bold())
                .monospacedDigit()
                // 路線號絕不能被拆行（例如 265 變成 26／5）。
                .lineLimit(1)
                .fixedSize()
        } icon: {
            Image(systemName: "bus.fill")
                .foregroundStyle(Theme.accent)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(routeName) 公車")
    }
}

/// 能否趕上：圖示 + 文字，不只靠顏色。
struct CatchStatusLabel: View {
    let status: CatchStatus

    var body: some View {
        let format = TransitFormat.catchStatus(status)
        Label(format.text, systemImage: format.symbol)
            .font(.headline)
            .foregroundStyle(status == .canCatch ? Theme.accent : Color.secondary)
    }
}
