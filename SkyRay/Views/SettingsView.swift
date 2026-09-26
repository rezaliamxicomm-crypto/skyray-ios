import SwiftUI
import SkyRayCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var showLogs = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    NavigationLink(destination: ServerListView()) {
                        row("antenna.radiowaves.left.and.right", L("server.title"), model.serverLabel)
                    }
                    .disabled(!model.hasSubscription)
                    Button { open(UIApplication.openSettingsURLString) } label: {
                        row("globe", L("language"), Locale.current.localizedString(forLanguageCode: appLanguage) ?? L("language.system"))
                    }
                }
                Section {
                    Button { showLogs = true } label: { row("doc.text", L("send.logs"), L("send.logs.hint")) }
                    NavigationLink(destination: AboutView()) { row("info.circle", L("about"), nil) }
                    Button { open(Etha.privacyURL) } label: { row("hand.raised", L("privacy"), nil) }
                }
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: { row("trash", L("delete.account"), L("delete.hint")) }
                }
            }
            .navigationTitle(L("settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(L("done")) { dismiss() } } }
            .confirmationDialog(L("delete.account"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L("delete.do"), role: .destructive) { Task { await model.deleteAccount(); dismiss() } }
                Button(L("cancel"), role: .cancel) {}
            } message: {
                Text(L("delete.confirm"))
            }
            .sheet(isPresented: $showLogs) { LogShareSheet(urls: logURLs) }
        }
        .navigationViewStyle(.stack)
    }

    private var logURLs: [URL] {
        [model.store.appLogURL, model.store.tunnelLogURL, model.store.xrayLogURL].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func row(_ icon: String, _ title: String, _ subtitle: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 24).foregroundColor(.primaryBlue)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.body).foregroundColor(.primary)
                if let s = subtitle, !s.isEmpty { Text(s).font(AppFont.small).foregroundColor(.muted) }
            }
        }
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { UIApplication.shared.open(url) }
    }
}

struct ServerListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            ForEach(Array(model.serverRows.enumerated()), id: \.offset) { _, row in
                Button {
                    Task { await model.pick(lineId: row.id) }
                } label: {
                    HStack {
                        Text(row.text).font(AppFont.body).foregroundColor(.primary)
                        Spacer()
                        if isCurrent(row) { Image(systemName: "checkmark").foregroundColor(.primaryBlue) }
                    }
                }
            }
            Button(L("test.again")) { Task { await model.testAgain() } }.disabled(model.busy)
        }
        .navigationTitle(L("server.pick"))
    }

    private func isCurrent(_ row: ServerRows.Row) -> Bool {
        if row.id == nil { return !model.selection.pinned }
        return model.selection.pinned && row.id == model.selection.selectedLineId
    }
}
