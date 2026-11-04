import SwiftUI
import SkyRayCore

/// The Servers box under the chip (3.0.0): the flag and the name of the country this phone leaves from — the choice not yet
/// confirmed, else the box's word; Auto with the globe. Shown once the box offers a second country; red while the chosen one
/// does not answer. A tap opens the sheet. The Android box_server.
struct ServerBox: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let down = model.isConnected && model.exitDown
        Button { model.showServers = true } label: {
            HStack(spacing: 12) {
                Text(model.exitFlag).font(.system(size: 22))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("server.title").uppercased()).font(AppFont.label).foregroundColor(.muted).kerning(0.8)
                    Text(model.exitName.isEmpty ? L("auto") : model.exitName).font(AppFont.font(15, weight: .medium)).foregroundColor(.onSurface).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundColor(.muted)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60)
            .background((down ? Color.pingRed : Color.primaryBlue).opacity(0.14))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke((down ? Color.pingRed : Color.blueLight).opacity(0.45), lineWidth: 1))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }
}

/// The Servers sheet: Auto and every country on offer with its measured latency — measured now through the line in use while
/// connected, else the last figures, greyed —, the chosen one ticked; one button, Connect or Switch. The Android sheet_servers.
struct ServersSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 10) {
                    row(nil)
                    ForEach(model.exits.filter { $0.state != "off" }) { e in row(e) }
                    Button(model.isConnected ? L("server.switch") : L("server.connect")) {
                        let code = selected
                        dismiss()
                        if code != model.exitShown { Task { await model.chooseExit(code) } }
                        else if !model.isConnected { Task { await model.connectTapped() } }
                    }
                    .buttonStyle(EthaPrimaryButtonStyle())
                    .padding(.top, 2)
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
            }
            .background(Color.sheet.ignoresSafeArea())
            .navigationTitle(L("server.pick"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(L("cancel")) { dismiss() } } }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            selected = model.exitShown
            Task { await model.measureExits() }   // real figures, through the line in use (nothing while disconnected)
        }
    }

    private func row(_ e: Exit?) -> some View {
        let code = e?.code ?? ""
        let chosen = code == selected
        let ms = e.flatMap { model.exitMeasured[$0.code] }
        let text: String = {
            guard let e = e else { return "" }
            if !e.ok { return L("server.unavailable") }
            guard let ms = ms else { return model.isConnected ? L("server.measuring") : "" }
            return ms <= 0 ? L("server.unavailable") : "\(ms) ms"
        }()
        return Button { selected = code } label: {
            HStack(spacing: 12) {
                Text(e.map { Exits.flag($0.country) } ?? "\u{1F310}").font(.system(size: 22))
                Text(e?.name ?? L("auto")).font(AppFont.font(15, weight: .medium)).foregroundColor(.onSurface).lineLimit(1)
                Spacer(minLength: 8)
                Text(text).font(AppFont.ms).foregroundColor(model.isConnected && (ms ?? 0) > 0 ? .greenLight : .muted)
                if chosen { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundColor(.blueLight) }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
            .background(chosen ? Color.primaryBlue.opacity(0.14) : Color.panel)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(chosen ? Color.blueLight.opacity(0.45) : Color.edge, lineWidth: 1))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}
