import SwiftUI
import UIKit
import SkyRayCore

/// No account yet, as on Android: "Almost there", the hint, one Paste link button (the page copied the link), and
/// Scan QR code as a text button — in a panel on the ground. A Paste with no link on the clipboard opens the box
/// to put it in (LinkBoxSheet): never a dead end.
struct EmptyCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var showScanner = false
    @State private var showLinkBox = false

    var body: some View {
        Panel(padding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)) {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("empty.title")).font(AppFont.title).foregroundColor(.onSurface)
                Text(L("empty.hint")).font(AppFont.body).foregroundColor(.onSurface).lineSpacing(3).padding(.top, 6)
                Button {
                    // the copied text, else a copied web address; nothing of ours there (or "Don't Allow Paste") → the box
                    let text = UIPasteboard.general.string ?? UIPasteboard.general.url?.absoluteString ?? ""
                    if EthaLink.extract(from: text) == nil {
                        showLinkBox = true
                    } else {
                        Task { await model.importLink(text, source: .paste) }
                    }
                } label: { Text(L("paste")) }
                    .buttonStyle(EthaPrimaryButtonStyle())
                    .padding(.top, 18)
                    .sheet(isPresented: $showLinkBox) {
                        LinkBoxSheet { link in
                            showLinkBox = false
                            Task { await model.importLink(link, source: .paste) }
                        }
                    }
                Button { showScanner = true } label: { Text(L("scan")).frame(maxWidth: .infinity) }
                    .buttonStyle(EthaTextButtonStyle(font: AppFont.textButton))
                    .padding(.top, 10)
            }
        }
        .sheet(isPresented: $showScanner) {
            QRScannerSheet { text in
                showScanner = false
                Task { await model.importLink(text, source: .qr) }
            }
        }
    }
}
