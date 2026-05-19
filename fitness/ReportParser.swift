// ReportParser.swift — Parses AI-generated .md coaching reports into structured data
import Foundation

struct CoachingReport: Identifiable {
    let id = UUID()
    var name:                String = "User"
    var date:                String = ""
    var intro:               String = ""
    var motivationalMessage: String = ""
    var workoutStrategy:     String = ""
    var workoutDays:         [WorkoutDayPlan] = []
    var nutritionApproach:   String = ""
    var macros:              MacroInfo? = nil
    var healthKitInsights:   String = ""
    var progressHighlights:  String = ""
    var appImprovements:     String = ""
    var topActions:          [String] = []
    var motivationalClosing: String = ""
    var rawMarkdown:         String = ""
    // Extracted numeric goals — used by Dashboard
    var calGoalValue:  Double = 500
    var stepGoalValue: Int    = 10_000
}

struct WorkoutDayPlan: Identifiable {
    let id = UUID()
    var title:     String        // e.g. "Day 1: Chest and Triceps"
    var exercises: [String]      // bullet lines
}

struct MacroInfo {
    var calories:  String = ""
    var protein:   String = ""
    var carbs:     String = ""
    var fat:       String = ""
}

// MARK: - Parser
enum ReportParser {

    static func parse(_ markdown: String) -> CoachingReport {
        var report = CoachingReport()
        report.rawMarkdown = markdown

        // ── Name from h1 ──────────────────────────────────────────────────────
        if let nameMatch = markdown.range(of: #"^# (.+)'s Personalized"#,
                                          options: .regularExpression) {
            let line = String(markdown[nameMatch])
            report.name = line
                .replacingOccurrences(of: "# ", with: "")
                .components(separatedBy: "'s Personalized").first ?? "User"
        }

        // ── Date ──────────────────────────────────────────────────────────────
        if let m = markdown.range(of: #"## Date: (.+)"#, options: .regularExpression) {
            report.date = String(markdown[m]).replacingOccurrences(of: "## Date: ", with: "")
        }

        // ── Split into sections by ### ────────────────────────────────────────
        let sections = splitSections(markdown)

        // Intro = text between QA Status line and first ###
        report.intro = sections["__intro__"] ?? ""

        report.motivationalMessage = sections["Personalized Motivational Message"] ?? ""
        report.workoutStrategy     = sections["QA-Verified Workout Strategy Summary"] ?? ""
        report.nutritionApproach   = sections["Nutrition Approach"] ?? ""
        report.healthKitInsights   = sections["HealthKit Insights"] ?? ""
        report.progressHighlights  = sections["Progress Highlights"] ?? ""
        report.appImprovements     = sections["App Experience Improvements"] ?? ""
        report.motivationalClosing = sections["Motivational Closing"] ?? ""

        // ── Top 5 Actions → array ─────────────────────────────────────────────
        if let raw = sections["This Week's Top 5 Actions"] {
            report.topActions = raw.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("*") || $0.hasPrefix("-") || $0.first?.isNumber == true }
                .map { $0.trimmingCharacters(in: .init(charactersIn: "*-1234567890. ")) }
                .filter { !$0.isEmpty }
        }

        // ── Workout days ──────────────────────────────────────────────────────
        report.workoutDays = parseWorkoutDays(report.workoutStrategy)

        // ── Macro info ────────────────────────────────────────────────────────
        report.macros = parseMacros(report.nutritionApproach)

        // ── Numeric goals for Dashboard ───────────────────────────────────────
        report.calGoalValue  = extractCalGoal(report.nutritionApproach)
        report.stepGoalValue = extractStepGoal(report.healthKitInsights
                                               + " " + report.progressHighlights)
        return report
    }

    // MARK: Helpers

    private static func splitSections(_ md: String) -> [String: String] {
        var result: [String: String] = [:]
        let lines = md.components(separatedBy: "\n")
        var currentKey: String = "__intro__"
        var buffer: [String] = []

        for line in lines {
            if line.hasPrefix("### ") {
                result[currentKey] = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                currentKey = line.replacingOccurrences(of: "### ", with: "").trimmingCharacters(in: .whitespaces)
                buffer = []
            } else if !line.hasPrefix("# ") && !line.hasPrefix("## ") {
                buffer.append(line)
            }
        }
        result[currentKey] = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    private static func parseWorkoutDays(_ text: String) -> [WorkoutDayPlan] {
        var days: [WorkoutDayPlan] = []
        var currentTitle = ""
        var currentExercises: [String] = []

        for line in text.components(separatedBy: "\n") {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            let lower = stripped.lowercased()
            let isDayHeading = lower.contains("day ") && stripped.contains(":")
            let isWeekdayHeading = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
                .contains { lower.contains($0) } && stripped.contains(":")
            if isDayHeading || isWeekdayHeading {
                if !currentTitle.isEmpty {
                    days.append(WorkoutDayPlan(title: currentTitle, exercises: currentExercises))
                }
                currentTitle = stripped.trimmingCharacters(in: .init(charactersIn: "*-# "))
                currentExercises = []
            } else if (stripped.hasPrefix("+") || stripped.hasPrefix("-") || stripped.hasPrefix("*")) && !stripped.isEmpty {
                let ex = stripped.trimmingCharacters(in: .init(charactersIn: "+-* \t"))
                if !ex.isEmpty { currentExercises.append(ex) }
            }
        }
        if !currentTitle.isEmpty {
            days.append(WorkoutDayPlan(title: currentTitle, exercises: currentExercises))
        }
        return days
    }

    private static func parseMacros(_ text: String) -> MacroInfo {
        var m = MacroInfo()
        for line in text.components(separatedBy: "\n") {
            let l = line.lowercased()
            if l.contains("calorie") || l.contains("kcal") {
                m.calories = extractBold(line) ?? extractNumbers(line)
            } else if l.contains("protein") {
                m.protein = extractBold(line) ?? extractNumbers(line)
            } else if l.contains("carbohydrate") || l.contains("carb") {
                m.carbs = extractBold(line) ?? extractNumbers(line)
            } else if l.contains(" fat") {
                m.fat = extractBold(line) ?? extractNumbers(line)
            }
        }
        return m
    }

    private static func extractBold(_ s: String) -> String? {
        let pattern = #"\*\*([^*]+)\*\*"#
        guard let r = s.range(of: pattern, options: .regularExpression) else { return nil }
        return String(s[r]).replacingOccurrences(of: "**", with: "")
    }

    private static func extractNumbers(_ s: String) -> String {
        let nums = s.components(separatedBy: .whitespaces)
            .filter { $0.contains(where: { $0.isNumber }) }
        return nums.first ?? ""
    }

    // ── Numeric goal extractors ───────────────────────────────────────────────
    private static func extractCalGoal(_ text: String) -> Double {
        // Matches "2500 calories", "2500-2800 calories", "3,193 kcal"
        let pattern = #"(\d[\d,]{2,})(\s*-\s*\d[\d,]+)?\s*(?:kcal|calories|calorie|cal)"#
        guard let r = text.range(of: pattern, options: [.regularExpression, .caseInsensitive])
        else { return 500 }
        let raw = String(text[r])
            .replacingOccurrences(of: ",", with: "")
        let nums = raw.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }.compactMap { Double($0) }
            .filter { $0 >= 1000 && $0 <= 8000 }
        return nums.first ?? 500
    }

    private static func extractStepGoal(_ text: String) -> Int {
        // Matches "10,000 steps", "7000 steps"
        let pattern = #"(\d[\d,]{2,})\s*steps"#
        guard let r = text.range(of: pattern, options: [.regularExpression, .caseInsensitive])
        else { return 10_000 }
        let raw = String(text[r]).replacingOccurrences(of: ",", with: "")
        let nums = raw.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }.compactMap { Int($0) }
            .filter { $0 >= 1_000 && $0 <= 50_000 }
        return nums.first ?? 10_000
    }
}
