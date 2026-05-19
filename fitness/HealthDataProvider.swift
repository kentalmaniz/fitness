// HealthDataProvider.swift
// Protocol-based HealthKit abstraction — swap implementations for testing,
// simulation, or future data sources without touching the UI layer.

import Foundation
import HealthKit
import SwiftUI

// MARK: - Status
enum HealthConnectionStatus: Equatable {
    case connected, permissionDenied, unavailable, unknown

    var label: String {
        switch self {
        case .connected:       return "Connected"
        case .permissionDenied: return "Permission Denied"
        case .unavailable:     return "HealthKit Unavailable"
        case .unknown:         return "Not Requested"
        }
    }
    var icon: String {
        switch self {
        case .connected:        return "checkmark.circle.fill"
        case .permissionDenied: return "xmark.circle.fill"
        case .unavailable:      return "minus.circle.fill"
        case .unknown:          return "questionmark.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .connected:        return .teal
        case .permissionDenied: return .red
        case .unavailable:      return .secondary
        case .unknown:          return .amber
        }
    }
}

// MARK: - Snapshot (value type — easy to diff / mock)
struct HealthSnapshot {
    var connectionStatus: HealthConnectionStatus = .unknown
    var steps:            Double = 0
    var calories:         Double = 0
    var heartRate:        Double = 0
    var sleepHours:       Double = 0
    var activeMinutes:    Int    = 0
    var stepGoal:         Int    = 10_000
    var calGoal:          Double = 500

    var calProgress:  Double { calGoal  > 0 ? min(calories / calGoal,        1.0) : 0 }
    var stepProgress: Double { stepGoal > 0 ? min(steps / Double(stepGoal),  1.0) : 0 }
    var overallProgress: Double { (calProgress + stepProgress) / 2.0 }
    var overallPercentage: Int  { Int(overallProgress * 100) }
}

// MARK: - Protocol
// Each concrete type is a self-contained "agent credit" — scoped, replaceable.
protocol HealthDataProviding {
    func requestAuthorization(completion: @escaping (HealthConnectionStatus) -> Void)
    func fetchSnapshot(completion: @escaping (HealthSnapshot) -> Void)
}

// MARK: - ① Live (real HealthKit)
struct LiveHealthDataProvider: HealthDataProviding {
    private let store = HKHealthStore()

    func requestAuthorization(completion: @escaping (HealthConnectionStatus) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.unavailable); return
        }
        let types: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        ]
        store.requestAuthorization(toShare: [], read: types) { ok, _ in
            DispatchQueue.main.async { completion(ok ? .connected : .permissionDenied) }
        }
    }

    func fetchSnapshot(completion: @escaping (HealthSnapshot) -> Void) {
        var snap = HealthSnapshot(connectionStatus: .connected)
        let group = DispatchGroup()

        group.enter()
        querySum(.stepCount, unit: .count()) { snap.steps = $0; group.leave() }

        group.enter()
        querySum(.activeEnergyBurned, unit: .kilocalorie()) { snap.calories = $0; group.leave() }

        group.enter()
        queryLatestHR { snap.heartRate = $0; group.leave() }

        group.enter()
        querySum(.appleExerciseTime, unit: .minute()) { snap.activeMinutes = Int($0); group.leave() }

        group.enter()
        querySleepHours { snap.sleepHours = $0; group.leave() }

        group.notify(queue: .main) { completion(snap) }
    }

    private func querySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                          cb: @escaping (Double) -> Void) {
        let t     = HKQuantityType.quantityType(forIdentifier: id)!
        let start = Calendar.current.startOfDay(for: Date())
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date(),
                                                options: .strictStartDate)
        let q = HKStatisticsQuery(quantityType: t, quantitySamplePredicate: pred,
                                  options: .cumulativeSum) { _, r, _ in
            cb(r?.sumQuantity()?.doubleValue(for: unit) ?? 0)
        }
        store.execute(q)
    }

    private func queryLatestHR(_ cb: @escaping (Double) -> Void) {
        let t = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let s = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let q = HKSampleQuery(sampleType: t, predicate: nil, limit: 1,
                              sortDescriptors: [s]) { _, samples, _ in
            let v = (samples?.first as? HKQuantitySample)?
                .quantity.doubleValue(for: HKUnit(from: "count/min")) ?? 0
            cb(v)
        }
        store.execute(q)
    }

    private func querySleepHours(_ cb: @escaping (Double) -> Void) {
        let t = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let start = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let q = HKSampleQuery(sampleType: t, predicate: pred, limit: HKObjectQueryNoLimit,
                              sortDescriptors: nil) { _, samples, _ in
            let seconds = (samples as? [HKCategorySample] ?? [])
                .filter { sample in
                    sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                        || sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                        || sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                        || sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                }
                .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            cb(seconds / 3600.0)
        }
        store.execute(q)
    }
}

// MARK: - ② Mock (good data — unit tests / previews)
struct MockHealthDataProvider: HealthDataProviding {
    func requestAuthorization(completion: @escaping (HealthConnectionStatus) -> Void) {
        completion(.connected)
    }
    func fetchSnapshot(completion: @escaping (HealthSnapshot) -> Void) {
        completion(HealthSnapshot(
            connectionStatus: .connected,
            steps: 7_234, calories: 387, heartRate: 68,
            sleepHours: 7.4, activeMinutes: 42,
            stepGoal: 10_000, calGoal: 500
        ))
    }
}

// MARK: - ③ Permission Denied (simulate denied state)
struct PermissionDeniedProvider: HealthDataProviding {
    func requestAuthorization(completion: @escaping (HealthConnectionStatus) -> Void) {
        completion(.permissionDenied)
    }
    func fetchSnapshot(completion: @escaping (HealthSnapshot) -> Void) {
        completion(HealthSnapshot(connectionStatus: .permissionDenied))
    }
}

// MARK: - ④ Empty Data (simulate zero / first-launch state)
struct EmptyDataProvider: HealthDataProviding {
    func requestAuthorization(completion: @escaping (HealthConnectionStatus) -> Void) {
        completion(.connected)
    }
    func fetchSnapshot(completion: @escaping (HealthSnapshot) -> Void) {
        completion(HealthSnapshot(
            connectionStatus: .connected,
            steps: 0, calories: 0, heartRate: 0, sleepHours: 0, activeMinutes: 0,
            stepGoal: 10_000, calGoal: 500
        ))
    }
}

// MARK: - DashboardViewModel (provider-injected, scoped)
class DashboardViewModel: ObservableObject {
    @Published var snapshot  = HealthSnapshot()
    @Published var isLoading = false

    private let provider: HealthDataProviding

    /// Inject any provider — defaults to real HealthKit in production.
    init(provider: HealthDataProviding = LiveHealthDataProvider()) {
        self.provider = provider
    }

    func authorize() {
        provider.requestAuthorization { [weak self] status in
            self?.snapshot.connectionStatus = status
            if status == .connected { self?.refresh() }
        }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        provider.fetchSnapshot { [weak self] snap in
            guard let self else { return }
            // Keep report-synced goals when refreshing live data
            var updated        = snap
            updated.calGoal    = self.snapshot.calGoal
            updated.stepGoal   = self.snapshot.stepGoal
            self.snapshot      = updated
            self.isLoading     = false
        }
    }

    /// Call this whenever a new .md report is loaded.
    func syncGoals(calGoal: Double, stepGoal: Int) {
        snapshot.calGoal  = calGoal
        snapshot.stepGoal = stepGoal
    }
}
