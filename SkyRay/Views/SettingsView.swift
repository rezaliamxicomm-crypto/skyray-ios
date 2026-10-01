import SwiftUI
import SkyRayCore

/// The Android settings screen (res/layout/activity_etha_settings.xml): plain rows on the background — an icon,
/// a 16 pt title, a 13 pt summary. The rows Android has and iOS cannot (apps that bypass the VPN, check for
/// update) are left out; the rest keep their order.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmDelete = false
    @State private var showLogs = false
    @State private var showServers = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Button { showServers = true } label: {
                    row("antenna.radiowaves.left.and.right", L("server.pick"), model.serverLabel)
                }
                .disabled(!model.hasSubscription)
                Button { open(UIApplication.openSettingsURLString) } label: {
                    row("globe", L("language"), Locale.current.localizedString(forLanguageCode: appLanguage) ?? L("language.system"))
                }
                Button { showLogs = true } label: { row("doc.text", L("send.logs"), L("send.logs.hint")) }
                Button { share() } label: { row("square.and.arrow.up", L("share.app"), L("share.hint")) }
                Button { rate() } label: { row("star", L("rate.app"), L("rate.hint")) }
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
        .sheet(isPresented: $showServers) { ServerSheet().environmentObject(model) }
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

    /// The App Store's page for writing a review; the customer went there by themselves, so the app never asks after this.
    private func rate() {
        var prompt = model.store.ratePrompt
        prompt.done = true
        model.store.ratePrompt = prompt
        open(Etha.reviewURL)
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { UIApplication.shared.open(url) }
    }
}
