import SwiftUI

/// A rounded rectangle placeholder with shimmer animation
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 20
    var cornerRadius: CGFloat = 6

    @State private var translate: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.elevatedBackground)
            .frame(width: width, height: height)
            .overlay(
                GeometryReader { geo in
                    let bandWidth = geo.size.width * 0.5
                    let travel = geo.size.width + bandWidth

                    LinearGradient(
                        colors: [.clear, .white.opacity(0.12), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: bandWidth)
                    .offset(x: translate ? travel : -bandWidth)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    translate = true
                }
            }
    }
}
