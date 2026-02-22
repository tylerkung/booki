import SwiftUI

/// Design tokens for the fun, gamelike sports-betting theme
/// Provides consistent colors, typography, and styling across the app
enum Theme {

    // MARK: - Background Colors

    /// Primary background: deep purple-tinted black for gaming feel
    static let background = Color(hex: 0x0A0A12)

    /// Secondary background: dark with subtle purple tint for cards
    static let cardBackground = Color(hex: 0x14141F)

    /// Tertiary background: slightly lighter for nested elements
    static let elevatedBackground = Color(hex: 0x1E1E2D)

    // MARK: - Accent Colors

    /// Primary accent: electric cyan/teal for energy (#00F5D4)
    static let accent = Color(hex: 0x00F5D4)

    /// Secondary accent: vibrant purple for variety (#9D4EDD)
    static let accentSecondary = Color(hex: 0x9D4EDD)

    /// Tertiary accent: hot pink for highlights (#FF006E)
    static let accentTertiary = Color(hex: 0xFF006E)

    /// Secondary accent: gold/yellow for highlights - now more vibrant
    static let gold = Color(hex: 0xFFE66D)

    /// Danger color: coral red for losses/errors - softer, more gamelike
    static let danger = Color(hex: 0xFF6B6B)

    /// Warning color: warm orange for caution states
    static let warning = Color(hex: 0xFFA94D)

    // MARK: - Text Colors

    /// Primary text: slightly warm white for comfort
    static let textPrimary = Color(hex: 0xF8F8F8)

    /// Secondary text: soft lavender gray
    static let textSecondary = Color(hex: 0xA8A8B8)

    /// Muted text: deeper purple-gray
    static let textMuted = Color(hex: 0x6B6B7B)

    // MARK: - Status Colors

    /// Live indicator: vibrant cyan (matches accent)
    static let live = accent

    /// Scheduled/upcoming: soft blue-purple
    static let scheduled = Color(hex: 0x7B68EE)

    /// Final/completed: muted purple-gray
    static let finalStatus = Color(hex: 0x5C5C6F)

    // MARK: - Bet Result Colors

    /// Win color: matches accent green
    static let win = accent

    /// Loss color: matches danger red
    static let loss = danger

    /// Push color: neutral gray
    static let push = textSecondary

    // MARK: - UI Element Colors

    /// Border color: subtle purple tint
    static let border = Color(hex: 0x2A2A3A)

    /// Divider color: deep purple-black
    static let divider = Color(hex: 0x22222E)

    /// Selected state background with accent tint
    static let selectedBackground = accent.opacity(0.15)

    // MARK: - Corner Radius (more rounded = more fun)

    /// Standard corner radius for cards
    static let cornerRadius: CGFloat = 16

    /// Smaller corner radius for buttons and inner elements
    static let cornerRadiusSmall: CGFloat = 12

    // MARK: - Gradients

    /// Primary button gradient: cyan to purple for energy
    static let buttonGradient = LinearGradient(
        colors: [accent, accentSecondary],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Exciting multi-color gradient for special elements
    static let rainbowGradient = LinearGradient(
        colors: [accent, accentSecondary, accentTertiary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Gold highlight gradient - warmer, more playful
    static let goldGradient = LinearGradient(
        colors: [gold, Color(hex: 0xFFAA00)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Typography

    /// Returns a Space Grotesk font with the given size and weight (display/titles)
    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .semibold, .heavy, .black:
            name = "SpaceGrotesk-Bold"
        case .medium:
            name = "SpaceGrotesk-Medium"
        default:
            name = "SpaceGrotesk-Regular"
        }
        return Font.custom(name, size: size)
    }

    /// Returns an IBM Plex Sans font with the given size and weight (body/reading text)
    static func bodyFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .semibold, .heavy, .black:
            name = "IBMPlexSans-Bold"
        case .medium:
            name = "IBMPlexSans-Medium"
        default:
            name = "IBMPlexSans-Regular"
        }
        return Font.custom(name, size: size)
    }

    /// Space Grotesk with monospaced digits for odds/numbers
    static func monoDigits(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        font(size: size, weight: weight).monospacedDigit()
    }

    // Convenience type scale — Space Grotesk for titles/headlines
    static let largeTitle = font(size: 34, weight: .bold)
    static let title1 = font(size: 28, weight: .bold)
    static let title2 = font(size: 22, weight: .bold)
    static let title3 = font(size: 20, weight: .bold)
    static let headline = font(size: 17, weight: .bold)

    // Convenience type scale — IBM Plex Sans for body/reading text
    static let body = bodyFont(size: 17)
    static let callout = bodyFont(size: 16)
    static let subheadline = bodyFont(size: 15)
    static let footnote = bodyFont(size: 13)
    static let caption = bodyFont(size: 12)
    static let caption2 = bodyFont(size: 11, weight: .medium)

    /// Card gradient: subtle purple depth
    static let cardGradient = LinearGradient(
        colors: [cardBackground, Color(hex: 0x0E0E18)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Background gradient for screens: adds depth
    static let backgroundGradient = LinearGradient(
        colors: [Color(hex: 0x12121A), background],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Glow gradient for selected/active states
    static let glowGradient = RadialGradient(
        colors: [accent.opacity(0.3), accent.opacity(0)],
        center: .center,
        startRadius: 0,
        endRadius: 50
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
    /// Apply the standard card background style with gamelike styling
    func cardStyle() -> some View {
        self
            .background(Theme.cardGradient)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [Theme.border.opacity(0.8), Theme.border.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }

    /// Apply the elevated card style with colored glow
    func elevatedCardStyle() -> some View {
        self
            .background(Theme.cardGradient)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.3), Theme.accentSecondary.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Theme.accent.opacity(0.15), radius: 12, x: 0, y: 4)
            .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
    }

    /// Apply the standard dark background with subtle gradient
    func darkBackground() -> some View {
        self.background(Theme.backgroundGradient)
    }

    /// Apply a glowing border effect for highlighted elements
    func glowingBorder(color: Color = Theme.accent, isActive: Bool = true, cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(color, lineWidth: isActive ? 2 : 0)
            )
            .shadow(color: isActive ? color.opacity(0.5) : .clear, radius: 8, x: 0, y: 0)
    }

    /// Apply accent gradient text
    func gradientText() -> some View {
        self
            .overlay(Theme.buttonGradient)
            .mask(self)
    }
}

// MARK: - Preview

#Preview("Theme Colors") {
    ScrollView {
        VStack(spacing: 24) {
            // Background Colors
            VStack(alignment: .leading, spacing: 8) {
                Text("Backgrounds")
                    .font(Theme.headline)
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
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 12) {
                    colorSwatch(Theme.accent, "Cyan")
                    colorSwatch(Theme.accentSecondary, "Purple")
                    colorSwatch(Theme.accentTertiary, "Pink")
                }
                HStack(spacing: 12) {
                    colorSwatch(Theme.gold, "Gold")
                    colorSwatch(Theme.danger, "Danger")
                    colorSwatch(Theme.warning, "Warning")
                }
            }

            // Text Colors
            VStack(alignment: .leading, spacing: 8) {
                Text("Text")
                    .font(Theme.headline)
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
                    .font(Theme.headline)
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
                    .font(Theme.headline)
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

                Text("Glowing Card")
                    .foregroundStyle(Theme.textPrimary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .cardStyle()
                    .glowingBorder()
            }

            // Gradient Demo
            VStack(alignment: .leading, spacing: 8) {
                Text("Gradients")
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                        .fill(Theme.buttonGradient)
                        .frame(height: 50)
                        .overlay(
                            Text("Button")
                                .font(Theme.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.background)
                        )

                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                        .fill(Theme.rainbowGradient)
                        .frame(height: 50)
                        .overlay(
                            Text("Rainbow")
                                .font(Theme.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                        )
                }
            }
        }
        .padding()
    }
    .darkBackground()
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
            .font(Theme.caption2)
            .foregroundStyle(Theme.textSecondary)
    }
}
