import SwiftUI
import SkyRayCore

/// Shown once before anything else: what the app does with the phone's traffic and data (App Store 5.4).
struct DeclarationView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image("AppIconPreview").resizable().frame(width: 72, height: 72).cornerRadius(16)
                Text(L("declaration.title")).font(AppFont.title)
                Text(L("declaration.body")).font(AppFont.body)
                Link(L("privacy"), destination: URL(string: Etha.privacyURL)!).font(AppFont.body)
                Button { model.acceptDeclaration() } label: {
                    Text(L("declaration.continue")).font(AppFont.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.primaryBlue)
                .padding(.top, 8)
            }
            .padding(24)
        }
        .background(Color.bg.ignoresSafeArea())
    }
}
