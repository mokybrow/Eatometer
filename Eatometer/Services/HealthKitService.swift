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

    private init() {}

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

    /// Saves a nutrition entry. Silently no-ops when sync is off or denied.
    func saveNutrition(
        calories: Int,
        protein: Int,
        carbs: Int,
        fat: Int,
        date: Date = .now
    ) async {
        guard isAvailable else { return }

        var samples: [HKQuantitySample] = []
        samples.append(contentsOf: quantitySample(.dietaryEnergyConsumed, unit: .kilocalorie(), value: Double(calories), date: date))
        samples.append(contentsOf: quantitySample(.dietaryProtein, unit: .gram(), value: Double(protein), date: date))
        samples.append(contentsOf: quantitySample(.dietaryCarbohydrates, unit: .gram(), value: Double(carbs), date: date))
        samples.append(contentsOf: quantitySample(.dietaryFatTotal, unit: .gram(), value: Double(fat), date: date))

        guard !samples.isEmpty else { return }
        try? await store.save(samples)
    }

    func saveWater(milliliters: Int, date: Date = .now) async {
        guard isAvailable, milliliters > 0 else { return }

        let samples = quantitySample(
            .dietaryWater,
            unit: .literUnit(with: .milli),
            value: Double(milliliters),
            date: date
        )
        guard !samples.isEmpty else { return }
        try? await store.save(samples)
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
