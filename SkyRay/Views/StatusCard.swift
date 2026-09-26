import SwiftUI

/// The round Connect button, the state, the line and its latency, the server menu.
struct StatusCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Card {
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    ConnectButton()
                    Text(model.stateText).font(AppFont.headline)
                    Text(L(model.isConnected ? "tap.disconnect" : "tap.connect")).font(AppFont.small).foregroundColor(.muted)
                    if model.isConnected, let line = model.tunnel?.lineName ?? model.currentLine?.displayName {
                        Text(L("line", line) + latency).font(AppFont.small).foregroundColor(.muted)
                    }
                    if model.busy { ProgressView().padding(.top, 2) }
                }
                Spacer()
            }
            Divider()
            HStack {
                Menu {
                    ForEach(Array(model.serverRows.enumerated()), id: \.offset) { _, row in
                        Button(row.text) { Task { await model.pick(lineId: row.id) } }
                    }
                } label: {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text(model.serverLabel).font(AppFont.body).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption)
                    }
                    .padding(12)
                    .background(Color.surfaceVariant)
                    .cornerRadius(12)
                }
                .disabled(model.busy)
                Button(L("test.again")) { Task { await model.testAgain() } }
                    .font(AppFont.small)
                    .disabled(model.busy)
            }
        }
    }

    private var latency: String {
        guard let ms = model.tunnel?.lastProbeMs, ms > 0 else { return "" }
        return " · \(ms) ms"
    }
}

struct ConnectButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button { Task { await model.connectTapped() } } label: {
            ZStack {
                Circle().fill(model.isConnected ? Color.connectOn : Color.primaryBlue).frame(width: 120, height: 120)
                Image(systemName: "power").font(.system(size: 44, weight: .semibold)).foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
        .opacity(model.busy ? 0.6 : 1)
        .accessibilityLabel(Text(L(model.isConnected ? "disconnect" : "connect")))
    }
}
