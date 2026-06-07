import SwiftUI

/// Shared colors and small style helpers for a bright, friendly look.
enum Theme {
    static let background = Color(red: 0.06, green: 0.08, blue: 0.16)
    static let panel = Color(red: 0.12, green: 0.15, blue: 0.26)
    static let panelStroke = Color.white.opacity(0.08)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.65)
    static let accent = Color(red: 0.36, green: 0.78, blue: 0.95)
    static let win = Color(red: 0.36, green: 0.85, blue: 0.55)

    static func rounded(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension View {
    /// A rounded card background used by the panels.
    func cardStyle(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.panelStroke, lineWidth: 1)
            )
    }
}
