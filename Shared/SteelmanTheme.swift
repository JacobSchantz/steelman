import SwiftUI

enum SteelmanTheme {
    static let accent = Color(red: 0.22, green: 0.45, blue: 0.72)
    static let sideA = Color(red: 0.22, green: 0.45, blue: 0.72)
    static let sideB = Color(red: 0.85, green: 0.45, blue: 0.22)
    static let danger = Color(red: 0.75, green: 0.25, blue: 0.28)

    static func color(for side: ArgumentSide) -> Color {
        switch side {
        case .a: return sideA
        case .b: return sideB
        }
    }

    /// Categories are free text, so their colours can't be declared up front — they're
    /// derived from the name, which keeps a category the same colour everywhere it appears
    /// and across launches. Hashed by hand (djb2) rather than with `hashValue`: Swift seeds
    /// that per process, so "Work" would be a different colour every time the app opened.
    static func color(forCategory category: String) -> Color {
        var hash: UInt64 = 5381
        for byte in category.lowercased().utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return categoryPalette[Int(hash % UInt64(categoryPalette.count))]
    }

    private static let categoryPalette: [Color] = [
        Color(red: 0.22, green: 0.45, blue: 0.72),
        Color(red: 0.85, green: 0.45, blue: 0.22),
        Color(red: 0.30, green: 0.56, blue: 0.40),
        Color(red: 0.55, green: 0.36, blue: 0.68),
        Color(red: 0.78, green: 0.55, blue: 0.20),
        Color(red: 0.24, green: 0.55, blue: 0.62),
    ]
}
