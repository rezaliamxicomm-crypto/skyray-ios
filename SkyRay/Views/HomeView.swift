import SwiftUI

/// The Android Home (res/layout/activity_home.xml) on the gradient ground: the hero, the server panel, the account
/// tiles — 20 pt at the sides, 24 pt below.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showServers = false
    private let poll = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if model.hasSubscription {
                    HeroView()
                    ServerPanel { showServers = true }
                    AccountCard().padding(.top, 12)
                } else {
                    EmptyCard().padding(.top, 12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(Ground())
        .sheet(isPresented: $showServers) { ServerSheet().environmentObject(model) }
        .onReceive(poll) { _ in
            if model.isConnected { Task { await model.pollStatus() } }
        }
    }
}
