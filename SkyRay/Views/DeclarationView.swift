import SwiftUI
import SkyRayCore

/// Shown once before anything else: what the app does with the phone's traffic and data (App Store 5.4).
struct DeclarationView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image("AppIconPreview").resizable().frame(width: 72, height: 72).cornerRadius(16)
                Text(L("declaration.title")).font(AppFont.headline).foregroundColor(.onSurface)
                Text(L("declaration.body")).font(AppFont.body).foregroundColor(.onSurface).lineSpacing(3)
                Link(L("privacy"), destination: URL(string: Etha.privacyURL)!).font(AppFont.body).foregroundColor(.primaryBlue)
                Button { model.acceptDeclaration() } label: { Text(L("declaration.continue")) }
                    .buttonStyle(EthaPrimaryButtonStyle())
                    .padding(.top, 8)
            }
            .padding(24)
        }
        .background(Color.bg.ignoresSafeArea())
    }
}
