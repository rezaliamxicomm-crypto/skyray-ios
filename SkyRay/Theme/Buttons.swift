import SwiftUI

/// Material 3 buttons as the Android app styles them: 52 pt tall, 14 pt corners, 15 pt Vazirmatn.
struct EthaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.button)
            .foregroundColor(.onPrimary)
            .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
            .background(Color.primaryBlue)
            .cornerRadius(14)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .modifier(DimWhenDisabled())
    }
}

struct EthaOutlinedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.button)
            .foregroundColor(.primaryBlue)
            .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.outline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .modifier(DimWhenDisabled())
    }
}

/// Material's TextButton: primary-coloured text, no frame.
struct EthaTextButtonStyle: ButtonStyle {
    var font: Font = AppFont.button
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundColor(.primaryBlue)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .modifier(DimWhenDisabled())
    }
}

struct DimWhenDisabled: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    func body(content: Content) -> some View { content.opacity(isEnabled ? 1 : 0.45) }
}
