import SwiftUI

/// 狀態或警告提示。以圖示 + 文字表達，不只依賴顏色區分。
struct NoticeBanner: View {
    let notice: CapabilityTestViewModel.Notice

    var body: some View {
        Label {
            Text(notice.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: notice.kind == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(notice.kind == .warning ? Color.primary : Theme.accent)
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(notice.kind == .warning ? "注意：\(notice.text)" : notice.text)
        .accessibilityIdentifier("noticeBanner")
    }
}
