import Foundation
import SwiftUI

@MainActor
final class RecommendationViewModel: ObservableObject {
    @Published var targetCalories: Double = 500
    @Published var availableMinutes: Int = 30
    @Published var preferredIntensity: WorkoutIntensity = .moderate
    @Published var availableEquipment: String = "Bodyweight / No equipment"
    @Published var bodyWeightPounds: Double?
    @Published var plan: WorkoutPlan?
    @Published var recentSessions: [WorkoutSessionSummary] = []
    @Published var isLoading = false

    private var engine: WorkoutRecommendationEngine
    private let store: RecommendationStoring

    init(
        store: RecommendationStoring = FileRecommendationStore()
    ) {
        self.store = store
        self.engine = Self.buildEngine()
        let cache = store.loadCache()
        self.recentSessions = Array(cache.completedSessions.prefix(5))
        self.plan = cache.recommendations.first
    }

    /// Call to force engine rebuild (e.g. if provider needs refresh, though Wger doesn't usually need it)
    func rebuildEngine() {
        engine = Self.buildEngine()
    }



    func refresh(snapshot: HealthSnapshot) {
        isLoading = true
        targetCalories = snapshot.calGoal
        
        Task {
            let input = RecommendationInput(
                targetCalories: targetCalories,
                availableMinutes: availableMinutes,
                preferredIntensity: preferredIntensity,
                activeEnergyBurned: snapshot.calories,
                bodyWeightPounds: bodyWeightPounds,
                recentSessions: recentSessions,
                availableEquipment: availableEquipment,
                healthKitAvailable: snapshot.connectionStatus == .connected
            )

            let nextPlan = await engine.recommend(input: input)
            await MainActor.run {
                plan = nextPlan
                persist(nextPlan, snapshot: snapshot)
                isLoading = false
            }
        }
    }

    func markCompleted() {
        guard let plan else { return }
        let summary = WorkoutSessionSummary(
            title: plan.title,
            completedAt: Date(),
            durationMinutes: plan.durationMinutes,
            estimatedCalories: plan.estimatedCalories,
            intensity: plan.intensity
        )
        recentSessions.insert(summary, at: 0)
        recentSessions = Array(recentSessions.prefix(5))
        store.saveCompletedSession(summary)
    }

    private func persist(_ plan: WorkoutPlan, snapshot: HealthSnapshot) {
        let target = DailyFitnessTarget(
            date: Date(),
            targetCalories: snapshot.calGoal,
            stepGoal: snapshot.stepGoal
        )
        store.saveRecommendation(plan, target: target)
    }

    nonisolated private static func buildEngine() -> WorkoutRecommendationEngine {
        return WorkoutRecommendationEngine(
            catalog: HybridExerciseCatalogProvider(remote: WgerExerciseCatalogProvider()),
            estimator: METCalorieEstimator()
        )
    }
}

