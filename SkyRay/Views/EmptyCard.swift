import SwiftUI
import UIKit

/// No account yet: one tap on Paste link (the page copied it), or a QR code.
struct EmptyCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var showScanner = false

    var body: some View {
        Card {
            Text(L("empty.title")).font(AppFont.title)
            Text(L("empty.hint")).font(AppFont.body).foregroundColor(.muted)
            pasteButton
                .padding(.top, 6)
            Button { showScanner = true } label: {
                Text(L("scan")).font(AppFont.body).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.primaryBlue)
        }
        .sheet(isPresented: $showScanner) {
            QRScannerSheet { text in
                showScanner = false
                Task { await model.importLink(text, source: .qr) }
            }
        }
    }

    @ViewBuilder
    private var pasteButton: some View {
        if #available(iOS 16.0, *) {
            PasteButton(payloadType: String.self) { strings in
                Task { await model.importLink(strings.first ?? "", source: .paste) }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.roundedRectangle)
            .frame(maxWidth: .infinity)
        } else {
            Button {
                Task { await model.importLink(UIPasteboard.general.string ?? "", source: .paste) }
            } label: {
                Text(L("paste")).font(AppFont.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primaryBlue)
        }
    }
}
