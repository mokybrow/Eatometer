import SwiftUI

/// A person, drawn the same way here as in Financium: one initial, in the
/// secondary label colour, on a neutral rounded square.
///
/// The avatar used to carry a chosen background colour, an optional emoji, and
/// up to two initials. That is more expression than a list of names needs — the
/// colour competed with the tinted content beside it, and the emoji made two
/// people's avatars hard to tell apart at 34pt. Kept deliberately quiet so the
/// name next to it does the identifying.
///
/// `appearance` is still taken so callers do not all have to change; it no
/// longer affects what is drawn.
struct ProfileAvatarView: View {
    let username: String
    let appearance: ProfileAppearance
    let size: CGFloat

    /// Corner radius as a fraction of the side, and monogram size likewise.
    ///
    /// Both are ratios rather than fixed points, so a 34pt avatar in the sidebar
    /// and a 108pt one in the profile are the same drawing at two sizes. The
    /// numbers are Financium's: 28 and 44 points at a side of 108.
    static let cornerRatio: CGFloat = 28.0 / 108.0
    private static let monogramRatio: CGFloat = 44.0 / 108.0

    /// The avatar's outline, so a ring or a badge drawn around one can be cut to
    /// the same shape instead of guessing at it.
    static func shape(size: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: max(size, 1) * cornerRatio, style: .continuous)
    }

    private var resolvedSize: CGFloat {
        let candidate = size.isFinite ? size : 44
        return max(candidate, 1)
    }

    /// One letter, not two.
    ///
    /// Two initials need a name and a surname, which most accounts here do not
    /// have — "MP" for one person next to "M" for another reads as a different
    /// kind of thing rather than as the same thing with less information.
    private var initial: String {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    var body: some View {
        Text(initial)
            .font(.system(size: resolvedSize * Self.monogramRatio, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: resolvedSize, height: resolvedSize)
            .background(EOTheme.Palette.controlFill, in: Self.shape(size: resolvedSize))
    }
}
