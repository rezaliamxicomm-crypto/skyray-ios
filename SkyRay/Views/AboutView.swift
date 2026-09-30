import SwiftUI
import SkyRayCore

struct AboutView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("about.version", version, build)).font(AppFont.row).foregroundColor(.onSurface).padding(16)
                Text(L("about.core", model.tunnel?.xrayVersion ?? model.store.tunnelState.xrayVersion ?? "–")).font(AppFont.row).foregroundColor(.onSurface).padding(16)
                Text(L("about.licenses")).font(AppFont.small).foregroundColor(.muted).lineSpacing(3).padding(16)
                Link(L("about.source"), destination: URL(string: Etha.sourceURL)!).font(AppFont.row).foregroundColor(.primaryBlue).padding(16)
                Link(L("privacy"), destination: URL(string: Etha.privacyURL)!).font(AppFont.row).foregroundColor(.primaryBlue).padding(16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle(L("about"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    private var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?" }
}
