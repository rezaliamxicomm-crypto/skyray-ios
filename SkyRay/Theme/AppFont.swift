import SwiftUI

/// Vazirmatn for Farsi (the same face as the Android app), the system font otherwise.
enum AppFont {
    static var isFarsi: Bool { appLanguage.hasPrefix("fa") }

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard isFarsi else { return .system(size: size, weight: weight) }
        switch weight {
        case .bold, .heavy, .black, .semibold: return .custom("Vazirmatn-Bold", size: size)
        case .medium: return .custom("Vazirmatn-Medium", size: size)
        default: return .custom("Vazirmatn-Regular", size: size)
        }
    }

    static var title: Font { font(20, weight: .bold) }
    static var headline: Font { font(17, weight: .medium) }
    static var body: Font { font(16) }
    static var small: Font { font(13) }
    static var tile: Font { font(28, weight: .bold) }
}
