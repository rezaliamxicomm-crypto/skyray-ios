import SwiftUI
import SkyRayCore

/// The hero: a 150 pt Connect disc inside a halo that breathes while connected, the state in 22 pt bold, the hint
/// (or, connected, the chip with the server and its probe) — Android's `hero`.
struct HeroView: View {
    @EnvironmentObject private var model: AppModel
    @State private var breathing = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [(model.isConnected ? Color.connectOn : Color.primaryBlue).opacity(model.isConnected ? 0.48 : 0.40),
                                                  (model.isConnected ? Color.connectOn : Color.primaryBlue).opacity(0.22), .clear],
                                         center: .center, startRadius: 40, endRadius: 102))
                    .frame(width: 204, height: 204)
                    .scaleEffect(breathing ? 1.12 : 1)
                    .opacity(breathing ? 1 : 0.85)
                ConnectButton()
            }
            .frame(width: 204, height: 204)
            Text(model.stateText)
                .font(AppFont.headline).foregroundColor(.onSurface)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
            if model.isConnected, let chip = chipText {
                HStack(spacing: 6) {
                    Circle().fill(Color.greenLight).frame(width: 8, height: 8)
                    Text(chip).font(AppFont.chip).foregroundColor(.greenLight)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.connectOn.opacity(0.12))
                .overlay(Capsule().stroke(Color.connectOn.opacity(0.25), lineWidth: 1))
                .clipShape(Capsule())
                .padding(.top, 8)
            } else if !model.isConnected {
                Text(model.selection.pinned ? L("tap.connect") : L("tap.connect") + "\n" + L("auto.hint"))
                    .font(AppFont.hint).foregroundColor(.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 4)
            }
            if model.busy {
                ProgressView().tint(.blueLight).frame(height: 24).padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .onAppear { breathe(model.isConnected) }
        .onChange(of: model.isConnected) { breathe($0) }
    }

    private func breathe(_ on: Bool) {
        if on {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { breathing = true }
        } else {
            withAnimation(.easeOut(duration: 0.3)) { breathing = false }
        }
    }

    /// "CleanIP3 · XHTTP/443 · 412 ms": the probe's number, else the last test's — Android's chipText.
    private var chipText: String? {
        guard let line = model.currentLine else { return nil }
        let name = model.tunnel?.lineName.map { LineName.display($0) } ?? line.displayName
        let ms = (model.tunnel?.lastProbeMs).flatMap { $0 > 0 ? $0 : nil } ?? model.selection.delay(of: line.id)
        return ms > 0 ? "\(name) · \(ms) ms" : name
    }
}

/// The round Connect button: 150 pt, blue, green once connected, Material's power glyph.
struct ConnectButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button { Task { await model.connectTapped() } } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: model.isConnected ? [.greenLight, .connectOn] : [.blueLight, .primaryBlue],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 150, height: 150)
                    .shadow(color: (model.isConnected ? Color.connectOn : Color.primaryBlue).opacity(0.55), radius: 18, y: 12)
                PowerIcon().fill(Color.white).frame(width: 58, height: 58)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
        .opacity(model.busy ? 0.6 : 1)
        .accessibilityLabel(Text(L(model.isConnected ? "disconnect" : "connect")))
    }
}

/// The server panel: SERVER and Ping all above, the value (Auto → the line, or the pinned line), its ping and a
/// chevron below; the whole panel opens the sheet — Android's `panel_server`.
struct ServerPanel: View {
    @EnvironmentObject private var model: AppModel
    let open: () -> Void

    var body: some View {
        Panel(padding: EdgeInsets(top: 6, leading: 16, bottom: 12, trailing: 8)) {
            VStack(spacing: 0) {
                HStack {
                    Text(L("server").uppercased()).font(AppFont.label).foregroundColor(.muted).kerning(0.8)
                    Spacer(minLength: 0)
                    Button(L("test.again")) { Task { await model.testAgain() } }
                        .buttonStyle(EthaTextButtonStyle())
                        .disabled(model.busy)
                }
                HStack(spacing: 8) {
                    Text(model.panelValue).font(AppFont.value).foregroundColor(.onSurface).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    if model.panelDelay > 0 {
                        Text("\(model.panelDelay) ms").font(AppFont.chip).foregroundColor(Color.ping(model.panelDelay))
                    }
                    Image(systemName: "chevron.forward").font(.system(size: 13, weight: .semibold)).foregroundColor(.muted)
                        .padding(.trailing, 4)
                }
                .padding(.trailing, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { open() }
    }
}

/// The server sheet: Auto on top as the highlighted card with the server it uses now, the five fastest servers
/// with a coloured ping dot, Show all N, Ping all in the header — Android's ServerSheet.
struct ServerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var expanded = false
    private let shownFirst = 5

    var body: some View {
        let candidates = model.sortedCandidates
        let shown = expanded ? candidates : Array(candidates.prefix(shownFirst))
        VStack(spacing: 10) {
            Capsule().fill(Color.white.opacity(0.22)).frame(width: 38, height: 4).padding(.top, 10)
            HStack {
                Text(L("server")).font(AppFont.sheetTitle).foregroundColor(.onSurface)
                Spacer(minLength: 0)
                Button(L("test.again")) { Task { await model.testAgain() } }
                    .buttonStyle(EthaTextButtonStyle())
                    .disabled(model.busy)
            }
            Button { dismiss(); Task { await model.pick(lineId: nil) } } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("auto")).font(AppFont.value).foregroundColor(.onSurface)
                        Text(model.autoNowText).font(AppFont.chip).foregroundColor(.muted)
                    }
                    Spacer(minLength: 0)
                    if !model.selection.pinned {
                        ZStack {
                            Circle().fill(Color.primaryBlue).frame(width: 22, height: 22)
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.primaryBlue.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.blueLight.opacity(0.45), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            HStack {
                Text(L("fastest").uppercased()).font(AppFont.label).foregroundColor(.muted).kerning(0.8)
                Spacer(minLength: 0)
                Text(L("servers.count", Int64(candidates.count))).font(AppFont.label).foregroundColor(.muted).kerning(0.8)
            }
            .padding(.top, 2)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(shown, id: \.id) { c in
                        Button { dismiss(); Task { await model.pick(lineId: c.id) } } label: {
                            HStack(spacing: 10) {
                                Circle().fill(Color.ping(c.delayMs)).frame(width: 8, height: 8)
                                Text(model.name(of: c.id)).font(AppFont.value).foregroundColor(.onSurface).lineLimit(1)
                                Spacer(minLength: 0)
                                Text(pingText(c.delayMs)).font(AppFont.ms).foregroundColor(.onSurface)
                                if model.selection.pinned, model.selection.selectedLineId == c.id {
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(.blueLight)
                                }
                            }
                            .padding(.horizontal, 4)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Color.white.opacity(0.06))
                    }
                    if candidates.count > shownFirst {
                        Button(expanded ? L("show.fewer") : L("show.all", Int64(candidates.count))) { withAnimation { expanded.toggle() } }
                            .buttonStyle(EthaTextButtonStyle(font: AppFont.textButton))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.sheet.ignoresSafeArea())
        .modifier(SheetDetents())
    }

    private func pingText(_ ms: Int64) -> String {
        if ms > 0 { return "\(ms) ms" }
        return ms < 0 ? L("ping.failed") : L("ping.untested")
    }
}

/// Half height first, full on drag (iOS 16); iOS 15 shows the standard card.
struct SheetDetents: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.presentationDetents([.medium, .large]).presentationDragIndicator(.hidden)
        } else {
            content
        }
    }
}
