import SwiftUI

private func watchTimeText(for date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}

private func watchCategoryMatches(_ category: WatchMealCategory, itemCategoryID: String?, itemCategoryTitle: String) -> Bool {
    if itemCategoryID == category.id {
        return true
    }

    return itemCategoryTitle.compare(
        category.title,
        options: [.caseInsensitive, .diacriticInsensitive]
    ) == .orderedSame
}

private func watchCategoryItems(in snapshot: WatchTodaySnapshot, category: WatchMealCategory) -> [WatchMealItemSummary] {
    let baseItems: [WatchMealItemSummary]

    if !snapshot.mealItems.isEmpty {
        baseItems = snapshot.mealItems
    } else {
        baseItems = snapshot.meals.map { meal in
            WatchMealItemSummary(
                id: meal.id,
                mealID: meal.id,
                itemID: nil,
                title: meal.title,
                subtitle: nil,
                categoryID: meal.categoryID,
                categoryTitle: meal.categoryTitle,
                calories: meal.calories,
                scheduledAt: meal.scheduledAt
            )
        }
    }

    return baseItems.filter {
        watchCategoryMatches(category, itemCategoryID: $0.categoryID, itemCategoryTitle: $0.categoryTitle)
    }
}

struct MealsOverviewView: View {
    @EnvironmentObject private var sessionManager: WatchSessionManager

    private var snapshot: WatchTodaySnapshot { sessionManager.todaySnapshot }

    private func mealItemCount(for category: WatchMealCategory) -> Int {
        watchCategoryItems(in: snapshot, category: category).count
    }

    private var displayedMealCategories: [WatchMealCategory] {
        snapshot.mealCategories
    }

    var body: some View {
        NavigationStack {
            List {
                if !snapshot.hasData {
                    Section {
                        Text("watch.sync.open_phone_diary")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("today.meals.title") {
                    if displayedMealCategories.isEmpty {
                        Text("watch.sync.open_phone_categories")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(displayedMealCategories) { category in
                            NavigationLink {
                                MealCategoryQuickAddView(category: category)
                            } label: {
                                MealCategoryDestinationRow(
                                    category: category,
                                    mealCount: mealItemCount(for: category)
                                )
                            }
                        }
                    }
                }

                if !sessionManager.isPhoneReachable {
                    Section {
                        Text("watch.sync.actions_pending")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("today.meals.title")
        }
    }
}

private struct MealCategoryDestinationRow: View {
    let category: WatchMealCategory
    let mealCount: Int

    private var summaryText: String? {
        guard mealCount > 0 else { return nil }
        return "\(mealCount) \(NSLocalizedString("today.stats.items_suffix", comment: "Items suffix"))"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: category.symbolName)
                .foregroundStyle(.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)

                if let summaryText {
                    Text(summaryText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()


            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct MealCategoryQuickAddView: View {
    @EnvironmentObject private var sessionManager: WatchSessionManager

    let category: WatchMealCategory

    @State private var lastActionMessage: String?
    @State private var feedbackTrigger = 0

    private var snapshot: WatchTodaySnapshot { sessionManager.todaySnapshot }

    private var categoryItems: [WatchMealItemSummary] {
        watchCategoryItems(in: snapshot, category: category)
    }

    private var categoryCalories: Int {
        categoryItems.reduce(0) { $0 + $1.calories }
    }

    private func delete(_ item: WatchMealItemSummary) {
        guard let mealID = item.mealID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !mealID.isEmpty else {
            return
        }

        if let itemID = item.itemID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !itemID.isEmpty {
            sessionManager.deleteMealItem(mealID: mealID, itemID: itemID)
            lastActionMessage = String(format: NSLocalizedString("watch.feedback.removed_item", comment: "Item removed feedback"), item.title)
        } else {
            sessionManager.deleteMeal(mealID: mealID)
            lastActionMessage = String(format: NSLocalizedString("watch.feedback.deleted_item", comment: "Meal deleted feedback"), item.title)
        }

        feedbackTrigger += 1
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    MealCategoryAddView(category: category) { loggedTitle in
                        lastActionMessage = String(
                            format: NSLocalizedString("watch.feedback.added_to_category", comment: "Item added feedback"),
                            category.title,
                            loggedTitle
                        )
                        feedbackTrigger += 1
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("watch.action.add")
                                .font(.headline)
                            Text("watch.add.subtitle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Section("today.stats.summary.title") {
                SummaryMetricRow(titleKey: "settings.widget.metric.calories", value: String(format: NSLocalizedString("today.kcal_value", comment: "Calories value"), categoryCalories))
                SummaryMetricRow(titleKey: "addmeal.section.items", value: "\(categoryItems.count)")
            }

            Section("addmeal.section.items") {
                if categoryItems.isEmpty {
                    Text("watch.empty.no_items_yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(categoryItems) { item in
                        CurrentMealItemRow(item: item) {
                            delete(item)
                        }
                    }
                }
            }

            if let lastActionMessage {
                Section {
                    Text(lastActionMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !sessionManager.isPhoneReachable {
                Section {
                    Text("watch.sync.process_later")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(category.title)
        .sensoryFeedback(.impact(weight: .medium), trigger: feedbackTrigger)
    }
}

private struct SummaryMetricRow: View {
    let titleKey: String
    let value: String

    var body: some View {
        HStack {
            Text(LocalizedStringKey(titleKey))
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CurrentMealItemRow: View {
    let item: WatchMealItemSummary
    let onDelete: () -> Void

    private var detailText: String {
        let subtitle = item.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detailParts = [subtitle, watchTimeText(for: item.scheduledAt)]
            .compactMap { value -> String? in
                guard let value,
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return value
            }
        return detailParts.joined(separator: " • ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)

                if !detailText.isEmpty {
                    Text(detailText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                Text("\(item.calories)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)

                if item.mealID != nil {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: item.itemID == nil ? "trash" : "minus.circle")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct MealCategoryAddView: View {
    @EnvironmentObject private var sessionManager: WatchSessionManager
    @Environment(\.dismiss) private var dismiss

    let category: WatchMealCategory
    let onItemLogged: (String) -> Void

    private var snapshot: WatchTodaySnapshot { sessionManager.todaySnapshot }

    private var hasQuickAddItems: Bool {
        !snapshot.mealTemplates.isEmpty || !snapshot.recipes.isEmpty || !snapshot.products.isEmpty
    }

    var body: some View {
        List {
            if hasQuickAddItems {
                QuickAddSection(
                    titleKey: "watch.section.saved_meals",
                    emptyTitleKey: "recipes.saved_meals.empty.title",
                    items: snapshot.mealTemplates,
                    action: { itemID, itemTitle in
                        sessionManager.logMealTemplate(itemID, mealCategoryID: category.id)
                        onItemLogged(itemTitle)
                        dismiss()
                    }
                )

                QuickAddSection(
                    titleKey: "recipes.title",
                    emptyTitleKey: "recipes.empty.title",
                    items: snapshot.recipes,
                    action: { itemID, itemTitle in
                        sessionManager.logRecipe(itemID, mealCategoryID: category.id)
                        onItemLogged(itemTitle)
                        dismiss()
                    }
                )

                QuickAddSection(
                    titleKey: "products.title",
                    emptyTitleKey: "products.empty.title",
                    items: snapshot.products,
                    action: { itemID, itemTitle in
                        sessionManager.logProduct(itemID, mealCategoryID: category.id)
                        onItemLogged(itemTitle)
                        dismiss()
                    }
                )
            } else {
                Section {
                    Text("watch.empty.no_saved_content")
                        .foregroundStyle(.secondary)
                }
            }

            if !sessionManager.isPhoneReachable {
                Section {
                    Text("watch.sync.process_later")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("watch.action.add")
    }
}

private struct QuickAddSection: View {
    let titleKey: String
    let emptyTitleKey: String
    let items: [WatchQuickAddItem]
    let action: (String, String) -> Void

    var body: some View {
        Section(LocalizedStringKey(titleKey)) {
            if items.isEmpty {
                Text(LocalizedStringKey(emptyTitleKey))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    QuickLogItemRow(item: item) {
                        action(item.id, item.title)
                    }
                }
            }
        }
    }
}

private struct QuickLogItemRow: View {
    let item: WatchQuickAddItem

    let onAdd: () -> Void

    private var subtitleText: String? {
        if item.calories > 0 {
            return String(format: NSLocalizedString("today.kcal_value", comment: "Calories value"), item.calories)
        }

        let trimmedSubtitle = item.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSubtitle.isEmpty ? nil : trimmedSubtitle
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)

                if let subtitleText {
                    Text(subtitleText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Button(action: onAdd) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.18))

                        Image(systemName: "plus")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.accent)
                    }
                    .frame(width: 58, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: NSLocalizedString("watch.accessibility.add_item", comment: "Accessibility label for add action"), item.title))
            }
        }
    }
}
