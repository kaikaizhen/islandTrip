import SwiftUI

/// 「下一步」小卡：只放一句話，與「現在」的大卡區隔。
struct NextStepCard: View {
    let text: String
    var systemImage = "arrow.forward.circle"

    var body: some View {
        Label {
            Text(text)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.accent)
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("下一步，\(text)")
    }
}

/// 安全提示：圖示 + 文字。
struct SafetyNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.body.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("注意，\(text)")
    }
}
