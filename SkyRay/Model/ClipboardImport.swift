import UIKit
import SkyRayCore

/// The first launch: the landing page copies the customer's link before the install, so the app can add the
/// account by itself. Reads only when the clipboard says it holds a web address (no banner otherwise).
enum ClipboardImport {
    /// Returns false when the clipboard handed nothing over (the caller retries once after a moment).
    @MainActor
    static func attempt(model: AppModel) async -> Bool {
        let pasteboard = UIPasteboard.general
        guard pasteboard.hasStrings || pasteboard.hasURLs else { return false }
        let patterns = await detectedPatterns(pasteboard)
        if let patterns = patterns, !patterns.contains(\.probableWebURL) { return true }
        guard let text = pasteboard.string ?? pasteboard.url?.absoluteString else { return false }
        guard let link = EthaLink.extract(from: text) else { return true }
        await model.importFromClipboard(link)
        return true
    }

    @MainActor
    private static func detectedPatterns(_ pasteboard: UIPasteboard) async -> Set<PartialKeyPath<UIPasteboard.DetectedValues>>? {
        await withCheckedContinuation { continuation in
            pasteboard.detectPatterns(for: [\.probableWebURL]) { result in
                switch result {
                case .success(let set): continuation.resume(returning: set)
                case .failure: continuation.resume(returning: nil)
                }
            }
        }
    }
}
