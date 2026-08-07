import SwiftUI

/// Soft prompt shown when the user's weight changed, offering to update the
/// daily calorie target or to dismiss the suggestion.
struct CaloriePlanReviewSheet: View {
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 4)

            Image(systemName: "scalemass.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.appAccent)
                .frame(width: 74, height: 74)
                .background(Color.appAccent.opacity(0.12), in: Circle())

            VStack(spacing: 8) {
                Text("calorie_review.sheet.title")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text("calorie_review.sheet.message")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 4)

            VStack(spacing: 10) {
                Button {
                    onUpdate()
                } label: {
                    Text("calorie_review.sheet.update")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.appAccentReadableText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    onDismiss()
                } label: {
                    Text("calorie_review.sheet.decline")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appPageBackground.ignoresSafeArea())
    }
}
