import SwiftUI

/// Custom numeric keypad for stake entry, replacing the iOS system keyboard
/// 4x3 grid: [1][2][3] / [4][5][6] / [7][8][9] / [.][0][⌫]
struct NumericKeypadView: View {
    @Binding var text: String
    var onValueChanged: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                digitKey("1")
                digitKey("2")
                digitKey("3")
            }
            HStack(spacing: 6) {
                digitKey("4")
                digitKey("5")
                digitKey("6")
            }
            HStack(spacing: 6) {
                digitKey("7")
                digitKey("8")
                digitKey("9")
            }
            HStack(spacing: 6) {
                digitKey(".")
                digitKey("0")
                actionKey("DEL", systemImage: "delete.left") { deleteLast() }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Key Views

    @ViewBuilder
    private func digitKey(_ digit: String) -> some View {
        Button {
            appendDigit(digit)
        } label: {
            Text(digit)
                .font(Theme.font(size: 20, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Theme.elevatedBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
        }
        .buttonStyle(KeypadButtonStyle())
    }

    @ViewBuilder
    private func actionKey(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Theme.elevatedBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
        }
        .buttonStyle(KeypadButtonStyle())
    }

    // MARK: - Actions

    private func appendDigit(_ digit: String) {
        if digit == "." {
            // Only allow one decimal point
            if text.contains(".") { return }
            // If empty, start with "0."
            if text.isEmpty {
                text = "0."
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onValueChanged?(text)
                return
            }
        }

        // Max 2 decimal places
        if let dotIndex = text.firstIndex(of: ".") {
            let afterDot = text[text.index(after: dotIndex)...]
            if afterDot.count >= 2 && digit != "." { return }
        }

        // Prevent leading zeros (except "0.")
        if text == "0" && digit != "." {
            text = digit
        } else {
            text.append(digit)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onValueChanged?(text)
    }

    private func deleteLast() {
        guard !text.isEmpty else { return }
        text.removeLast()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onValueChanged?(text)
    }
}

// MARK: - Button Style

private struct KeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview("Numeric Keypad") {
    struct PreviewWrapper: View {
        @State private var value = ""
        var body: some View {
            VStack(spacing: 20) {
                Text(value.isEmpty ? "$0.00" : "$\(value)")
                    .font(Theme.title1)
                    .foregroundStyle(Theme.textPrimary)
                NumericKeypadView(text: $value)
            }
            .padding()
            .darkBackground()
        }
    }
    return PreviewWrapper()
}
