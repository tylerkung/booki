import SwiftUI

/// Design tokens for the dark sports-betting theme
/// Provides consistent colors, typography, and styling across the app
enum Theme {

    // MARK: - Background Colors

    /// Primary background: near-black (#0D0D0D)
    static let background = Color(hex: 0x0D0D0D)

    /// Secondary background: dark gray for cards (#1A1A1A)
    static let cardBackground = Color(hex: 0x1A1A1A)

    /// Tertiary background: slightly lighter for nested elements (#252525)
    static let elevatedBackground = Color(hex: 0x252525)

    // MARK: - Accent Colors

    /// Primary accent: vibrant green for positive/wins (#00FF87)
    static let accent = Color(hex: 0x00FF87)

    /// Secondary accent: gold/yellow for highlights (#FFD700)
    static let gold = Color(hex: 0xFFD700)

    /// Danger color: red for losses/errors (#FF4444)
    static let danger = Color(hex: 0xFF4444)

    /// Warning color: orange for caution states (#FF9500)
    static let warning = Color(hex: 0xFF9500)

    // MARK: - Text Colors

    /// Primary text: white
    static let textPrimary = Color.white

    /// Secondary text: gray (#9E9E9E)
    static let textSecondary = Color(hex: 0x9E9E9E)

    /// Muted text: darker gray (#666666)
    static let textMuted = Color(hex: 0x666666)

    // MARK: - Status Colors

    /// Live indicator green (#00FF87)
    static let live = accent

    /// Scheduled/upcoming blue (#007AFF)
    static let scheduled = Color(hex: 0x007AFF)

    /// Final/completed gray (#666666)
    static let finalStatus = Color(hex: 0x666666)

    // MARK: - Bet Result Colors

    /// Win color: matches accent green
    static let win = accent

    /// Loss color: matches danger red
    static let loss = danger

    /// Push color: neutral gray
    static let push = textSecondary

    // MARK: - UI Element Colors

    /// Border color for cards and inputs (#333333)
    static let border = Color(hex: 0x333333)

    /// Divider color (#2A2A2A)
    static let divider = Color(hex: 0x2A2A2A)

    /// Selected state background with accent tint
    static let selectedBackground = accent.opacity(0.15)

    // MARK: - Gradients

    /// Primary button gradient
    static let buttonGradient = LinearGradient(
        colors: [accent, accent.opacity(0.8)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Gold highlight gradient
    static let goldGradient = LinearGradient(
        colors: [gold, Color(hex: 0xFFA500)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Card subtle gradient overlay
    static let cardGradient = LinearGradient(
        colors: [cardBackground, Color(hex: 0x151515)],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Color Extension for Hex Values

extension Color {
    /// Initialize a Color from a hex integer value (e.g., 0x0D0D0D)
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - View Modifiers

extension View {
    /// Apply the standard card background style
    func cardStyle() -> some View {
        self
            .background(Theme.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
    }

    /// Apply the elevated card style with shadow
    func elevatedCardStyle() -> some View {
        self
            .background(Theme.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    /// Apply the standard dark background
    func darkBackground() -> some View {
        self.background(Theme.background)
    }
}

// MARK: - Preview

#Preview("Theme Colors") {
    ScrollView {
        VStack(spacing: 24) {
            // Background Colors
            VStack(alignment: .leading, spacing: 8) {
                Text("Backgrounds")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 12) {
                    colorSwatch(Theme.background, "Primary")
                    colorSwatch(Theme.cardBackground, "Card")
                    colorSwatch(Theme.elevatedBackground, "Elevated")
                }
            }

            // Accent Colors
            VStack(alignment: .leading, spacing: 8) {
                Text("Accents")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 12) {
                    colorSwatch(Theme.accent, "Accent")
                    colorSwatch(Theme.gold, "Gold")
                    colorSwatch(Theme.danger, "Danger")
                    colorSwatch(Theme.warning, "Warning")
                }
            }

            // Text Colors
            VStack(alignment: .leading, spacing: 8) {
                Text("Text")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 12) {
                    colorSwatch(Theme.textPrimary, "Primary")
                    colorSwatch(Theme.textSecondary, "Secondary")
                    colorSwatch(Theme.textMuted, "Muted")
                }
            }

            // Status Colors
            VStack(alignment: .leading, spacing: 8) {
                Text("Status")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 12) {
                    colorSwatch(Theme.live, "Live")
                    colorSwatch(Theme.scheduled, "Scheduled")
                    colorSwatch(Theme.finalStatus, "Final")
                }
            }

            // Card Styles
            VStack(alignment: .leading, spacing: 8) {
                Text("Card Styles")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                Text("Standard Card")
                    .foregroundStyle(Theme.textPrimary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .cardStyle()

                Text("Elevated Card")
                    .foregroundStyle(Theme.textPrimary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .elevatedCardStyle()
            }
        }
        .padding()
    }
    .background(Theme.background)
}

@ViewBuilder
private func colorSwatch(_ color: Color, _ name: String) -> some View {
    VStack(spacing: 4) {
        RoundedRectangle(cornerRadius: 8)
            .fill(color)
            .frame(width: 60, height: 60)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.border, lineWidth: 1)
            )
        Text(name)
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
    }
}
