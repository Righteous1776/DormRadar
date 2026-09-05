import SwiftUI

extension AppTheme {
    var accent: Color {
        switch self {
        case .midnight: return .cyan
        case .oledBlack: return .mint
        case .graphite: return Color(red: 0.48, green: 0.72, blue: 0.95)
        case .redNight: return Color(red: 0.92, green: 0.24, blue: 0.18)
        }
    }
    var background: LinearGradient {
        let colors: [Color]
        switch self {
        case .midnight:
            colors = [Color(red: 0.025, green: 0.04, blue: 0.08),
                      Color(red: 0.02, green: 0.09, blue: 0.12)]
        case .oledBlack: colors = [.black, Color(red: 0.01, green: 0.025, blue: 0.025)]
        case .graphite:
            colors = [Color(red: 0.055, green: 0.06, blue: 0.075),
                      Color(red: 0.10, green: 0.11, blue: 0.13)]
        case .redNight:
            colors = [Color(red: 0.035, green: 0.005, blue: 0.005),
                      Color(red: 0.10, green: 0.012, blue: 0.008)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension MarkerColor {
    var swiftUIColor: Color {
        switch self {
        case .cyan: return .cyan
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        case .purple: return .purple
        }
    }
}

struct ExtraDimOverlay: View {
    let amount: Double
    var body: some View {
        Color.black.opacity(amount).ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}
