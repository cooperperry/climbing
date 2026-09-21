import SwiftUI

extension ShapeStyle where Self == Color {
    /// Athletic accent inspired by Strava's signature orange (#FC4C02).
    ///
    /// Declared on `ShapeStyle where Self == Color` (the same pattern SwiftUI
    /// uses for `.red`, `.blue`, …) so `.stravaOrange` resolves in `ShapeStyle`
    /// contexts like `.foregroundStyle`/`.tint`, not just as `Color.stravaOrange`.
    static var stravaOrange: Color {
        Color(red: 0.988, green: 0.298, blue: 0.008)
    }
}

extension Color {
    init(hold color: HoldColor) {
        self.init(red: color.red, green: color.green, blue: color.blue)
    }
}
