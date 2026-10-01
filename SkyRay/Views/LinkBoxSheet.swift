import SwiftUI
import UIKit
import SkyRayCore

/// Paste found no link on the clipboard (nothing copied it — an install straight from the App Store —, "Don't Allow
/// Paste" was tapped, or something else was copied since): a box to put the link in, where the keyboard's own paste
/// works, and "Open Telegram", which brings the bot's message with the link. As on Android (HomeActivity.askForLink).
/// The customer who taps the link there needs nothing more: the app opens with it and the empty card goes, this
/// sheet with it.
struct LinkBoxSheet: View {
    let onLink: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("link.box.text")).font(AppFont.body).foregroundColor(.onSurface).lineSpacing(3)
                    TextField("https://…", text: $text)
                        .font(AppFont.body)
                        .foregroundColor(.onSurface)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .environment(\.layoutDirection, .leftToRight)   // a link reads left to right in every language
                        .padding(.horizontal, 14)
                        .frame(minHeight: 50)
                        .background(Color.panel)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(invalid ? Color.error : Color.edge, lineWidth: 1))
                        .padding(.top, 16)
                        .onChange(of: text) { _ in invalid = false }
                    if invalid {
                        Text(L("link.invalid")).font(AppFont.small).foregroundColor(.error).padding(.top, 6)
                    }
                    Button { add() } label: { Text(L("link.box.add")) }
                        .buttonStyle(EthaPrimaryButtonStyle())
                        .padding(.top, 16)
                    Button { openTelegram() } label: { Text(L("link.box.telegram")).frame(maxWidth: .infinity) }
                        .buttonStyle(EthaTextButtonStyle(font: AppFont.textButton))
                        .padding(.top, 10)
                }
                .padding(20)
            }
            .background(Color.sheet.ignoresSafeArea())
            .navigationTitle(L("link.box.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(L("cancel")) { dismiss() } } }
        }
        .navigationViewStyle(.stack)
    }

    private func add() {
        guard let link = EthaLink.extract(from: text) else { invalid = true; return }
        onLink(link)
    }

    private func openTelegram() {
        if let url = URL(string: Etha.linkURL) { UIApplication.shared.open(url) }
    }
}
