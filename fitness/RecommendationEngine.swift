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

    /// Maps intensity to API Ninjas exercise type for smarter queries.
    var apiExerciseType: String? {
        switch self {
        case .low: return "stretching"
        case .moderate: return "strength"
        case .high: return "plyometrics"
        }
    }

    /// Maps intensity to API Ninjas difficulty param.
    var apiDifficulty: String {
        switch self {
        case .low: return "beginner"
        case .moderate: return "intermediate"
        case .high: return "expert"
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
    var muscle: String = ""
    var exerciseType: String = ""
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

// MARK: - Wger API response model
struct WgerResponse: Decodable {
    let results: [WgerExercise]
}

struct WgerExercise: Decodable, Identifiable, Equatable {
    static func == (lhs: WgerExercise, rhs: WgerExercise) -> Bool {
        lhs.id == rhs.id
    }
    
    let id: Int
    let category: WgerNamedItem?
    let muscles: [WgerNamedItem]?
    let equipment: [WgerNamedItem]?
    let translations: [WgerTranslation]?
    let images: [WgerImage]?
    
    var englishTranslation: WgerTranslation? {
        translations?.first(where: { $0.language == 2 })
    }
    
    // Wger places the English name/desc in translations array. Prefer language == 2 (English).
    var name: String { englishTranslation?.name ?? translations?.first?.name ?? "Unknown Exercise" }
    
    var descriptionStr: String {
        let desc = englishTranslation?.description_source ?? englishTranslation?.description ?? "Keep the movement controlled and repeat with good form."
        return desc.strippingHTML()
    }
    
    var imageUrl: URL? {
        guard let urlString = images?.first?.image else { return nil }
        return URL(string: urlString)
    }
    
    var equipmentDisplay: String {
        guard let eq = equipment, !eq.isEmpty else { return "No equipment" }
        return eq.map { $0.name }.joined(separator: ", ")
    }
    
    func toTemplate(fallbackEquipment: String = "Bodyweight / No equipment",
                    fallbackIntensity: WorkoutIntensity = .moderate) -> ExerciseTemplate {
        return ExerciseTemplate(
            name: name,
            metValue: fallbackIntensity.defaultMET,
            intensity: fallbackIntensity,
            equipment: equipmentDisplay == "none (bodyweight exercise)" ? fallbackEquipment : equipmentDisplay,
            instructions: descriptionStr,
            safetyCue: "Scale range, speed, or load before form breaks.",
            isLowImpact: category?.name.localizedCaseInsensitiveContains("stretching") == true || fallbackIntensity == .low,
            sourceProvider: "Wger API",
            muscle: muscles?.map { $0.name }.joined(separator: ", ") ?? "",
            exerciseType: category?.name ?? ""
        )
    }
}

struct WgerNamedItem: Decodable {
    let id: Int
    let name: String
}

struct WgerTranslation: Decodable {
    let language: Int?
    let name: String?
    let description: String?
    let description_source: String?
}

struct WgerImage: Decodable {
    let image: String?
}

extension String {
    func strippingHTML() -> String {
        return self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
    }
}

// MARK: - Wger API Service
struct WgerService {
    var session: URLSession = .shared

    /// Map user equipment selection to Wger equipment ID.
    static func mapEquipment(_ userEquipment: String) -> Int? {
        let lower = userEquipment.lowercased()
        if lower.contains("dumbbell")  { return 3 }
        if lower.contains("band")      { return 8 }
        if lower.contains("barbell")   { return 1 }
        if lower.contains("bodyweight") || lower.contains("no equipment") { return 7 }
        return nil
    }

    /// Search exercises by category, equipment, or name filtering locally
    func searchExercises(
        name: String? = nil,
        category: Int? = nil,
        equipment: Int? = nil
    ) async throws -> [WgerExercise] {
        guard var components = URLComponents(string: "https://wger.de/api/v2/exerciseinfo/") else {
            return []
        }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "language", value: "2"), // English
            URLQueryItem(name: "limit", value: "100") // Batch size
        ]
        
        if let category { queryItems.append(URLQueryItem(name: "category", value: String(category))) }
        if let equipment { queryItems.append(URLQueryItem(name: "equipment", value: String(equipment))) }
        
        components.queryItems = queryItems

        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let wgerResponse = try JSONDecoder().decode(WgerResponse.self, from: data)
        var results = wgerResponse.results
        
        // Filter out exercises that don't have an English translation
        results = results.filter { $0.englishTranslation != nil }
        
        if let name = name, !name.isEmpty {
            results = results.filter { $0.name.localizedCaseInsensitiveContains(name) }
        }
        
        return results
    }

    func lookupExercise(name: String) async throws -> WgerExercise? {
        let results = try await searchExercises(name: name)
        return results.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            ?? results.first
    }
}

struct WgerExerciseCatalogProvider: ExerciseCatalogProviding {
    var session: URLSession = .shared

    func fetchTemplates(for input: RecommendationInput) async throws -> [ExerciseTemplate] {
        let service = WgerService(session: session)
        let equipmentID = WgerService.mapEquipment(input.availableEquipment)

        let results = try await service.searchExercises(equipment: equipmentID)
        return results.shuffled().prefix(20).map { 
            $0.toTemplate(fallbackEquipment: input.availableEquipment,
                          fallbackIntensity: input.preferredIntensity)
        }
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
