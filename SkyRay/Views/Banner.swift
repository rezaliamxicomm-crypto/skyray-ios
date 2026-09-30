import SwiftUI

/// The short message at the top of the screen (added / failed / switched), gone after a few seconds — the
/// Android app's toasts.
struct BannerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let banner = model.banner {
            Text(banner.text)
                .font(AppFont.muted)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
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
        case .error: return .error
        case .info: return .primaryBlue
        }
    }
}
