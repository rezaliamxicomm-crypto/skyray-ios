import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.declarationAccepted {
            MainView()
        } else {
            DeclarationView()
        }
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
