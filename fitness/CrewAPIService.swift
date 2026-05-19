// CrewAPIService.swift — Network layer for crew_server.py /report endpoint
import Foundation

// MARK: - Intake Data (mirrors crew_server HealthData model)
struct IntakeData: Codable {
    // Personal
    var name:          String  = "User"
    var age:           Int     = 28
    var weightKg:      Double  = 75.0
    var heightCm:      Double  = 175.0

    // Goals & Schedule
    var goal:          String  = "General Fitness"
    var level:         String  = "Beginner (0-6 months)"
    var daysPerWeek:   Int     = 4
    var sessionMins:   Int     = 60
    var targetWeeks:   Int     = 12
    var equipment:     String  = "Full Gym (barbells, machines, cables)"
    var weeksActive:   Int     = 0
    var workoutsDone:  Int     = 0
    var streakDays:    Int     = 0

    // Health Metrics
    var steps:         Int     = 0
    var calories:      Double  = 0
    var heartRate:     Double  = 0
    var sleepHours:    Double  = 7.5
    var activeMinutes: Int     = 30

    // Nutrition
    var diet:          String  = "No restrictions (Omnivore)"
    var mealsPerDay:   Int     = 3
    var waterLiters:   Double  = 2.0
    var allergies:     String  = "None"
    var supplements:   String  = "None"

    // Lifestyle
    var stressLevel:   Int     = 5
    var injuries:      String  = "None"
    var extraGoals:    String  = "Improve overall health and energy levels"

    var bmi: Double {
        guard heightCm > 0 else { return 0 }
        return weightKg / pow(heightCm / 100.0, 2)
    }
}

// MARK: - API Request / Response
private struct ReportRequest: Codable {
    let message: String
    let health_data: ReportHealthData

    struct ReportHealthData: Codable {
        let name: String
        let age: Int
        let weight_kg: Double
        let height_cm: Double
        let steps: Int
        let calories: Double
        let heart_rate: Double
        let sleep_hours: Double
        let active_minutes: Int
        let goal: String
        let level: String
        let days_per_week: Int
        let session_mins: Int
        let target_weeks: Int
        let equipment: String
        let weeks_active: Int
        let workouts_done: Int
        let streak_days: Int
        let diet: String
        let meals_per_day: Int
        let water_liters: Double
        let allergies: String
        let supplements: String
        let stress_level: Int
        let injuries: String
        let extra_goals: String
    }
}

private struct ReportResponse: Codable {
    let report: String
    let agents_used: [String]
}

// MARK: - Error
enum CrewAPIError: LocalizedError {
    case invalidURL
    case serverUnreachable(url: String)
    case serverError(statusCode: Int, message: String)
    case decodingError
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:        return "Invalid server URL."
        case .serverUnreachable(let url):
            return """
            Cannot reach the AI server at \(url).

            On your Mac, start it with:
            cd fitness_crew
            ./run_server.sh

            Simulator can use http://localhost:8000. A real iPhone must use your Mac's Wi-Fi IP, for example http://192.168.1.23:8000.
            """
        case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
        case .decodingError:     return "Failed to read the server response."
        case .unknown(let msg):  return msg
        }
    }
}

// MARK: - Service
class CrewAPIService {
    /// Change this to your Mac's local IP when testing on a real iPhone.
    /// Simulator can use localhost.
    static var baseURL: String = "http://localhost:8000"

    static func checkHealth(baseURL override: String? = nil) async throws -> String {
        let root = override ?? baseURL
        guard let url = URL(string: "\(root)/health") else {
            throw CrewAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CrewAPIError.serverUnreachable(url: root)
        }

        guard let httpResp = response as? HTTPURLResponse else {
            throw CrewAPIError.unknown("Unexpected response type.")
        }
        guard (200...299).contains(httpResp.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CrewAPIError.serverError(statusCode: httpResp.statusCode, message: msg)
        }
        return String(data: data, encoding: .utf8) ?? "Server is online."
    }

    static func generateReport(intake: IntakeData) async throws -> String {
        guard let url = URL(string: "\(baseURL)/report") else {
            throw CrewAPIError.invalidURL
        }

        let body = ReportRequest(
            message: "",
            health_data: .init(
                name:           intake.name,
                age:            intake.age,
                weight_kg:      intake.weightKg,
                height_cm:      intake.heightCm,
                steps:          intake.steps,
                calories:       intake.calories,
                heart_rate:     intake.heartRate,
                sleep_hours:    intake.sleepHours,
                active_minutes: intake.activeMinutes,
                goal:           intake.goal,
                level:          intake.level,
                days_per_week:  intake.daysPerWeek,
                session_mins:   intake.sessionMins,
                target_weeks:   intake.targetWeeks,
                equipment:      intake.equipment,
                weeks_active:   intake.weeksActive,
                workouts_done:  intake.workoutsDone,
                streak_days:    intake.streakDays,
                diet:           intake.diet,
                meals_per_day:  intake.mealsPerDay,
                water_liters:   intake.waterLiters,
                allergies:      intake.allergies,
                supplements:    intake.supplements,
                stress_level:   intake.stressLevel,
                injuries:       intake.injuries,
                extra_goals:    intake.extraGoals
            )
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120  // AI generation can take time
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CrewAPIError.serverUnreachable(url: baseURL)
        }

        guard let httpResp = response as? HTTPURLResponse else {
            throw CrewAPIError.unknown("Unexpected response type.")
        }

        guard (200...299).contains(httpResp.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CrewAPIError.serverError(statusCode: httpResp.statusCode, message: msg)
        }

        guard let decoded = try? JSONDecoder().decode(ReportResponse.self, from: data) else {
            throw CrewAPIError.decodingError
        }

        return decoded.report
    }
}
