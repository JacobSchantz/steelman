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
}
