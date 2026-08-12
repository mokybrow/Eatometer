import SwiftUI
import UIKit

/// What a shared thing looks like as a picture.
///
/// A link on its own says nothing until it is opened, and to anyone without the
/// app it never says anything at all. The card carries the answer with it: what
/// the thing is called, what is in it, and what it comes to.
///
/// Deliberately not a screenshot of a screen. A screen is sized for the reader's
/// device and carries chrome that means nothing out of context; this is composed
/// for the one job of being looked at in a chat.
struct ShareCard: Equatable, Hashable {
    /// Name of the thing being shared, at the top.
    let title: String
    /// What kind of thing it is — "Recipe", "Meal plan" — above the title.
    let kind: String
    /// A line under the title: servings, brand, weight. Optional.
    let subtitle: String
    /// What it is made of, in the order it is listed in the app.
    let items: [String]
    /// The figures, already in the units they are shown in.
    let nutrition: NutritionSummary
    /// What the numbers describe: "per serving", "per 100 g", "in total".
    let nutritionCaption: String

    /// How many lines of composition fit before the card stops being glanceable.
    ///
    /// Ten in the taller format, with the type at a readable size. Past that the
    /// card says how many were left rather than listing them, which is more use
    /// than a wall that gets scaled down to nothing.
    static let visibleItemLimit = 10
}

// MARK: - Drawing

struct ShareCardView: View {
    let card: ShareCard

    /// Portrait, 4:5.
    ///
    /// The proportion chats and feeds give the most room to — a landscape card
    /// arrives as a letterbox strip with the type too small to read without
    /// opening it. Fixed rather than sized to content so every card shared looks
    /// like the same object.
    static let width: CGFloat = 1080
    static let height: CGFloat = 1350

    private var visibleItems: [String] {
        Array(card.items.prefix(ShareCard.visibleItemLimit))
    }

    private var hiddenItemCount: Int {
        max(card.items.count - ShareCard.visibleItemLimit, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 44) {
            header
            if !card.items.isEmpty { composition }
            Spacer(minLength: 0)
            macros
            footer
        }
        .padding(64)
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .background(EOTheme.Palette.card)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: card.kind.uppercased())
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(EOTheme.Palette.accent)

            Text(verbatim: card.title)
                .font(.system(size: 78, weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                // Three lines of a 78pt title is already a third of the card; a
                // longer name is trimmed rather than allowed to push the figures
                // off the bottom.
                .lineLimit(3)

            if !card.subtitle.isEmpty {
                Text(verbatim: card.subtitle)
                    .font(.system(size: 38))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var composition: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("share.card.composition")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(visibleItems.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 18) {
                        Circle()
                            .fill(EOTheme.Palette.accent.opacity(0.4))
                            .frame(width: 12, height: 12)
                            .padding(.top, 17)
                        Text(verbatim: item)
                            .font(.system(size: 38))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(2)
                    }
                }

                if hiddenItemCount > 0 {
                    Text(verbatim: String(
                        format: NSLocalizedString("share.card.more_items", comment: "Hidden item count"),
                        hiddenItemCount
                    ))
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 30)
                }
            }
        }
    }

    private var macros: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(verbatim: card.nutritionCaption)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 22),
                    GridItem(.flexible(), spacing: 22)
                ],
                alignment: .leading,
                spacing: 22
            ) {
                macro(
                    value: "\(card.nutrition.calories)",
                    unit: NSLocalizedString("diary.kcal", comment: "Calories unit"),
                    title: NSLocalizedString("addmeal.total.calories", comment: "Calories"),
                    tint: EOTheme.Palette.calories
                )
                macro(
                    value: "\(card.nutrition.protein)",
                    unit: gramsUnit,
                    title: NSLocalizedString("addmeal.total.protein", comment: "Protein"),
                    tint: EOTheme.Palette.protein
                )
                macro(
                    value: "\(card.nutrition.fat)",
                    unit: gramsUnit,
                    title: NSLocalizedString("addmeal.total.fat", comment: "Fat"),
                    tint: EOTheme.Palette.fat
                )
                macro(
                    value: "\(card.nutrition.carbs)",
                    unit: gramsUnit,
                    title: NSLocalizedString("addmeal.total.carbs", comment: "Carbs"),
                    tint: EOTheme.Palette.carbs
                )
            }
        }
    }

    private var gramsUnit: String {
        NSLocalizedString("unit.grams.short", comment: "Grams unit")
    }

    private func macro(value: String, unit: String, title: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: title.uppercased())
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(verbatim: value)
                    .font(.system(size: 82, weight: .bold).monospacedDigit())
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(verbatim: unit)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .leading)
        .padding(.horizontal, 30)
        .padding(.vertical, 28)
        .background(
            tint.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
    }

    private var footer: some View {
        HStack(spacing: 20) {
            Image(AppIconOption.current.previewImageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            Text("share.card.footer")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Rendering

@MainActor
enum ShareCardRenderer {
    /// The last few cards drawn.
    ///
    /// Drawing is the slow part of opening a share sheet, and the same card gets
    /// asked for more than once — the sheet is dismissed and reopened, or the
    /// view redraws and rebuilds its item. A handful of entries covers that
    /// without holding on to bitmaps nobody will ask for again.
    private static var cache: [ShareCard: UIImage] = [:]
    private static var order: [ShareCard] = []
    private static let cacheLimit = 4

    /// Draws the card once, as an image.
    ///
    /// Light mode regardless of the reader's setting: the picture leaves the
    /// device and will be looked at next to whatever the recipient is using, so
    /// a card that came out dark for one person and light for another is a
    /// difference with no meaning behind it.
    static func image(for card: ShareCard) -> UIImage? {
        if let cached = cache[card] { return cached }

        let renderer = ImageRenderer(
            content: ShareCardView(card: card).environment(\.colorScheme, .light)
        )
        // 1080 × 1350 is already a generous picture; at scale 2 it would be
        // 2160 × 2700, which costs four times the drawing and the memory for
        // detail nothing will ever show.
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(
            width: ShareCardView.width,
            height: ShareCardView.height
        )
        renderer.isOpaque = true

        guard let image = renderer.uiImage else { return nil }
        remember(image, for: card)
        return image
    }

    /// Draws the card ahead of time, so the share sheet opens on a picture that
    /// already exists rather than waiting for one.
    static func prepare(_ card: ShareCard) {
        _ = image(for: card)
    }

    private static func remember(_ image: UIImage, for card: ShareCard) {
        cache[card] = image
        order.append(card)
        while order.count > cacheLimit {
            cache.removeValue(forKey: order.removeFirst())
        }
    }
}

#Preview {
    ShareCardView(card: ShareCard(
        title: "Овсянка с ягодами",
        kind: "Рецепт",
        subtitle: "4 порции · 320 г",
        items: ["Овсяные хлопья, 80 г", "Молоко 2,5%, 200 мл", "Черника, 60 г", "Мёд, 15 г"],
        nutrition: NutritionSummary(calories: 412, protein: 14, fat: 9, carbs: 68),
        nutritionCaption: "На порцию"
    ))
}
