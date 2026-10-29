import SwiftUI
import SkyRayCore

/// The hero: a 150 pt Connect disc inside a halo that breathes while connected, the state in 22 pt bold, one line
/// under it — the hint, connected the chip with the line in use's time, busy the spinner — then the two buttons,
/// "Test latency" and "Refresh", and a line for what the last test did — Android's `hero` (2.0.0). No line is named.
/// It takes the height the phone has to spare (HomeView): the block sits in the middle of it and the disc with its
/// halo grows with it, up to 12 % at 160 pt to spare (168 pt, the design's tall-phone hero). The line under the
/// state lives in a slot as tall as the hint's two lines whatever it shows, so the block's height never changes and
/// the Connect button never moves under the finger. Three states while the tunnel is up: Connected (green), Searching
/// for a line (amber disc, red chip, what to do), Testing.
struct HeroView: View {
    @EnvironmentObject private var model: AppModel
    @State private var breathing = false
    @State private var spare: CGFloat = 0   // the height left over on this phone, all of it the hero's

    private var grow: CGFloat { 1 + 0.12 * min(1, max(0, spare) / 160) }
    private var discColor: Color {
        if model.isConnected { return model.searching ? .amber : .connectOn }
        return .primaryBlue
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [discColor.opacity(model.isConnected ? 0.48 : 0.40), discColor.opacity(0.22), .clear],
                                         center: .center, startRadius: 40, endRadius: 102))
                    .frame(width: 204, height: 204)
                    .scaleEffect(breathing ? 1.12 : 1)
                    .opacity(breathing ? 1 : 0.85)
                ConnectButton()
            }
            .frame(width: 204, height: 204)
            .scaleEffect(grow)   // drawn larger, laid out the same: the halo's clear rim is what reaches past the box
            Text(model.stateText)
                .font(AppFont.headline).foregroundColor(.onSurface)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
            ZStack(alignment: .top) {
                Text("0\n0").font(AppFont.hint).lineSpacing(4).padding(.top, 4).hidden()   // the slot: the hint's two lines
                if model.busy {
                    ProgressView().tint(.blueLight).frame(height: 24).padding(.top, 8)
                } else if model.isConnected {
                    if let chip = chip {
                        HStack(spacing: 6) {
                            Circle().fill(chip.red ? Color.pingRed : Color.greenLight).frame(width: 8, height: 8)
                            Text(chip.text).font(AppFont.chip).foregroundColor(chip.red ? .pingRed : .greenLight).lineLimit(1)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background((chip.red ? Color.pingRed : Color.connectOn).opacity(0.12))
                        .overlay(Capsule().stroke((chip.red ? Color.pingRed : Color.connectOn).opacity(0.3), lineWidth: 1))
                        .clipShape(Capsule())
                        .padding(.top, 8)
                    }
                } else {
                    Text(L("tap.connect") + "\n" + L("auto.hint"))
                        .font(AppFont.hint).foregroundColor(.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.top, 4)
                }
            }
            HStack(spacing: 10) {
                Button(model.testing ? L("testing") : L("test.latency")) { Task { await model.testLatency() } }
                    .buttonStyle(EthaOutlinedButtonStyle())
                    .disabled(model.testing || model.busy)
                Button { Task { await model.refreshNow() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold))
                        Text(L("refresh"))
                    }
                }
                .buttonStyle(EthaOutlinedButtonStyle())
                .disabled(model.refreshing || model.testing || model.busy)
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            Text(model.outcomeText ?? " ")
                .font(AppFont.hint).foregroundColor(.onSurface)
                .multilineTextAlignment(.center)
                .opacity(model.outcomeText == nil ? 0 : 1)   // invisible, never gone: the block keeps its height
                .padding(.top, 10)
        }
        // the block is centred in the hero's height: twice its distance from the top is what the phone has to spare
        .background(GeometryReader { g in Color.clear.preference(key: SpareHeight.self, value: 2 * g.frame(in: .named("hero")).minY) })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "hero")
        .padding(.top, 18)
        .padding(.bottom, 14)
        .onPreferenceChange(SpareHeight.self) { spare = $0.rounded() }
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

    /// The chip under the state while connected: the line in use's time and its age — never its name.
    private var chip: (text: String, red: Bool)? {
        if model.testing { return (L("testing"), false) }
        if model.searching { return (L("no.line.answers") + " · " + model.ago(model.latencyAt), true) }
        if model.latencyMs > 0 { return ("\(model.latencyMs) ms · " + model.ago(model.latencyAt), false) }
        return nil
    }
}

private struct SpareHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The round Connect button: 150 pt, blue, green once connected, amber while no line answers, Material's power glyph.
struct ConnectButton: View {
    @EnvironmentObject private var model: AppModel

    private var colors: [Color] {
        if model.isConnected { return model.searching ? [.amber, .amber] : [.greenLight, .connectOn] }
        return [.blueLight, .primaryBlue]
    }

    var body: some View {
        Button { Task { await model.connectTapped() } } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 150, height: 150)
                    .shadow(color: colors[1].opacity(0.55), radius: 18, y: 12)
                PowerIcon().fill(Color.white).frame(width: 58, height: 58)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
        .opacity(model.busy ? 0.6 : 1)
        .accessibilityLabel(Text(L(model.isConnected ? "disconnect" : "connect")))
    }
}
