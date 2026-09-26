import SwiftUI

/// The short message at the top of the screen (added / failed / switched), gone after a few seconds.
struct BannerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let banner = model.banner {
            Text(banner.text)
                .font(AppFont.small)
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(color(banner.kind))
                .cornerRadius(10)
                .padding(.horizontal, 16).padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { model.banner = nil }
                .task(id: banner.id) {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if model.banner?.id == banner.id { model.banner = nil }
                }
        }
    }

    private func color(_ kind: BannerMessage.Kind) -> Color {
        switch kind {
        case .ok: return .connectOn
        case .error: return Color(red: 0.72, green: 0.16, blue: 0.16)
        case .info: return .primaryBlue
        }
    }
}
