import SwiftUI
import SkyRayCore

/// The connection card as on Android: the 156 pt Connect button, the state in 22 pt bold, the hint, the line and
/// its delay, a spinner while busy, then the server field with Test again beside it.
struct StatusCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Card(topPadding: 28) {
            VStack(spacing: 0) {
                ConnectButton()
                Text(model.stateText)
                    .font(AppFont.headline).foregroundColor(.onSurface)
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)
                Text(L(model.isConnected ? "tap.disconnect" : "tap.connect"))
                    .font(AppFont.muted).foregroundColor(.muted)
                    .multilineTextAlignment(.center)
                if !lineText.isEmpty {
                    Text(lineText)
                        .font(AppFont.muted).foregroundColor(.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                if model.busy {
                    ProgressView().scaleEffect(1.4).frame(height: 28).padding(.top, 8)
                }
                HStack(alignment: .center, spacing: 4) {
                    ServerField()
                    Button(L("test.again")) { Task { await model.testAgain() } }
                        .buttonStyle(EthaTextButtonStyle(font: AppFont.textButton))
                        .disabled(model.busy)
                }
                .padding(.top, 18)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// "Server: <line>" while connected, the last measured delay on the next line — Android's lineText.
    private var lineText: String {
        guard model.isConnected, let name = model.tunnel?.lineName ?? model.currentLine?.displayName else { return "" }
        var text = L("line", name)
        if let ms = model.tunnel?.lastProbeMs, ms > 0 { text += "\n\(ms) ms" }
        return text
    }
}

/// The round Connect button: 156 pt, the primary colour, green (colorPing) once connected, Material's power glyph.
struct ConnectButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button { Task { await model.connectTapped() } } label: {
            ZStack {
                Circle().fill(model.isConnected ? Color.connectOn : Color.primaryBlue).frame(width: 156, height: 156)
                PowerIcon().fill(Color.white).frame(width: 60, height: 60)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
        .opacity(model.busy ? 0.5 : 1)
        .accessibilityLabel(Text(L(model.isConnected ? "disconnect" : "connect")))
    }
}

/// Material's outlined exposed-dropdown field: a 14 pt-cornered outline, the floating label "Choose a server",
/// the current choice and a dropdown arrow; the menu lists Auto, then every line fastest first with its ping.
struct ServerField: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Menu {
            ForEach(Array(model.serverRows.enumerated()), id: \.offset) { _, row in
                Button(row.text) { Task { await model.pick(lineId: row.id) } }
            }
        } label: {
            ZStack(alignment: .topLeading) {
                HStack(spacing: 8) {
                    Text(model.serverLabel)
                        .font(AppFont.field).foregroundColor(.onSurface)
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 10)).foregroundColor(.muted)
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.outline, lineWidth: 1))
                Text(L("server.pick"))
                    .font(AppFont.floating).foregroundColor(.muted)
                    .padding(.horizontal, 4)
                    .background(Color.surface)
                    .padding(.leading, 12)
                    .offset(y: -8)
            }
        }
        .frame(maxWidth: .infinity)
        .disabled(model.busy)
    }
}
