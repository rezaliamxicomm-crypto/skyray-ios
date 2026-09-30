import SwiftUI

/// The Android buttons: 50 pt tall, 14 pt corners, 15 pt Vazirmatn.
struct EthaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.button)
            .foregroundColor(.onPrimary)
            .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
            .background(Color.primaryBlue)
            .cornerRadius(14)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .modifier(DimWhenDisabled())
    }
}

/// EthaOutlinedButton: text in the surface colour, the panel edge as its outline.
struct EthaOutlinedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.button)
            .foregroundColor(.onSurface)
            .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.edge, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .modifier(DimWhenDisabled())
    }
}

/// EthaLinkButton: small bold blue text (Ping all, Show all).
struct EthaTextButtonStyle: ButtonStyle {
    var font: Font = AppFont.link
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundColor(.blueLight)
            .padding(.horizontal, 8)
            .frame(minHeight: 36)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .modifier(DimWhenDisabled())
    }
}

/// EthaPill: the 32 pt round Refresh pill on the panel colour with the edge as its outline.
struct EthaPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.link)
            .foregroundColor(.onSurface)
            .padding(.leading, 12).padding(.trailing, 14)
            .frame(height: 32)
            .background(Color.panel)
            .overlay(Capsule().stroke(Color.edge, lineWidth: 1))
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .modifier(DimWhenDisabled())
    }
}

struct DimWhenDisabled: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    func body(content: Content) -> some View { content.opacity(isEnabled ? 1 : 0.45) }
}

/// bg_panel: the translucent panel with a 1 pt edge and 18 pt corners.
struct Panel<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
    let content: Content
    init(padding: EdgeInsets = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14), @ViewBuilder content: () -> Content) {
        self.padding = padding; self.content = content()
    }
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.panel)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.edge, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
