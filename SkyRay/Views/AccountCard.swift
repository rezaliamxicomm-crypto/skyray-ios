import SwiftUI
import SkyRayCore

/// The account card as on Android: the subscription's title, the days and data tiles, the service's announcement,
/// then the buttons. Android's row is Renew | Support with Refresh under it; here Support | Refresh: the App Store
/// forbids a button that leads to a purchase outside it, and renewals happen in Telegram.
struct AccountCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Card {
            Text(model.snapshot?.info.profileTitle ?? model.snapshot?.name ?? Etha.subName)
                .font(AppFont.title).foregroundColor(.onSurface)
            HStack(spacing: 12) {
                tile(value: days.value, label: days.label)
                tile(value: data.value, label: data.label)
            }
            .padding(.top, 14)
            if let announce = model.snapshot?.info.announce, !announce.isEmpty {
                Text(announce)
                    .font(AppFont.body).foregroundColor(.onSurface)
                    .lineSpacing(3)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.announce)
                    .cornerRadius(14)
                    .padding(.top, 14)
            }
            HStack(spacing: 10) {
                Button { open(model.snapshot?.info.supportURL ?? Etha.supportURL) } label: { Text(L("support")) }
                    .buttonStyle(EthaPrimaryButtonStyle())
                Button { Task { await model.refreshNow() } } label: {
                    HStack(spacing: 6) {
                        if model.refreshing { ProgressView().scaleEffect(0.8) }
                        Text(L("refresh"))
                    }
                }
                .buttonStyle(EthaOutlinedButtonStyle())
                .disabled(model.refreshing)
            }
            .padding(.top, 14)
        }
    }

    /// EthaTile: the surfaceVariant colour, 16 pt corners, 14 pt of padding; the value in 22 pt bold, the label in 13 pt.
    private func tile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(AppFont.tileValue).foregroundColor(.onSurface).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(AppFont.small).foregroundColor(.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceVariant)
        .cornerRadius(16)
    }

    private var days: (value: String, label: String) {
        let expire = model.snapshot?.info.expire ?? -1
        guard let left = SubscriptionHeaders.daysLeft(expire: expire) else { return ("–", L("days.label")) }
        if left == Int64.max { return ("∞", L("no.expiry")) }
        if left == 0 { return ("0", L("expired")) }
        return ("\(left)", L("days.label"))
    }

    private var data: (value: String, label: String) {
        let info = model.snapshot?.info ?? SubscriptionInfo()
        let used = Self.format(bytes: max(0, info.download) + max(0, info.upload))
        if info.total < 0 { return ("–", L("data.unknown")) }
        if info.total == 0 { return (used, L("data.unlimited")) }
        return (used, L("data.of", Self.format(bytes: info.total)))
    }

    static func format(bytes: Int64) -> String {
        if bytes >= 1 << 30 { return String(format: "%.1f GB", Double(bytes) / 1_073_741_824) }
        if bytes >= 1 << 20 { return String(format: "%.0f MB", Double(bytes) / 1_048_576) }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { UIApplication.shared.open(url) }
    }
}
