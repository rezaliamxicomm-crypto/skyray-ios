import SwiftUI

/// The Android Home (res/layout/activity_home.xml): the cards in a scroll view, 20 pt at the sides, 12 pt above,
/// 28 pt below, 14 pt between the cards.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    private let poll = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if model.hasSubscription {
                    StatusCard()
                    AccountCard()
                } else {
                    EmptyCard()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(Color.bg.ignoresSafeArea())
        .onReceive(poll) { _ in
            if model.isConnected { Task { await model.pollStatus() } }
        }
    }
}

/// EthaCard: the surface colour, 22 pt corners, no elevation, 20 pt of padding.
struct Card<Content: View>: View {
    var topPadding: CGFloat = 20
    let content: Content
    init(topPadding: CGFloat = 20, @ViewBuilder content: () -> Content) { self.topPadding = topPadding; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, topPadding)
            .padding(.bottom, 20)
            .background(Color.surface)
            .cornerRadius(22)
    }
}
