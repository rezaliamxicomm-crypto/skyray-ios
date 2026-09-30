import SwiftUI
import UIKit

/// Vazirmatn everywhere, as on Android (the theme there sets one typeface for every language); the point sizes are
/// the Android sp values of the Etha* styles in res/values/themes.xml.
enum AppFont {
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .bold, .heavy, .black, .semibold: return .custom("Vazirmatn-Bold", size: size)
        case .medium: return .custom("Vazirmatn-Medium", size: size)
        default: return .custom("Vazirmatn-Regular", size: size)
        }
    }

    static var headline: Font { font(22, weight: .bold) }      // EthaHeadline: the state under Connect
    static var title: Font { font(17, weight: .bold) }         // EthaTitle: card titles
    static var body: Font { font(15) }                         // EthaBody
    static var muted: Font { font(14) }                        // EthaMuted
    static var small: Font { font(13) }                        // tile labels, settings summaries
    static var button: Font { font(15, weight: .medium) }      // EthaPrimaryButton / EthaOutlinedButton
    static var textButton: Font { font(13, weight: .medium) }  // Test again
    static var tileValue: Font { font(22, weight: .bold) }     // EthaTileValue
    static var row: Font { font(16) }                          // EthaSettingsTitle
    static var field: Font { font(15) }                        // the server dropdown
    static var floating: Font { font(12) }                     // the dropdown's floating label
    static var uiTitle: UIFont { UIFont(name: "Vazirmatn-Medium", size: 20) ?? .systemFont(ofSize: 20, weight: .medium) }
}
