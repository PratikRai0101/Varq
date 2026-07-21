import SwiftUI

enum PageTurnDirection {
    case forward
    case backward
}

struct PageTurnOverlay: View {
    let direction: PageTurnDirection
    let progress: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(Color.varqTerracotta.opacity(VarqOpacity.pageTurnOverlay))
                .frame(width: proxy.size.width)
                .shadow(
                    color: Color.varqTerracotta.opacity(VarqOpacity.pageTurnShadow),
                    radius: VarqLayout.pageTurnShadowRadius
                )
                .offset(x: horizontalOffset(for: proxy.size.width))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func horizontalOffset(for width: CGFloat) -> CGFloat {
        let remainingDistance = (1 - progress) * width
        switch direction {
        case .forward:
            return remainingDistance
        case .backward:
            return -remainingDistance
        }
    }
}
