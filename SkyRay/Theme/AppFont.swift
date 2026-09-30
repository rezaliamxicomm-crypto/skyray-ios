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
    static var title: Font { font(17, weight: .bold) }         // EthaTitle
    static var body: Font { font(15) }                         // EthaBody
    static var muted: Font { font(14) }                        // EthaMuted
    static var hint: Font { font(13) }                         // the hint under the state
    static var small: Font { font(13) }                        // settings summaries
    static var label: Font { font(11, weight: .medium) }       // EthaLabel: SERVER, tile labels (uppercase)
    static var chip: Font { font(12) }                         // the server chip, the updated line
    static var value: Font { font(14, weight: .medium) }       // the server panel's value, sheet rows
    static var ms: Font { font(13) }                           // pings in the sheet
    static var link: Font { font(12, weight: .bold) }          // Ping all, Show all, the Refresh pill
    static var button: Font { font(15, weight: .medium) }      // EthaPrimaryButton / EthaOutlinedButton
    static var textButton: Font { font(13, weight: .medium) }
    static var tileValue: Font { font(26, weight: .bold) }     // EthaTileValue
    static var tileLabel: Font { font(12) }                    // EthaTileLabel
    static var sheetTitle: Font { font(16, weight: .bold) }
    static var row: Font { font(16) }                          // EthaSettingsTitle
    static var uiTitle: UIFont { UIFont(name: "Vazirmatn-Bold", size: 20) ?? .systemFont(ofSize: 20, weight: .bold) }
}
