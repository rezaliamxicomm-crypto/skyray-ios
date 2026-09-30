import SwiftUI
import UIKit

/// The Android app's palette, name for name (V2rayNG/app/src/main/res/values{,-night}/colors.xml); the values live in
/// the asset catalog with their light and dark appearances.
extension Color {
    static let bg = Color("bg")                         // md_theme_background
    static let surface = Color("surface")               // md_theme_surface (cards)
    static let surfaceVariant = Color("surfaceVariant") // tiles, the server field
    static let onSurface = Color("onSurface")           // text
    static let primaryBlue = Color("primary")           // md_theme_primary
    static let onPrimary = Color("onPrimary")           // text on a primary button
    static let connectOn = Color("connectOn")           // colorPing: Connect while connected
    static let muted = Color("muted")                   // md_theme_onSurfaceVariant
    static let announce = Color("announce")             // md_theme_secondaryContainer
    static let outline = Color("outline")               // md_theme_outline
    static let error = Color("error")                   // md_theme_error
}

enum AppTheme {
    /// The toolbar as the Android app draws it: the background colour, the title in Vazirmatn, no shadow line.
    static func applyNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "bg")
        appearance.shadowColor = .clear
        let title: [NSAttributedString.Key: Any] = [.font: AppFont.uiTitle, .foregroundColor: UIColor(named: "onSurface") ?? .label]
        appearance.titleTextAttributes = title
        appearance.largeTitleTextAttributes = title
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor(named: "onSurface")
    }
}
