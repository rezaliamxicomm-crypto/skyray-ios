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
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel(Text(L("settings")))
                    }
                }
                .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .navigationViewStyle(.stack)
        .overlay(alignment: .top) { BannerView() }
    }
}
