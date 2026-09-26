import SwiftUI
import UIKit

/// The share sheet with the log files (for support only).
struct LogShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let items: [Any] = urls.isEmpty ? [L("logs.none")] : urls
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
