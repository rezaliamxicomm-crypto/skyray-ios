import SwiftUI
import SkyRayCore

struct AboutView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section {
                Text(L("about.version", version, build)).font(AppFont.body)
                Text(L("about.core", model.tunnel?.xrayVersion ?? model.store.tunnelState.xrayVersion ?? "–")).font(AppFont.body)
            }
            Section {
                Text(L("about.licenses")).font(AppFont.small).foregroundColor(.muted)
                Link(L("about.source"), destination: URL(string: Etha.sourceURL)!)
                Link(L("privacy"), destination: URL(string: Etha.privacyURL)!)
            }
        }
        .navigationTitle(L("about"))
    }

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    private var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?" }
}
