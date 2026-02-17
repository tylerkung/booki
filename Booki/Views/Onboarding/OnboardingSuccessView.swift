import SwiftUI

/// Success screen (Step 5)
/// Confirms onboarding completion with a celebration
struct OnboardingSuccessView: View {

    // MARK: - Properties

    let onComplete: () -> Void

    // MARK: - State

    @State private var showCheckmarks: [Bool] = [false, false, false]
    @State private var showButton: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Celebration Icon
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.bottom, 32)

            // Headline
            Text("Your book is ready")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, 40)

            // Checklist
            VStack(alignment: .leading, spacing: 20) {
                ChecklistItem(
                    title: "Book configured",
                    isComplete: showCheckmarks[0]
                )

                ChecklistItem(
                    title: "Players added",
                    isComplete: showCheckmarks[1]
                )

                ChecklistItem(
                    title: "Games imported",
                    isComplete: showCheckmarks[2]
                )
            }
            .padding(.horizontal, 40)

            Spacer()

            // CTA Button
            if showButton {
                Button(action: onComplete) {
                    Text("Go to Dashboard")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.backgroundGradient)
        .onAppear {
            animateCheckmarks()
        }
    }

    // MARK: - Animation

    private func animateCheckmarks() {
        // Staggered animation for checkmarks
        for index in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.3 + 0.2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    showCheckmarks[index] = true
                }
            }
        }

        // Show button after checkmarks
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showButton = true
            }
        }
    }
}

// MARK: - Checklist Item

private struct ChecklistItem: View {
    let title: String
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isComplete ? Theme.accent : Theme.elevatedBackground)
                    .frame(width: 32, height: 32)

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.background)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Text(title)
                .font(.body)
                .foregroundStyle(isComplete ? Theme.textPrimary : Theme.textMuted)
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingSuccessView(onComplete: { print("Complete") })
}
