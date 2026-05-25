import Foundation

enum WorkoutIntensity: String, CaseIterable, Codable, Identifiable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"

    var id: String { rawValue }

    var searchTerms: [String] {
        switch self {
        case .low: return ["mobility", "stretching", "walking", "yoga"]
        case .moderate: return ["strength", "cardio", "cycling", "row"]
        case .high: return ["hiit", "running", "interval", "jump rope"]
        }
    }
}

struct WorkoutSessionSummary: Codable, Equatable {
    var title: String
    var completedAt: Date
    var durationMinutes: Int
    var estimatedCalories: Double
    var intensity: WorkoutIntensity
}

struct RecommendationInput: Codable, Equatable {
    var targetCalories: Double
    var availableMinutes: Int
    var preferredIntensity: WorkoutIntensity
    var activeEnergyBurned: Double
    var bodyWeightPounds: Double?
    var recentSessions: [WorkoutSessionSummary]
    var availableEquipment: String
    var healthKitAvailable: Bool

    var remainingCalories: Double {
        max(0, targetCalories - activeEnergyBurned)
    }
}

struct ExerciseBlock: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var durationMinutes: Int
    var estimatedCalories: Double
    var intensity: WorkoutIntensity
    var instructions: String
    var equipment: String
    var safetyCue: String
}

struct WorkoutPlan: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var estimatedCalories: Double
    var durationMinutes: Int
    var intensity: WorkoutIntensity
    var exercises: [ExerciseBlock]
    var sourceProvider: String
    var safetyNotes: [String]
    var generatedAt: Date = Date()
}

struct ExerciseTemplate: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var metValue: Double
    var intensity: WorkoutIntensity
    var equipment: String
    var instructions: String
    var safetyCue: String
    var isLowImpact: Bool
    var sourceProvider: String
    var fetchedAt: Date = Date()
}

protocol ExerciseCatalogProviding {
    func fetchTemplates(for input: RecommendationInput) async throws -> [ExerciseTemplate]
}

protocol CalorieEstimating {
    func estimateCalories(template: ExerciseTemplate, minutes: Int, bodyWeightPounds: Double?) -> Double
}

struct METCalorieEstimator: CalorieEstimating {
    func estimateCalories(template: ExerciseTemplate, minutes: Int, bodyWeightPounds: Double?) -> Double {
        let pounds = bodyWeightPounds ?? 170
        let kilograms = pounds * 0.45359237
        let caloriesPerMinute = template.metValue * 3.5 * kilograms / 200
        return max(20, caloriesPerMinute * Double(minutes))
    }
}

struct MockExerciseCatalogProvider: ExerciseCatalogProviding {
    func fetchTemplates(for input: RecommendationInput) async throws -> [ExerciseTemplate] {
        let remaining = input.remainingCalories
        let recoveryMode = remaining <= 0
        let matching = Self.fallbackTemplates.filter { template in
            if recoveryMode { return template.intensity == .low || template.isLowImpact }
            if template.intensity == input.preferredIntensity { return true }
            return template.isLowImpact && input.preferredIntensity == .low
        }
        return matching.isEmpty ? Self.fallbackTemplates : matching
    }

    static let fallbackTemplates: [ExerciseTemplate] = [
        ExerciseTemplate(
            name: "Brisk Walk",
            metValue: 4.3,
            intensity: .low,
            equipment: "Bodyweight / No equipment",
            instructions: "Keep an easy nasal-breathing pace and relaxed shoulders.",
            safetyCue: "Choose flat ground if joints feel sensitive.",
            isLowImpact: true,
            sourceProvider: "Local fallback"
        ),
        ExerciseTemplate(
            name: "Mobility Flow",
            metValue: 2.5,
            intensity: .low,
            equipment: "Bodyweight / No equipment",
            instructions: "Move through hips, shoulders, and spine without forcing range.",
            safetyCue: "Stop before sharp pain or pinching.",
            isLowImpact: true,
            sourceProvider: "Local fallback"
        ),
        ExerciseTemplate(
            name: "Stationary Cycling",
            metValue: 6.8,
            intensity: .moderate,
            equipment: "Full Gym (barbells, machines, cables)",
            instructions: "Hold a steady cadence where speaking short phrases is possible.",
            safetyCue: "Lower resistance if knees or low back complain.",
            isLowImpact: true,
            sourceProvider: "Local fallback"
        ),
        ExerciseTemplate(
            name: "Dumbbell Circuit",
            metValue: 5.5,
            intensity: .moderate,
            equipment: "Dumbbells & Bench only",
            instructions: "Alternate squats, rows, presses, and carries with controlled reps.",
            safetyCue: "Use a load you can move without holding your breath.",
            isLowImpact: true,
            sourceProvider: "Local fallback"
        ),
        ExerciseTemplate(
            name: "Bodyweight Strength Circuit",
            metValue: 5.0,
            intensity: .moderate,
            equipment: "Bodyweight / No equipment",
            instructions: "Rotate squats, incline push-ups, glute bridges, and planks.",
            safetyCue: "Use incline push-ups or shorter holds when form breaks.",
            isLowImpact: true,
            sourceProvider: "Local fallback"
        ),
        ExerciseTemplate(
            name: "Run Intervals",
            metValue: 9.8,
            intensity: .high,
            equipment: "Bodyweight / No equipment",
            instructions: "Alternate hard running with easy walking recoveries.",
            safetyCue: "Swap for cycling intervals if impact feels uncomfortable.",
            isLowImpact: false,
            sourceProvider: "Local fallback"
        ),
        ExerciseTemplate(
            name: "Jump Rope Intervals",
            metValue: 11.0,
            intensity: .high,
            equipment: "Bodyweight / No equipment",
            instructions: "Use short rounds and land softly with knees relaxed.",
            safetyCue: "Avoid if ankles, knees, or calves are irritated.",
            isLowImpact: false,
            sourceProvider: "Local fallback"
        )
    ]
}

struct APINinjasExerciseCatalogProvider: ExerciseCatalogProviding {
    var apiKey: String
    var session: URLSession = .shared

    func fetchTemplates(for input: RecommendationInput) async throws -> [ExerciseTemplate] {
        let query = input.preferredIntensity.searchTerms.first ?? "cardio"
        guard var components = URLComponents(string: "https://api.api-ninjas.com/v1/exercises") else {
            return []
        }
        components.queryItems = [URLQueryItem(name: "name", value: query)]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.timeoutInterval = 8

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        let decoded = try JSONDecoder().decode([APIExercise].self, from: data)
        return decoded.map { item in
            let intensity = WorkoutIntensity(fromDifficulty: item.difficulty) ?? input.preferredIntensity
            return ExerciseTemplate(
                name: item.name.capitalized,
                metValue: intensity.defaultMET,
                intensity: intensity,
                equipment: item.equipment?.isEmpty == false ? item.equipment!.capitalized : input.availableEquipment,
                instructions: item.instructions?.isEmpty == false ? item.instructions! : "Keep the movement controlled and repeat with good form.",
                safetyCue: "Scale range, speed, or load before form breaks.",
                isLowImpact: item.type?.localizedCaseInsensitiveContains("stretching") == true || intensity == .low,
                sourceProvider: "API Ninjas"
            )
        }
    }

    private struct APIExercise: Decodable {
        let name: String
        let type: String?
        let difficulty: String?
        let equipment: String?
        let instructions: String?
    }
}

struct HybridExerciseCatalogProvider: ExerciseCatalogProviding {
    var remote: ExerciseCatalogProviding?
    var fallback: ExerciseCatalogProviding = MockExerciseCatalogProvider()

    func fetchTemplates(for input: RecommendationInput) async throws -> [ExerciseTemplate] {
        if let remote {
            let remoteTemplates = (try? await remote.fetchTemplates(for: input)) ?? []
            if !remoteTemplates.isEmpty { return remoteTemplates }
        }
        return try await fallback.fetchTemplates(for: input)
    }
}

struct WorkoutRecommendationEngine {
    var catalog: ExerciseCatalogProviding
    var estimator: CalorieEstimating

    init(
        catalog: ExerciseCatalogProviding = MockExerciseCatalogProvider(),
        estimator: CalorieEstimating = METCalorieEstimator()
    ) {
        self.catalog = catalog
        self.estimator = estimator
    }

    func recommend(input: RecommendationInput) async -> WorkoutPlan {
        let safeInput = RecommendationInput(
            targetCalories: min(max(input.targetCalories, 100), 1200),
            availableMinutes: min(max(input.availableMinutes, 10), 120),
            preferredIntensity: input.preferredIntensity,
            activeEnergyBurned: max(0, input.activeEnergyBurned),
            bodyWeightPounds: input.bodyWeightPounds,
            recentSessions: input.recentSessions,
            availableEquipment: input.availableEquipment,
            healthKitAvailable: input.healthKitAvailable
        )

        let templates = ((try? await catalog.fetchTemplates(for: safeInput)) ?? MockExerciseCatalogProvider.fallbackTemplates)
        let candidates = templates.isEmpty ? MockExerciseCatalogProvider.fallbackTemplates : templates
        let scored = candidates
            .map { template in score(template: template, input: safeInput) }
            .sorted { $0.score > $1.score }

        let bestTemplates = Array(scored.prefix(2).map(\.template))
        let workoutMinutes = max(5, safeInput.availableMinutes - 10)
        let primaryMinutes = bestTemplates.count > 1 ? Int(Double(workoutMinutes) * 0.65) : workoutMinutes
        let secondaryMinutes = max(5, workoutMinutes - primaryMinutes)

        var blocks = [
            ExerciseBlock(
                name: "Warm-Up",
                durationMinutes: 5,
                estimatedCalories: 20,
                intensity: .low,
                instructions: "Start with easy movement and joint circles.",
                equipment: "Bodyweight / No equipment",
                safetyCue: "Keep this gentle; it should prepare you, not tire you out."
            )
        ]

        for (index, template) in bestTemplates.enumerated() {
            let minutes = index == 0 ? primaryMinutes : secondaryMinutes
            blocks.append(ExerciseBlock(
                name: template.name,
                durationMinutes: minutes,
                estimatedCalories: conservativeEstimate(template: template, minutes: minutes, input: safeInput),
                intensity: template.intensity,
                instructions: template.instructions,
                equipment: template.equipment,
                safetyCue: template.safetyCue
            ))
        }

        blocks.append(ExerciseBlock(
            name: "Cooldown",
            durationMinutes: 5,
            estimatedCalories: 15,
            intensity: .low,
            instructions: "Walk slowly and stretch the main muscles you used.",
            equipment: "Bodyweight / No equipment",
            safetyCue: "Ease out gradually and let breathing return to normal."
        ))

        let totalCalories = blocks.reduce(0) { $0 + $1.estimatedCalories }
        let source = Set(bestTemplates.map(\.sourceProvider)).sorted().joined(separator: ", ")
        return WorkoutPlan(
            title: title(for: safeInput, calories: totalCalories),
            estimatedCalories: totalCalories,
            durationMinutes: blocks.reduce(0) { $0 + $1.durationMinutes },
            intensity: safeInput.remainingCalories <= 0 ? .low : safeInput.preferredIntensity,
            exercises: blocks,
            sourceProvider: source.isEmpty ? "Local fallback" : source,
            safetyNotes: safetyNotes(for: safeInput, templates: bestTemplates)
        )
    }

    private func score(template: ExerciseTemplate, input: RecommendationInput) -> (template: ExerciseTemplate, score: Double) {
        let estimated = conservativeEstimate(template: template, minutes: max(5, input.availableMinutes - 10), input: input)
        let target = max(input.remainingCalories, 80)
        let calorieFit = 1 - min(abs(estimated - target) / target, 1)
        let durationFit = input.availableMinutes >= 20 ? 1.0 : 0.65
        let intensityFit = template.intensity == requestedIntensity(for: input) ? 1.0 : 0.45
        let recentNames = Set(input.recentSessions.map { $0.title.lowercased() })
        let noveltyFit = recentNames.contains(template.name.lowercased()) ? 0.2 : 1.0
        let equipmentFit = equipmentMatches(template.equipment, input.availableEquipment) ? 1.0 : 0.45
        let safetyPenalty = safetyPenalty(template: template, input: input)

        let score = (calorieFit * 0.45)
            + (durationFit * 0.20)
            + (intensityFit * 0.20)
            + (noveltyFit * 0.10)
            + (equipmentFit * 0.05)
            - safetyPenalty
        return (template, score)
    }

    private func requestedIntensity(for input: RecommendationInput) -> WorkoutIntensity {
        input.remainingCalories <= 0 ? .low : input.preferredIntensity
    }

    private func conservativeEstimate(template: ExerciseTemplate, minutes: Int, input: RecommendationInput) -> Double {
        estimator.estimateCalories(template: template, minutes: minutes, bodyWeightPounds: input.bodyWeightPounds) * 0.85
    }

    private func safetyPenalty(template: ExerciseTemplate, input: RecommendationInput) -> Double {
        var penalty = 0.0
        if input.remainingCalories <= 0 && template.intensity != .low { penalty += 0.45 }
        if input.availableMinutes < 20 && template.intensity == .high { penalty += 0.25 }
        if template.intensity == .high && !template.isLowImpact { penalty += 0.08 }
        return penalty
    }

    private func equipmentMatches(_ templateEquipment: String, _ availableEquipment: String) -> Bool {
        let template = templateEquipment.lowercased()
        let available = availableEquipment.lowercased()
        return template.contains("bodyweight")
            || available.contains("full gym")
            || available.contains(template)
            || template.contains("no equipment")
    }

    private func title(for input: RecommendationInput, calories: Double) -> String {
        if input.remainingCalories <= 0 { return "Recovery Mobility Plan" }
        return "\(input.preferredIntensity.rawValue) \(Int(calories)) kcal Plan"
    }

    private func safetyNotes(for input: RecommendationInput, templates: [ExerciseTemplate]) -> [String] {
        var notes = [
            "Includes a warm-up and cooldown.",
            "Stop if you feel pain, dizziness, chest discomfort, or unusual shortness of breath.",
            "Calories are conservative estimates, not promises."
        ]
        if templates.contains(where: { !$0.isLowImpact }) {
            notes.append("Low-impact alternative: use brisk walking, cycling, or mobility flow.")
        }
        if !input.healthKitAvailable {
            notes.append("HealthKit is unavailable or not permitted, so the plan uses defaults you can adjust.")
        }
        if input.remainingCalories <= 0 {
            notes.append("You have met today's calorie target, so this plan prioritizes recovery.")
        }
        return notes
    }
}

private extension WorkoutIntensity {
    init?(fromDifficulty difficulty: String?) {
        guard let difficulty = difficulty?.lowercased() else { return nil }
        if difficulty.contains("beginner") { self = .low; return }
        if difficulty.contains("intermediate") { self = .moderate; return }
        if difficulty.contains("expert") || difficulty.contains("advanced") { self = .high; return }
        return nil
    }

    var defaultMET: Double {
        switch self {
        case .low: return 3.0
        case .moderate: return 5.8
        case .high: return 9.0
        }
    }
}
