import SwiftUI
import SkyRayCore

/// Days and data left, the service's announcement, Support and Refresh. No Renew: renewals happen in
/// Telegram, and the App Store does not allow a button that points there.
struct AccountCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Card {
            Text(model.snapshot?.info.profileTitle ?? model.snapshot?.name ?? Etha.subName).font(AppFont.title)
            HStack(spacing: 12) {
                tile(value: days.value, label: days.label)
                tile(value: data.value, label: data.label)
            }
            if let announce = model.snapshot?.info.announce, !announce.isEmpty {
                Text(announce).font(AppFont.body)
            }
            HStack(spacing: 12) {
                Link(destination: URL(string: model.snapshot?.info.supportURL ?? Etha.supportURL) ?? URL(string: Etha.supportURL)!) {
                    Text(L("support")).font(AppFont.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.primaryBlue)
                Button { Task { await model.refreshNow() } } label: {
                    HStack(spacing: 6) {
                        if model.refreshing { ProgressView().scaleEffect(0.8) } else { Image(systemName: "arrow.clockwise") }
                        Text(L("refresh")).font(AppFont.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.refreshing)
            }
        }
    }

    private func tile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(AppFont.tile).lineLimit(1).minimumScaleFactor(0.5)
            Text(label).font(AppFont.small).foregroundColor(.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.surfaceVariant)
        .cornerRadius(12)
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
}
