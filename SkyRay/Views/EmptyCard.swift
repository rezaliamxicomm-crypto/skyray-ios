import SwiftUI
import UIKit

/// No account yet, as on Android: "Almost there", the hint, one Paste link button (the page copied the link), and
/// Scan QR code as a text button — in a panel on the ground.
struct EmptyCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var showScanner = false

    var body: some View {
        Panel(padding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)) {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("empty.title")).font(AppFont.title).foregroundColor(.onSurface)
                Text(L("empty.hint")).font(AppFont.body).foregroundColor(.onSurface).lineSpacing(3).padding(.top, 6)
                Button {
                    Task { await model.importLink(UIPasteboard.general.string ?? "", source: .paste) }
                } label: { Text(L("paste")) }
                    .buttonStyle(EthaPrimaryButtonStyle())
                    .padding(.top, 18)
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
