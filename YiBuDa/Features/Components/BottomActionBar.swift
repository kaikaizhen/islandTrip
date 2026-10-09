import SwiftUI

extension View {
    /// 底部只放一個主要按鈕（可選一個次要按鈕），統一位置與無障礙識別碼。
    func bottomAction(
        _ title: String,
        systemImage: String? = nil,
        isEnabled: Bool = true,
        isVisible: Bool = true,
        secondary: (title: String, action: () -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        safeAreaInset(edge: .bottom) {
            if isVisible {
                VStack(spacing: 10) {
                    if let secondary {
                        Button(secondary.title, action: secondary.action)
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("secondaryAction")
                    }
                    Button(action: action) {
                        if let systemImage {
                            Label(title, systemImage: systemImage)
                        } else {
                            Text(title)
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(!isEnabled)
                    .opacity(isEnabled ? 1 : 0.4)
                    .accessibilityIdentifier("primaryAction")
                }
                .padding(Theme.spacing)
                .background(.bar)
            }
        }
    }
}
