import SwiftUI

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
            .padding(16)
        }
        .background(Color.bg.ignoresSafeArea())
        .onReceive(poll) { _ in
            if model.isConnected { Task { await model.pollStatus() } }
        }
    }
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color.surface)
            .cornerRadius(18)
    }
}
