import SwiftUI
import SkyRayCore

/// The Android settings screen (res/layout/activity_etha_settings.xml): plain rows on the background — an icon,
/// a 16 pt title, a 13 pt summary. The rows Android has and iOS cannot (apps that bypass the VPN, check for
/// update) are left out; the rest keep their order.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmDelete = false
    @State private var showLogs = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                NavigationLink(destination: ServerListView()) {
                    row("antenna.radiowaves.left.and.right", L("server.pick"), model.serverLabel)
                }
                .disabled(!model.hasSubscription)
                Button { open(UIApplication.openSettingsURLString) } label: {
                    row("globe", L("language"), Locale.current.localizedString(forLanguageCode: appLanguage) ?? L("language.system"))
                }
                Button { showLogs = true } label: { row("doc.text", L("send.logs"), L("send.logs.hint")) }
                Button { share() } label: { row("square.and.arrow.up", L("share.app"), L("share.hint")) }
                NavigationLink(destination: AboutView()) { row("info.circle", L("about"), nil) }
                Button { open(Etha.privacyURL) } label: { row("hand.raised", L("privacy"), nil) }
                Button { confirmDelete = true } label: { row("trash", L("delete.account"), L("delete.hint")) }
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle(L("settings"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(L("delete.account"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("delete.do"), role: .destructive) { Task { await model.deleteAccount() } }
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(L("delete.confirm"))
        }
        .sheet(isPresented: $showLogs) { LogShareSheet(urls: logURLs) }
    }

    private var logURLs: [URL] {
        [model.store.appLogURL, model.store.tunnelLogURL, model.store.xrayLogURL].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// EthaSettingsRow: 16 pt of padding, a 24 pt icon, the text 16 pt further in.
    private func row(_ icon: String, _ title: String, _ subtitle: String?) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .frame(width: 24, height: 24)
                .foregroundColor(.muted)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(AppFont.row).foregroundColor(.onSurface)
                if let s = subtitle, !s.isEmpty { Text(s).font(AppFont.small).foregroundColor(.muted) }
            }
            .padding(.leading, 16)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The system share sheet with the two stores and the bot: a friend picks their platform.
    private func share() {
        let text = L("share.text", Etha.playURL, Etha.appStoreURL, Etha.shareURL)
        let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        sheet.popoverPresentationController?.sourceView = top.view   // iPad anchors the sheet
        sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        top.present(sheet, animated: true)
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { UIApplication.shared.open(url) }
    }
}

/// Android's ServerPicker dialog: Auto (fastest) first, then every line with its ping, and Test again.
struct ServerListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(model.serverRows.enumerated()), id: \.offset) { _, row in
                    Button {
                        Task { await model.pick(lineId: row.id) }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: isCurrent(row) ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 20)).foregroundColor(isCurrent(row) ? .primaryBlue : .muted)
                            Text(row.text).font(AppFont.row).foregroundColor(.onSurface)
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                }
                Button(L("test.again")) { Task { await model.testAgain() } }
                    .buttonStyle(EthaTextButtonStyle())
                    .disabled(model.busy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle(L("server.pick"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isCurrent(_ row: ServerRows.Row) -> Bool {
        if row.id == nil { return !model.selection.pinned }
        return model.selection.pinned && row.id == model.selection.selectedLineId
    }
}
