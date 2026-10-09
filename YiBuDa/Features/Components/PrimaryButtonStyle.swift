import SwiftUI

/// 底部主要動作：藍底白字、高度至少 60 pt、大圓角。
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.bold())
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: Theme.minimumButtonHeight)
            .padding(.horizontal, Theme.spacing)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// 次要動作：灰底、不搶主要按鈕的注意力。
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: Theme.minimumButtonHeight)
            .padding(.horizontal, Theme.spacing)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
