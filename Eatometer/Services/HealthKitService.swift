import Foundation
import HealthKit

/// Profile values Eatometer can pre-fill from the Health app.
struct HealthProfileSnapshot: Equatable {
    var ageYears: Int?
    var biologicalSex: EatometerBiologicalSex?
    var heightCentimeters: Int?
    var weightKilograms: Int?

    var isEmpty: Bool {
        ageYears == nil && biologicalSex == nil && heightCentimeters == nil && weightKilograms == nil
    }
}

/// Thin wrapper over HealthKit.
///
/// Reads the characteristics used to size the initial calorie plan and writes
/// back what the user logs. Everything degrades gracefully: on a device without
/// HealthKit, or when permission is denied, the calls simply do nothing.
@MainActor
final class HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()

    /// The reconcile currently in flight, if any.
    ///
    /// Reconciling is delete-then-write with an await in the middle, so two of
    /// them running at once interleave: both delete, then both write, and the
    /// day ends up counted twice — or one delete lands after the other's write
    /// and the day comes out empty. Tapping `+` twice in the water sheet is
    /// exactly that. Chaining makes them queue instead.
    private var pendingSync: Task<Void, Never>?

    private init() {}

    /// Runs `work` after whatever reconcile is already going.
    private func serialized(_ work: @escaping @MainActor () async -> Void) async {
        let previous = pendingSync
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        pendingSync = task
        await task.value
        // Released once it is the tail of the chain, so the singleton does not
        // hold the last reconcile for the life of the app.
        if pendingSync == task { pendingSync = nil }
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Types

    /// Read from Health: sex, height, weight, activity (via date of birth for age).
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) { types.insert(sex) }
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { types.insert(dob) }
        if let height = HKObjectType.quantityType(forIdentifier: .height) { types.insert(height) }
        if let weight = HKObjectType.quantityType(forIdentifier: .bodyMass) { types.insert(weight) }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        return types
    }

    /// Written to Health: calories, macros, water and a few micronutrients.
    private var writeTypes: Set<HKSampleType> {
        let identifiers: [HKQuantityTypeIdentifier] = [
            .dietaryEnergyConsumed,
            .dietaryProtein,
            .dietaryCarbohydrates,
            .dietaryFatTotal,
            .dietaryWater,
            .dietaryFiber,
            .dietarySugar,
            .dietarySodium,
            .dietaryMagnesium
        ]
        return Set(identifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) })
    }

    // MARK: - Authorization

    /// Shows the system permission sheet. Returns `false` when HealthKit is
    /// unavailable or the request itself fails — note that a user declining
    /// still reports success, which is how HealthKit is designed.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }

        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            return true
        } catch {
            return false
        }
    }

    /// Read-only request used by onboarding: the sheet then lists sex, height,
    /// weight and activity instead of the nutrients we only ever write.
    @discardableResult
    func requestReadAuthorization() async -> Bool {
        guard isAvailable else { return false }

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            return false
        }
    }

    /// True when at least one of the written types has been granted, i.e. the
    /// user has actually approved something.
    var hasAnyWriteAuthorization: Bool {
        guard isAvailable else { return false }
        return writeTypes.contains { store.authorizationStatus(for: $0) == .sharingAuthorized }
    }

    // MARK: - Reading the profile

    func readProfile() async -> HealthProfileSnapshot {
        guard isAvailable else { return HealthProfileSnapshot() }

        var snapshot = HealthProfileSnapshot()
        snapshot.biologicalSex = readBiologicalSex()
        snapshot.ageYears = readAgeYears()

        if let heightMeters = await readMostRecentQuantity(.height, unit: .meter()) {
            snapshot.heightCentimeters = Int((heightMeters * 100).rounded())
        }
        if let weightKilograms = await readMostRecentQuantity(.bodyMass, unit: .gramUnit(with: .kilo)) {
            snapshot.weightKilograms = Int(weightKilograms.rounded())
        }

        return snapshot
    }

    private func readBiologicalSex() -> EatometerBiologicalSex? {
        guard let sex = try? store.biologicalSex().biologicalSex else { return nil }
        switch sex {
        case .female: return .female
        case .male: return .male
        case .other: return .other
        default: return nil
        }
    }

    private func readAgeYears() -> Int? {
        guard let components = try? store.dateOfBirthComponents(),
              let birthDate = Calendar.current.date(from: components) else {
            return nil
        }
        let years = Calendar.current.dateComponents([.year], from: birthDate, to: .now).year
        guard let years, years > 0, years < 130 else { return nil }
        return years
    }

    private func readMostRecentQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    // MARK: - Writing

    private static let nutritionTypes: [(HKQuantityTypeIdentifier, HKUnit)] = [
        (.dietaryEnergyConsumed, .kilocalorie()),
        (.dietaryProtein, .gram()),
        (.dietaryCarbohydrates, .gram()),
        (.dietaryFatTotal, .gram())
    ]

    /// Makes a day in Health say what the diary says.
    ///
    /// Written as replace rather than add because HealthKit samples are
    /// additive and anonymous to us: once "450 kcal" is in there, deleting the
    /// meal it came from leaves nothing to subtract it from. Adding only the
    /// increase — which is what this used to do — meant a meal edited downwards
    /// or thrown away kept its calories in Health for good.
    ///
    /// Clearing the day and writing the totals again is also self-correcting: a
    /// write lost to a crash, or a figure that drifted for any other reason,
    /// is right again after the next change to that day.
    func replaceNutrition(
        on day: Date,
        calories: Int,
        protein: Int,
        carbs: Int,
        fat: Int
    ) async {
        guard isAvailable else { return }

        await serialized { [self] in
            let values = [calories, protein, carbs, fat]
            var samples: [HKQuantitySample] = []

            for (index, entry) in Self.nutritionTypes.enumerated() {
                await deleteOwnSamples(entry.0, on: day)
                samples.append(contentsOf: quantitySample(
                    entry.0,
                    unit: entry.1,
                    value: Double(values[index]),
                    date: startOfDay(day)
                ))
            }

            guard !samples.isEmpty else { return }
            try? await store.save(samples)
        }
    }

    /// Same bargain as nutrition: water can be taken back off the day in the
    /// app, so the day is rewritten rather than topped up.
    func replaceWater(on day: Date, milliliters: Int) async {
        guard isAvailable else { return }

        await serialized { [self] in
            await deleteOwnSamples(.dietaryWater, on: day)

            let samples = quantitySample(
                .dietaryWater,
                unit: .literUnit(with: .milli),
                value: Double(milliliters),
                date: startOfDay(day)
            )
            guard !samples.isEmpty else { return }
            try? await store.save(samples)
        }
    }

    /// Removes what this app wrote for one day, and nothing else.
    ///
    /// `deleteObjects(of:predicate:)` only ever removes samples saved by the
    /// calling app, which is exactly the rule wanted here: a figure typed
    /// straight into the Health app, or written by another tracker, belongs to
    /// whoever put it there.
    private func deleteOwnSamples(_ identifier: HKQuantityTypeIdentifier, on day: Date) async {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier),
              store.authorizationStatus(for: type) == .sharingAuthorized else { return }

        let start = startOfDay(day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate]
        )

        _ = try? await store.deleteObjects(of: type, predicate: predicate)
    }

    /// Samples are stamped at the start of the day rather than at the moment of
    /// the meal. The diary reconciles a whole day at a time, so a per-meal
    /// timestamp would be a detail this app can no longer honour — and a wrong
    /// time is worse than an obviously nominal one.
    private func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func quantitySample(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        value: Double,
        date: Date
    ) -> [HKQuantitySample] {
        guard value > 0,
              let type = HKObjectType.quantityType(forIdentifier: identifier),
              store.authorizationStatus(for: type) == .sharingAuthorized else {
            return []
        }

        return [
            HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: value),
                start: date,
                end: date
            )
        ]
    }
}
