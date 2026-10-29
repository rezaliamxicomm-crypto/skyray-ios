import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    /// The first-open declaration screen (DeclarationView) is not shown since Apple's review asked for it to go
    /// (2026-10-29): the app collects nothing to declare. The screen, its texts and the accepted flag stay in the
    /// code; AppModel marks the flag accepted at launch so the first-open imports still run.
    var body: some View {
        MainView()
    }
}

/// The Android toolbar: the app's name, the settings gear at the end; Settings opens as its own screen with a back arrow.
struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            HomeView()
                .navigationTitle("SkyRay")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill").foregroundColor(.onSurface)
                        }
                        .accessibilityLabel(Text(L("settings")))
                    }
                }
                .background(
                    NavigationLink(destination: SettingsView(), isActive: $showSettings) { EmptyView() }.hidden()
                )
        }
        .navigationViewStyle(.stack)
        .overlay(alignment: .top) { BannerView() }
    }
}
