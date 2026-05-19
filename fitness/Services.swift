// Services.swift — HealthKitService only (no AI/HTTP calls)
import Foundation
import HealthKit

class HealthKitService {
    private let store = HKHealthStore()

    func requestAuth(_ cb: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { cb(false); return }
        let read: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        ]
        store.requestAuthorization(toShare: [], read: read) { ok, _ in
            DispatchQueue.main.async { cb(ok) }
        }
    }

    func fetchSteps(_ cb: @escaping (Double) -> Void) {
        querySum(.stepCount, unit: .count(), cb: cb)
    }
    func fetchCalories(_ cb: @escaping (Double) -> Void) {
        querySum(.activeEnergyBurned, unit: .kilocalorie(), cb: cb)
    }
    func fetchHR(_ cb: @escaping (Double) -> Void) {
        let t = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let s = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let q = HKSampleQuery(sampleType: t, predicate: nil, limit: 1, sortDescriptors: [s]) { _, s, _ in
            let v = (s?.first as? HKQuantitySample)?
                .quantity.doubleValue(for: HKUnit(from: "count/min")) ?? 72
            DispatchQueue.main.async { cb(v) }
        }
        store.execute(q)
    }

    private func querySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                          cb: @escaping (Double) -> Void) {
        let t     = HKQuantityType.quantityType(forIdentifier: id)!
        let start = Calendar.current.startOfDay(for: Date())
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date(),
                                                options: .strictStartDate)
        let q = HKStatisticsQuery(quantityType: t, quantitySamplePredicate: pred,
                                  options: .cumulativeSum) { _, r, _ in
            DispatchQueue.main.async { cb(r?.sumQuantity()?.doubleValue(for: unit) ?? 0) }
        }
        store.execute(q)
    }
}
