import SwiftUI
import UIKit

/// SkyRay 1.3: one dark look in every mode, token for token the Android palette
/// (V2rayNG/app/src/main/res/values/colors.xml — the night file there is identical on purpose).
extension Color {
    static let bg = Color("bg")                         // md_theme_background: the ground's darkest end
    static let surface = Color("surface")               // md_theme_surface
    static let surfaceVariant = Color("surfaceVariant") // md_theme_surfaceVariant
    static let onSurface = Color("onSurface")           // text
    static let primaryBlue = Color("primary")           // etha_blue: Connect idle, the filled button
    static let onPrimary = Color("onPrimary")
    static let connectOn = Color("connectOn")           // etha_green: Connect while connected
    static let muted = Color("muted")                   // etha_muted
    static let announce = Color("announce")             // md_theme_secondaryContainer
    static let outline = Color("outline")               // md_theme_outline
    static let error = Color("error")

    static let groundTop = Color(red: 0x1B / 255, green: 0x2B / 255, blue: 0x57 / 255)     // etha_ground_top
    static let groundMid = Color(red: 0x12 / 255, green: 0x1C / 255, blue: 0x36 / 255)     // etha_ground_mid
    static let panel = Color.white.opacity(0.06)                                            // etha_panel
    static let edge = Color.white.opacity(0.10)                                             // etha_edge
    static let track = Color.white.opacity(0.10)                                            // etha_track
    static let sheet = Color(red: 0x14 / 255, green: 0x1E / 255, blue: 0x3A / 255)         // etha_sheet
    static let blueLight = Color(red: 0x60 / 255, green: 0xA5 / 255, blue: 0xFA / 255)     // etha_blue_light
    static let greenLight = Color(red: 0x34 / 255, green: 0xD3 / 255, blue: 0x99 / 255)    // etha_green_light
    static let amber = Color(red: 0xF5 / 255, green: 0xB9 / 255, blue: 0x42 / 255)         // etha_amber
    static let pingRed = Color(red: 0xF2 / 255, green: 0x6D / 255, blue: 0x6D / 255)       // etha_red

    /// The ping dot: green under 500 ms, amber under 800, red failed or slower, muted untested — ServerPicker.dotColor.
    static func ping(_ ms: Int64) -> Color {
        if ms == 0 { return .muted }
        if ms < 0 || ms >= 800 { return .pingRed }
        return ms < 500 ? .greenLight : .amber
    }
}

/// The Home ground: the gradient Android draws behind its transparent toolbar (res/drawable/bg_home.xml).
struct Ground: View {
    var body: some View {
        LinearGradient(stops: [.init(color: .groundTop, location: 0), .init(color: .groundMid, location: 0.45), .init(color: .bg, location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

enum AppTheme {
    /// The toolbar as the Android app draws it: transparent over the ground, the title in Vazirmatn, no shadow line.
    static func applyNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.shadowColor = .clear
        let title: [NSAttributedString.Key: Any] = [.font: AppFont.uiTitle, .foregroundColor: UIColor(named: "onSurface") ?? .white]
        appearance.titleTextAttributes = title
        appearance.largeTitleTextAttributes = title
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor(named: "onSurface")
    }
}
