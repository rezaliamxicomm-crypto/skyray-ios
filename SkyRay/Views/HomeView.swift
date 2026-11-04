import SwiftUI

/// The Android Home (res/layout/activity_home.xml) on the gradient ground: the hero with its two buttons, the account
/// tiles — 20 pt at the sides, 24 pt below. The screen is filled from both ends: the content is at least as tall as
/// the screen and the hero takes whatever height the phone has to spare (HeroView centres itself in it and grows a
/// little), so the last button sits at the bottom on every model; a phone too short for everything scrolls.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    private let poll = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { screen in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if model.hasSubscription {
                        HeroView()
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
        .onReceive(poll) { _ in
            if model.isConnected { Task { await model.pollStatus() } }
        }
        .sheet(isPresented: $model.showServers) { ServersSheet().environmentObject(model) }   // the Servers sheet (3.0.0)
        .alert(item: $model.devicesLimit) { d in   // the device limit's refusal (3.0.0)
            Alert(title: Text(L("devices.title")), message: Text(L("devices.text", String(d.active), String(d.limit))),
                  primaryButton: .default(Text(L("devices.bot"))) { if let u = URL(string: model.snapshot?.info.supportURL ?? Etha.supportURL) { UIApplication.shared.open(u) } },
                  secondaryButton: .cancel())
        }
        .overlay(UpdateGate())   // the update screen (3.0.0): the box says this version is below what it supports
    }
}

/// The update screen (3.0.0): the box's X-Etha-App-Min is above this build — one way out, the App Store. Over the Home screen until the
/// version is right; the alert comes back when dismissed.
private struct UpdateGate: View {
    @EnvironmentObject private var model: AppModel
    @State private var shown = false
    var body: some View {
        Color.clear
            .alert(isPresented: $shown) {
                Alert(title: Text(L("update.title")), message: Text(L("update.text")),
                      dismissButton: .default(Text(L("update.now"))) { if let u = URL(string: Etha.appStoreURL) { UIApplication.shared.open(u) } })
            }
            .onAppear { shown = model.updateDue }
            .onChange(of: model.updateDue) { shown = $0 }
            .allowsHitTesting(false)
    }
}
