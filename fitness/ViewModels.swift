// ViewModels.swift — HealthKitViewModel + WorkoutViewModel (no ChatViewModel)
import Foundation
import Combine

// MARK: - HealthKit ViewModel
class HealthKitViewModel: ObservableObject {
    @Published var steps:     Double = 0
    @Published var calories:  Double = 0
    @Published var heartRate: Double = 72
    @Published var authorized = false
    private let svc = HealthKitService()

    func requestAuthorization() {
        svc.requestAuth { [weak self] ok in
            self?.authorized = ok
            if ok { self?.refresh() }
        }
    }
    func refresh() {
        svc.fetchSteps    { self.steps     = $0 }
        svc.fetchCalories { self.calories  = $0 }
        svc.fetchHR       { self.heartRate = $0 }
    }
}

// MARK: - Workout ViewModel
class WorkoutViewModel: ObservableObject {
    @Published var plans: [FitnessPlan] = FitnessPlan.defaults
    @Published var activePlanIndex = 0
    var activePlan: FitnessPlan { plans[activePlanIndex] }

    func toggleExercise(dayId: UUID, exId: UUID) {
        guard
            let di = plans[activePlanIndex].days.firstIndex(where: { $0.id == dayId }),
            let ei = plans[activePlanIndex].days[di].exercises.firstIndex(where: { $0.id == exId })
        else { return }
        plans[activePlanIndex].days[di].exercises[ei].isCompleted.toggle()
    }
    func completeDay(dayId: UUID) {
        guard let di = plans[activePlanIndex].days.firstIndex(where: { $0.id == dayId })
        else { return }
        plans[activePlanIndex].days[di].completedDate = Date()
    }

    func installGeneratedPlan(from report: CoachingReport, intake: IntakeData) {
        let generatedDays = report.workoutDays.enumerated().map { index, dayPlan in
            WorkoutDay(
                name: shortDayName(from: dayPlan.title, fallbackIndex: index),
                focus: focusName(from: dayPlan.title),
                exercises: dayPlan.exercises.map(makeExercise),
                isRest: dayPlan.title.lowercased().contains("rest"),
                duration: intake.sessionMins
            )
        }

        let fallbackDays = FitnessPlan.defaults.first?.days ?? []
        let plan = FitnessPlan(
            name: "\(report.name)'s AI Plan",
            desc: "\(intake.goal) plan generated from your latest coaching report.",
            difficulty: difficulty(from: intake.level),
            weeks: intake.targetWeeks,
            goal: goal(from: intake.goal),
            days: generatedDays.isEmpty ? fallbackDays : generatedDays,
            emoji: "AI"
        )

        if let existing = plans.firstIndex(where: { $0.name.hasSuffix("'s AI Plan") }) {
            plans[existing] = plan
            activePlanIndex = existing
        } else {
            plans.insert(plan, at: 0)
            activePlanIndex = 0
        }
    }

    private func makeExercise(_ raw: String) -> Exercise {
        let sets = firstMatch(in: raw, pattern: #"(\d+)\s*(?:sets?|x|×)"#) ?? 3
        let reps = firstMatch(in: raw, pattern: #"(?:x|×|for)\s*(\d+)"#) ?? 10
        let name = raw
            .replacingOccurrences(of: #"\*\*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[-+•]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Exercise(name: name.isEmpty ? "Workout block" : name, sets: sets, reps: reps, icon: "dumbbell.fill")
    }

    private func firstMatch(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return Int(text[range])
    }

    private func shortDayName(from title: String, fallbackIndex: Int) -> String {
        let trimmed = title.replacingOccurrences(of: "**", with: "")
        if let colon = trimmed.firstIndex(of: ":") {
            return String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
        }
        return "Day \(fallbackIndex + 1)"
    }

    private func focusName(from title: String) -> String {
        let trimmed = title.replacingOccurrences(of: "**", with: "")
        if let colon = trimmed.firstIndex(of: ":") {
            return String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    private func difficulty(from level: String) -> Difficulty {
        let lower = level.lowercased()
        if lower.contains("advanced") { return .advanced }
        if lower.contains("intermediate") { return .intermediate }
        return .beginner
    }

    private func goal(from text: String) -> Goal {
        let lower = text.lowercased()
        if lower.contains("loss") { return .weightLoss }
        if lower.contains("muscle") { return .muscleGain }
        if lower.contains("endurance") { return .endurance }
        return .general
    }
}
