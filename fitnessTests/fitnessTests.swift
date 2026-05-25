import XCTest
@testable import fitness

final class fitnessTests: XCTestCase {
    func testMetEstimatorUsesBodyWeightAndConservativeEngineEstimate() {
        let template = ExerciseTemplate(
            name: "Cycle",
            metValue: 6,
            intensity: .moderate,
            equipment: "Bodyweight / No equipment",
            instructions: "Pedal steadily.",
            safetyCue: "Reduce effort when needed.",
            isLowImpact: true,
            sourceProvider: "Test"
        )

        let calories = METCalorieEstimator()
            .estimateCalories(template: template, minutes: 30, bodyWeightPounds: 150)

        XCTAssertGreaterThan(calories, 180)
        XCTAssertLessThan(calories, 230)
    }

    func testRecommendationUsesRecoveryWhenTargetAlreadyMet() async {
        let engine = WorkoutRecommendationEngine(catalog: MockExerciseCatalogProvider())
        let input = RecommendationInput(
            targetCalories: 300,
            availableMinutes: 30,
            preferredIntensity: .high,
            activeEnergyBurned: 450,
            bodyWeightPounds: 160,
            recentSessions: [],
            availableEquipment: "Bodyweight / No equipment",
            healthKitAvailable: true
        )

        let plan = await engine.recommend(input: input)

        XCTAssertEqual(plan.intensity, .low)
        XCTAssertTrue(plan.title.localizedCaseInsensitiveContains("recovery"))
        XCTAssertTrue(plan.safetyNotes.contains { $0.localizedCaseInsensitiveContains("met today's calorie target") })
    }

    func testRecommendationIncludesWarmupCooldownAndSafetyNotes() async {
        let engine = WorkoutRecommendationEngine(catalog: MockExerciseCatalogProvider())
        let input = RecommendationInput(
            targetCalories: 600,
            availableMinutes: 40,
            preferredIntensity: .moderate,
            activeEnergyBurned: 100,
            bodyWeightPounds: nil,
            recentSessions: [],
            availableEquipment: "Dumbbells & Bench only",
            healthKitAvailable: false
        )

        let plan = await engine.recommend(input: input)

        XCTAssertEqual(plan.exercises.first?.name, "Warm-Up")
        XCTAssertEqual(plan.exercises.last?.name, "Cooldown")
        XCTAssertTrue(plan.safetyNotes.contains { $0.localizedCaseInsensitiveContains("pain") })
        XCTAssertTrue(plan.safetyNotes.contains { $0.localizedCaseInsensitiveContains("HealthKit") })
    }

    func testRecentSessionGetsNoveltyPenalty() async {
        let engine = WorkoutRecommendationEngine(catalog: MockExerciseCatalogProvider())
        let base = RecommendationInput(
            targetCalories: 500,
            availableMinutes: 35,
            preferredIntensity: .high,
            activeEnergyBurned: 0,
            bodyWeightPounds: 170,
            recentSessions: [],
            availableEquipment: "Bodyweight / No equipment",
            healthKitAvailable: true
        )

        let firstPlan = await engine.recommend(input: base)
        let firstMainBlock = firstPlan.exercises.dropFirst().first?.name ?? ""
        var repeated = base
        repeated.recentSessions = [
            WorkoutSessionSummary(
                title: firstMainBlock,
                completedAt: Date(),
                durationMinutes: 30,
                estimatedCalories: 250,
                intensity: .high
            )
        ]

        let secondPlan = await engine.recommend(input: repeated)
        let secondMainBlock = secondPlan.exercises.dropFirst().first?.name ?? ""

        XCTAssertNotEqual(firstMainBlock, "")
        XCTAssertNotEqual(firstMainBlock, secondMainBlock)
    }
}
