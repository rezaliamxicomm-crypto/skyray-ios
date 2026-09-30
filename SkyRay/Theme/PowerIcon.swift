import SwiftUI

/// Material's power icon, the Android app's Connect glyph (res/drawable/ic_power_48dp.xml), drawn from its path in
/// a 24 × 24 viewport so the two apps show the same shape.
struct PowerIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let ox = rect.minX + (rect.width - 24 * s) / 2
        let oy = rect.minY + (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var path = Path()
        // the bar: M13,3 h-2 v10 h2 V3 z
        path.move(to: p(13, 3)); path.addLine(to: p(11, 3)); path.addLine(to: p(11, 13)); path.addLine(to: p(13, 13)); path.closeSubpath()
        // the ring: M17.83,5.17 l-1.42,1.42 C… (absolute points computed from the Material path data)
        path.move(to: p(17.83, 5.17))
        path.addLine(to: p(16.41, 6.59))
        path.addCurve(to: p(19, 12), control1: p(17.99, 7.86), control2: p(19, 9.81))
        path.addCurve(to: p(12, 19), control1: p(19, 15.87), control2: p(15.87, 19))
        path.addCurve(to: p(5, 12), control1: p(8.13, 19), control2: p(5, 15.87))
        path.addCurve(to: p(7.58, 6.58), control1: p(5, 9.81), control2: p(6.01, 7.86))
        path.addLine(to: p(6.17, 5.17))
        path.addCurve(to: p(3, 12), control1: p(4.23, 6.82), control2: p(3, 9.26))
        path.addCurve(to: p(12, 21), control1: p(3, 16.97), control2: p(7.03, 21))
        path.addCurve(to: p(21, 12), control1: p(16.97, 21), control2: p(21, 16.97))
        path.addCurve(to: p(17.83, 5.17), control1: p(21, 9.26), control2: p(19.77, 6.82))
        path.closeSubpath()
        return path
    }
}
