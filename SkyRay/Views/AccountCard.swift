import SwiftUI
import SkyRayCore

/// The account as on Android: two tiles (days, data with its bar), the "Updated <ago>" line with the Refresh pill,
/// the announcement, then Support. Android's row is Renew | Support; the App Store forbids a button that leads to a
/// purchase outside it, and renewals happen in Telegram, so here Support stands alone.
struct AccountCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                tile(value: days.value, label: days.label, fraction: nil)
                tile(value: data.value, label: data.label, fraction: dataFraction)
            }
            if let announce = model.snapshot?.info.announce, !announce.isEmpty {
                Text(announce)
                    .font(AppFont.body).foregroundColor(.onSurface)
                    .lineSpacing(3)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.announce)
                    .cornerRadius(14)
                    .padding(.top, 12)
            }
            HStack {
                Text(updatedText).font(AppFont.chip).foregroundColor(.muted)
                Spacer(minLength: 0)
                Button { Task { await model.refreshNow() } } label: {
                    HStack(spacing: 6) {
                        if model.refreshing { ProgressView().scaleEffect(0.6).frame(width: 14, height: 14) }
                        else { Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .bold)) }
                        Text(L("refresh"))
                    }
                }
                .buttonStyle(EthaPillButtonStyle())
                .disabled(model.refreshing)
            }
            .padding(.leading, 4)
            .padding(.top, 10)
            Button { open(model.snapshot?.info.supportURL ?? Etha.supportURL) } label: { Text(L("support")) }
                .buttonStyle(EthaPrimaryButtonStyle())
                .padding(.top, 12)
        }
    }

    /// EthaTile: the panel, the value in 26 pt bold, the label in 12 pt, the data bar under the data tile.
    private func tile(value: String, label: String, fraction: Double?) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 4) {
                Text(value).font(AppFont.tileValue).foregroundColor(.onSurface).lineLimit(1).minimumScaleFactor(0.6)
                Text(label).font(AppFont.tileLabel).foregroundColor(.muted)
                if let f = fraction {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.track)
                            Capsule().fill(Color.blueLight).frame(width: max(0, min(1, f)) * geo.size.width)
                        }
                    }
                    .frame(height: 4)
                    .padding(.top, 6)
                }
            }
        }
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

    private var dataFraction: Double? {
        let info = model.snapshot?.info ?? SubscriptionInfo()
        guard info.total > 0 else { return nil }
        return Double(max(0, info.download) + max(0, info.upload)) / Double(info.total)
    }

    /// "Updated 3 min. ago" from the last fetch — Android's tv_updated (DateUtils' relative span).
    private var updatedText: String {
        guard let at = model.snapshot?.fetchedAt else { return L("updated.never") }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return L("updated", f.localizedString(for: at, relativeTo: Date()))
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
