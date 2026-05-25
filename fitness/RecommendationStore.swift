import Foundation

struct RecommendationCache: Codable {
    var templates: [ExerciseTemplate] = []
    var recommendations: [WorkoutPlan] = []
    var completedSessions: [WorkoutSessionSummary] = []
    var dailyTargets: [DailyFitnessTarget] = []
}

struct DailyFitnessTarget: Codable, Equatable {
    var date: Date
    var targetCalories: Double
    var stepGoal: Int
}

protocol RecommendationStoring {
    func loadCache() -> RecommendationCache
    func saveRecommendation(_ plan: WorkoutPlan, target: DailyFitnessTarget)
    func saveCompletedSession(_ summary: WorkoutSessionSummary)
}

final class FileRecommendationStore: RecommendationStoring {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "fitness.recommendation.store")

    init(fileManager: FileManager = .default) {
        let directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        fileURL = directory.appendingPathComponent("recommendation_cache.json")
    }

    func loadCache() -> RecommendationCache {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else {
                return RecommendationCache()
            }
            return (try? JSONDecoder().decode(RecommendationCache.self, from: data)) ?? RecommendationCache()
        }
    }

    func saveRecommendation(_ plan: WorkoutPlan, target: DailyFitnessTarget) {
        queue.sync {
            var cache = readCacheUnlocked()
            cache.recommendations.insert(plan, at: 0)
            cache.recommendations = Array(cache.recommendations.prefix(10))
            cache.dailyTargets.insert(target, at: 0)
            cache.dailyTargets = Array(cache.dailyTargets.prefix(30))
            writeCacheUnlocked(cache)
        }
    }

    func saveCompletedSession(_ summary: WorkoutSessionSummary) {
        queue.sync {
            var cache = readCacheUnlocked()
            cache.completedSessions.insert(summary, at: 0)
            cache.completedSessions = Array(cache.completedSessions.prefix(20))
            writeCacheUnlocked(cache)
        }
    }

    private func readCacheUnlocked() -> RecommendationCache {
        guard let data = try? Data(contentsOf: fileURL) else {
            return RecommendationCache()
        }
        return (try? JSONDecoder().decode(RecommendationCache.self, from: data)) ?? RecommendationCache()
    }

    private func writeCacheUnlocked(_ cache: RecommendationCache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
