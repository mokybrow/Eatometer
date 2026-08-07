import SwiftUI

enum FoodPlaceholderKind {
    case grocery
    case recipe
    case meal
    case favorite
    case habit

    var symbolName: String {
        switch self {
        case .grocery:
            return "carrot.fill"
        case .recipe:
            return "book.closed.fill"
        case .meal:
            return "fork.knife"
        case .favorite:
            return "heart.fill"
        case .habit:
            return "leaf.fill"
        }
    }

    var tint: Color {
        switch self {
        case .grocery:
            return .orange
        case .recipe:
            return .green
        case .meal:
            return .blue
        case .favorite:
            return .secondary
        case .habit:
            return .green
        }
    }
}

struct FoodPlaceholderArtwork: View {
    let kind: FoodPlaceholderKind
    var width: CGFloat = 32
    var height: CGFloat = 32
    var monochrome: Bool = true

    private var resolvedTint: Color {
        monochrome ? .secondary : kind.tint
    }

    private var symbolSize: CGFloat {
        min(width, height) * 0.72
    }

    var body: some View {
        Image(systemName: kind.symbolName)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: symbolSize, weight: .medium))
            .foregroundStyle(resolvedTint)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}
