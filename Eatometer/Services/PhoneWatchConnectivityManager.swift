import Foundation
import WatchConnectivity
import Combine

@MainActor
final class PhoneWatchConnectivityManager: NSObject, ObservableObject {
    static let shared = PhoneWatchConnectivityManager()

    private weak var diaryService: FoodDiaryService?
    private weak var catalogService: FoodCatalogService?
    private var cancellables = Set<AnyCancellable>()

    private let snapshotKey = "Eatometer.widget.today.snapshot"
    private let sharedDefaults = UserDefaults(suiteName: "group.com.goeatometer.Eatometer.shared")

    func configure(diaryService: FoodDiaryService, catalogService: FoodCatalogService) {
        self.diaryService = diaryService
        self.catalogService = catalogService
        cancellables.removeAll()

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()

        diaryService.objectWillChange
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshAndSendSnapshot()
                }
            }
            .store(in: &cancellables)

        catalogService.objectWillChange
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshAndSendSnapshot()
                }
            }
            .store(in: &cancellables)

        AppSettings.shared.$isWaterTrackingEnabled
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshAndSendSnapshot()
                }
            }
            .store(in: &cancellables)

        refreshAndSendSnapshot()
    }

    private func refreshAndSendSnapshot() {
        diaryService?.refreshWatchSnapshot()
        sendSnapshotToWatch()
    }

    func sendSnapshotToWatch() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else { return }
        guard let data = sharedDefaults?.data(forKey: snapshotKey) else { return }

        do {
            try session.updateApplicationContext(["snapshot": data])
        } catch {
            // Non-critical: watch will get updated on next change
        }
    }
}

// MARK: - WCSessionDelegate

extension PhoneWatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if activationState == .activated {
            Task { @MainActor in
                self.refreshAndSendSnapshot()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncomingPayload(message)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handleIncomingPayload(message)
        replyHandler([:])
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleIncomingPayload(userInfo)
    }

    nonisolated private func handleIncomingPayload(_ payload: [String: Any]) {
        guard let action = payload["action"] as? String else { return }
        let mealCategoryID = (payload["mealCategoryID"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedMealCategoryID = (mealCategoryID?.isEmpty == false) ? mealCategoryID : nil

        switch action {
        case "addWater":
            guard let amount = payload["amount"] as? Int, amount != 0 else { return }
            Task { @MainActor in
                self.diaryService?.addWater(amount, for: .now)
                self.refreshAndSendSnapshot()
            }
        case "logFavoriteProduct", "logProduct":
            guard let productID = payload["productID"] as? String,
                  let id = UUID(uuidString: productID) else { return }
            Task { @MainActor in
                await self.logProduct(id, mealCategoryID: resolvedMealCategoryID)
            }
        case "logRecipe":
            guard let recipeID = payload["recipeID"] as? String,
                  let id = UUID(uuidString: recipeID) else { return }
            Task { @MainActor in
                await self.logRecipe(id, mealCategoryID: resolvedMealCategoryID)
            }
        case "logMealTemplate":
            guard let mealTemplateID = payload["mealTemplateID"] as? String,
                  let id = UUID(uuidString: mealTemplateID) else { return }
            Task { @MainActor in
                await self.logMealTemplate(id, mealCategoryID: resolvedMealCategoryID)
            }
        case "deleteMeal":
            guard let mealID = payload["mealID"] as? String,
                  let id = UUID(uuidString: mealID) else { return }
            Task { @MainActor in
                await self.deleteMeal(id)
            }
        case "deleteMealItem":
            guard let mealID = payload["mealID"] as? String,
                  let id = UUID(uuidString: mealID) else { return }

            let rawItemID = (payload["itemID"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let rawItemID,
               !rawItemID.isEmpty {
                guard let itemID = UUID(uuidString: rawItemID) else { return }
                Task { @MainActor in
                    await self.deleteMealItem(mealID: id, itemID: itemID)
                }
            } else {
                Task { @MainActor in
                    await self.deleteMealItem(mealID: id, itemID: nil)
                }
            }
        default:
            break
        }
    }

    private func logProduct(_ id: UUID, mealCategoryID: String?) async {
        guard let diaryService, let catalogService else { return }
        let product = if let cachedProduct = catalogService.productSummary(id: id) {
            cachedProduct
        } else {
            await catalogService.fetchProductSnapshot(id: id)
        }
        guard let product else { return }

        let selection = product.selectionPayload()
        let item = MealItemEntry(
            id: UUID(),
            name: product.name,
            amount: selection.amount,
            unit: selection.unit,
            note: "",
            servingLabel: selection.servingLabel,
            caloriesPer100g: product.caloriesPer100g,
            proteinPer100g: product.proteinPer100g,
            fatPer100g: product.fatPer100g,
            carbsPer100g: product.carbsPer100g,
            productID: product.id,
            recipeID: nil
        )

        await enqueueWatchItems(
            [item],
            title: product.name,
            note: "",
            nutrition: .zero,
            mealCategoryID: mealCategoryID,
            diaryService: diaryService
        )
    }

    private func logRecipe(_ id: UUID, mealCategoryID: String?) async {
        guard let diaryService, let catalogService else { return }
        let recipe = if let cachedRecipe = catalogService.recipeSummary(id: id) {
            cachedRecipe
        } else {
            await catalogService.fetchRecipeSnapshot(id: id)
        }
        guard let recipe else { return }

        let item = catalogService.makeMealItem(from: recipe)

        await enqueueWatchItems(
            [item],
            title: recipe.title,
            note: "",
            nutrition: .zero,
            mealCategoryID: mealCategoryID,
            diaryService: diaryService
        )
    }

    private func logMealTemplate(_ id: UUID, mealCategoryID: String?) async {
        guard let diaryService, let catalogService else { return }
        let mealTemplate = if let cachedMealTemplate = catalogService.mealTemplateSummary(id: id) {
            cachedMealTemplate
        } else {
            await catalogService.fetchMealTemplateSnapshot(id: id)
        }
        guard let mealTemplate else { return }

        await enqueueWatchItems(
            clonedMealItems(from: mealTemplate.items),
            title: mealTemplate.title,
            note: mealTemplate.details,
            nutrition: mealTemplate.nutrition,
            mealCategoryID: mealCategoryID,
            diaryService: diaryService
        )
    }

    private func enqueueWatchItems(
        _ items: [MealItemEntry],
        title: String,
        note: String,
        nutrition: NutritionSummary,
        mealCategoryID: String?,
        diaryService: FoodDiaryService
    ) async {
        guard !items.isEmpty else { return }

        let context = loggingContext(for: mealCategoryID, diaryService: diaryService)
        let didSave: Bool

        if !context.mealCategoryID.isEmpty,
           var meal = diaryService.latestMeal(in: context.mealCategoryID, on: .now) {
            meal.kind = context.kind
            meal.mealCategoryID = context.mealCategoryID
            meal.items.append(contentsOf: items)
            meal.nutrition = .zero

            if meal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                meal.title = title
            }

            if meal.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                meal.note = note
            }

            didSave = await diaryService.saveMeal(meal)
        } else {
            let meal = MealEntry(
                id: UUID(),
                kind: context.kind,
                mealCategoryID: context.mealCategoryID,
                title: title,
                items: items,
                note: note,
                scheduledAt: context.scheduledAt,
                nutrition: nutrition
            )
            didSave = await diaryService.saveMeal(meal)
        }

        if didSave {
            refreshAndSendSnapshot()
        }
    }

    private func clonedMealItems(from items: [MealItemEntry]) -> [MealItemEntry] {
        items.map { item in
            MealItemEntry(
                id: UUID(),
                name: item.name,
                amount: item.amount,
                unit: item.unit,
                note: item.note,
                servingLabel: item.servingLabel,
                caloriesPer100g: item.caloriesPer100g,
                proteinPer100g: item.proteinPer100g,
                fatPer100g: item.fatPer100g,
                carbsPer100g: item.carbsPer100g,
                productID: item.productID,
                recipeID: item.recipeID
            )
        }
    }

    private func deleteMeal(_ id: UUID) async {
        guard let diaryService else { return }

        let didDelete = await diaryService.deleteMeal(id: id)
        if didDelete {
            refreshAndSendSnapshot()
        }
    }

    private func deleteMealItem(mealID: UUID, itemID: UUID?) async {
        guard let diaryService else { return }

        let didDelete: Bool
        if let itemID {
            didDelete = await diaryService.removeMealItem(mealID: mealID, itemID: itemID, on: .now)
        } else {
            didDelete = await diaryService.deleteMeal(id: mealID)
        }

        if didDelete {
            refreshAndSendSnapshot()
        }
    }

    private func loggingContext(for mealCategoryID: String?, diaryService: FoodDiaryService) -> (kind: MealKind, mealCategoryID: String, scheduledAt: Date) {
        guard let mealCategoryID,
              !mealCategoryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (.inferred(from: .now), "", .now)
        }

        let category = diaryService.category(for: mealCategoryID)
        let scheduledAt = scheduledAt(for: category, on: .now)
        let kind = MealKind(rawValue: category.id) ?? MealKind.inferred(from: scheduledAt)
        return (kind, category.id, scheduledAt)
    }

    private func scheduledAt(for category: MealCategory, on date: Date) -> Date {
        Calendar.current.date(
            bySettingHour: category.preferredHour,
            minute: category.preferredMinute,
            second: 0,
            of: date
        ) ?? date
    }
}
