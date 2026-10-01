import SwiftUI

/// The Android Home (res/layout/activity_home.xml) on the gradient ground: the hero, the server panel, the account
/// tiles — 20 pt at the sides, 24 pt below. The screen is filled from both ends: the content is at least as tall as
/// the screen and the hero takes whatever height the phone has to spare (HeroView centres itself in it and grows a
/// little), so the last button sits at the bottom on every model; a phone too short for everything scrolls.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showServers = false
    private let poll = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { screen in
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
                .frame(minHeight: screen.size.height, alignment: .top)
            }
        }
        .background(Ground())
        .sheet(isPresented: $showServers) { ServerSheet().environmentObject(model) }
        .onReceive(poll) { _ in
            if model.isConnected { Task { await model.pollStatus() } }
        }
    }
}
