import SwiftUI

/// Custom numeric keypad for stake entry, replacing the iOS system keyboard
/// US-009: Build custom numeric keypad component
struct NumericKeypadView: View {
    @Binding var text: String
    var onValueChanged: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            // Row 1: 1, 2, 3, DEL
            HStack(spacing: 8) {
                digitKey("1")
                digitKey("2")
                digitKey("3")
                actionKey("DEL", systemImage: "delete.left") { deleteLast() }
            }
            // Row 2: 4, 5, 6, +$5
            HStack(spacing: 8) {
                digitKey("4")
                digitKey("5")
                digitKey("6")
                quickStakeKey(5)
            }
            // Row 3: 7, 8, 9, +$10
            HStack(spacing: 8) {
                digitKey("7")
                digitKey("8")
                digitKey("9")
                quickStakeKey(10)
            }
            // Row 4: ., 0, +$25, +$50
            HStack(spacing: 8) {
                digitKey(".")
                digitKey("0")
                quickStakeKey(25)
                quickStakeKey(50)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
                .frame(height: 44)
                .background(Theme.elevatedBackground)
                .cornerRadius(Theme.cornerRadiusSmall)
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
                .frame(height: 44)
                .background(Theme.elevatedBackground)
                .cornerRadius(Theme.cornerRadiusSmall)
        }
        .buttonStyle(KeypadButtonStyle())
    }

    @ViewBuilder
    private func quickStakeKey(_ amount: Int) -> some View {
        Button {
            addQuickStake(amount)
        } label: {
            Text("+$\(amount)")
                .font(Theme.font(size: 14, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Theme.accent.opacity(0.15))
                .cornerRadius(Theme.cornerRadiusSmall)
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
                onValueChanged?(text)
                return
            }
        }

        // Prevent leading zeros (except "0.")
        if text == "0" && digit != "." {
            text = digit
        } else {
            text.append(digit)
        }
        onValueChanged?(text)
    }

    private func deleteLast() {
        guard !text.isEmpty else { return }
        text.removeLast()
        onValueChanged?(text)
    }

    private func addQuickStake(_ amount: Int) {
        let currentValue = Decimal(string: text) ?? 0
        let newValue = currentValue + Decimal(amount)
        // Format: remove trailing zeros but keep up to 2 decimal places
        let number = NSDecimalNumber(decimal: newValue)
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ""
        text = formatter.string(from: number) ?? "\(amount)"
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
