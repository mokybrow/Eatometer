import SwiftUI

struct ProfileAvatarView: View {
    let username: String
    let appearance: ProfileAppearance
    let size: CGFloat

    private var resolvedSize: CGFloat {
        let candidate = size.isFinite ? size : 44
        return max(candidate, 1)
    }

    private var initial: String {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }

        let components = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)

        let initials = components.compactMap { component in
            component.first.map { String($0) }
        }
        .joined()
        .uppercased()

        return initials.isEmpty ? String(trimmed.prefix(1)).uppercased() : initials
    }

    private var monogramFontSize: CGFloat {
        initial.count > 1 ? resolvedSize * 0.34 : resolvedSize * 0.46
    }

    var body: some View {
        Circle()
            .fill(appearance.backgroundStyle.color)
            .frame(width: resolvedSize, height: resolvedSize)
            .overlay {
                if let emoji = appearance.emoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: resolvedSize * 0.42))
                } else {
                    Text(initial)
                        .font(appearance.monogramStyle.font(size: monogramFontSize))
                        .foregroundStyle(.primary)
                }
            }
    }
}