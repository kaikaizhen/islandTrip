import SwiftUI

/// 公車圖示 + 路線號。長路線名（例：「小9(台灣好行-北投竹子湖)」）拆成大字主名＋可換行的小字說明。
struct RouteBadge: View {
    let routeName: String
    var size: Font = .largeTitle

    var body: some View {
        let parts = TransitFormat.routeNameParts(routeName)
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(parts.main)
                    .font(size.bold())
                    .monospacedDigit()
                    // 路線號絕不能被拆行（例如 265 變成 26／5）。
                    .lineLimit(1)
                    .fixedSize()
            } icon: {
                Image(systemName: "bus.fill")
                    .foregroundStyle(Theme.accent)
            }
            if let detail = parts.detail {
                Text(detail)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(routeName) 公車")
    }
}

/// 到站倒數：右側淺灰圓角框，大字分鐘數，一眼就能看到多久來。
struct CountdownBox: View {
    let arrival: Date?
    let now: Date
    var unavailableText: String?
    var isLarge = false

    var body: some View {
        let parts = TransitFormat.countdownParts(arrival, now: now, unavailableText: unavailableText)
        VStack(spacing: 0) {
            Text(parts.value)
                .font(parts.unit == nil ? .headline : (isLarge ? .largeTitle.bold() : .title.bold()))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let unit = parts.unit {
                Text(unit)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .foregroundStyle(arrival == nil ? Color.secondary : Color.primary)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(minWidth: 76, maxWidth: 110)
        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(TransitFormat.busCountdown(arrival, now: now, unavailableText: unavailableText))
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
