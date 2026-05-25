// ReportView.swift — Displays a parsed AI coaching report with rich UI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ViewModel (app-level — shared via environmentObject)
class ReportViewModel: ObservableObject {
    @Published var report:         CoachingReport? = nil
    @Published var showPicker:     Bool = false
    @Published var errorMessage:   String? = nil
    @Published var checkedActions: Set<Int> = []   // indices of ticked to-dos
    @Published var savedReportURL: URL? = nil

    // Fraction of top-actions completed (0.0 – 1.0)
    var actionProgress: Double {
        let total = report?.topActions.count ?? 0
        guard total > 0 else { return 0 }
        return Double(checkedActions.count) / Double(total)
    }

    func toggleAction(_ index: Int) {
        if checkedActions.contains(index) {
            checkedActions.remove(index)
        } else {
            checkedActions.insert(index)
        }
    }

    func load(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Could not access file."; return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            report = ReportParser.parse(text)
            checkedActions = []          // reset ticks on new report
            errorMessage   = nil
            savedReportURL = url
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
        }
    }

    func loadFromString(_ markdown: String) {
        report = ReportParser.parse(markdown)
        checkedActions = []
        errorMessage = nil
    }

    @discardableResult
    func saveMarkdown(_ markdown: String, preferredName: String) throws -> URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let safeName = preferredName
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9_ -]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: " ", with: "_")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "report_\(safeName.isEmpty ? "user" : safeName)_\(formatter.string(from: Date())).md"
        let url = docs.appendingPathComponent(filename)
        try markdown.write(to: url, atomically: true, encoding: .utf8)

        #if targetEnvironment(simulator)
        let macFolder = "/Users/BrokenMac/Documents/FitnessPlan"
        let macURL = URL(fileURLWithPath: macFolder).appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(atPath: macFolder, withIntermediateDirectories: true)
            try markdown.write(to: macURL, atomically: true, encoding: .utf8)
            print("🚀 Mirrored simulator report to Mac folder: \(macURL.path)")
        } catch {
            print("⚠️ Failed to mirror simulator report to Mac folder: \(error.localizedDescription)")
        }
        #endif

        savedReportURL = url
        return url
    }

    func importGeneratedReport(_ markdown: String, preferredName: String) throws -> CoachingReport {
        _ = try saveMarkdown(markdown, preferredName: preferredName)
        loadFromString(markdown)
        return report ?? ReportParser.parse(markdown)
    }
}

// MARK: - Main Report View
struct ReportView: View {
    @EnvironmentObject private var vm: ReportViewModel

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            if let report = vm.report {
                ReportDetailView(report: report) {
                    vm.showPicker = true
                }
            } else {
                emptyState
            }
        }
        .fileImporter(
            isPresented: $vm.showPicker,
            allowedContentTypes: [.text, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { vm.load(url: url) }
            case .failure(let err):
                vm.errorMessage = err.localizedDescription
            }
        }
        .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(LinearGradient(colors: [.accent, .teal],
                    startPoint: .topLeading, endPoint: .bottomTrailing))

            Text("No Report Loaded")
                .font(.title2.bold()).foregroundColor(.white)

            Text("Use the Get Plan tab to generate a coaching plan in the app, or import an existing .md file here.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button { vm.showPicker = true } label: {
                Label("Select Report (.md)", systemImage: "folder.badge.plus")
                    .font(.headline).foregroundColor(.white)
                    .padding(.horizontal, 28).padding(.vertical, 14)
                    .background(LinearGradient(colors: [.accent, .teal],
                        startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(14)
            }
        }.padding(32)
    }
}

// MARK: - Detail View (scrollable report)
struct ReportDetailView: View {
    @EnvironmentObject private var vm: ReportViewModel
    let report: CoachingReport
    let onSwap: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Group {
                    reportHeader
                    if !report.intro.isEmpty             { introCard }
                    if !report.motivationalMessage.isEmpty { motivationCard }
                    if !report.workoutDays.isEmpty        { workoutSection }
                    else if !report.workoutStrategy.isEmpty {
                        textCard("Workout Strategy", icon: "dumbbell.fill",
                                 color: .accent, text: report.workoutStrategy)
                    }
                    if report.macros != nil || !report.nutritionApproach.isEmpty {
                        nutritionSection
                    }
                }
                Group {
                    if !report.healthKitInsights.isEmpty {
                        textCard("HealthKit Insights", icon: "heart.text.square.fill",
                                 color: .red, text: report.healthKitInsights)
                    }
                    if !report.progressHighlights.isEmpty {
                        textCard("Progress Highlights", icon: "chart.line.uptrend.xyaxis",
                                 color: .teal, text: report.progressHighlights)
                    }
                    if !report.topActions.isEmpty         { actionsSection }
                    if !report.appImprovements.isEmpty {
                        textCard("App Improvements", icon: "sparkles",
                                 color: .amber, text: report.appImprovements)
                    }
                    if !report.motivationalClosing.isEmpty {
                        textCard("Closing Message", icon: "hands.sparkles.fill",
                                 color: .accent, text: report.motivationalClosing)
                    }
                    Spacer(minLength: 30)
                }
            }.padding(.top)
        }
    }

    // MARK: Header
    var reportHeader: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(report.name)'s Report")
                        .font(.title.bold()).foregroundColor(.white)
                    Text(report.date).font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2).foregroundColor(.teal)
                    Text("QA PASS").font(.caption2.bold()).foregroundColor(.teal)
                }
            }
            .padding(16)
            .background(LinearGradient(
                colors: [Color.accent.opacity(0.3), Color.teal.opacity(0.2)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .cornerRadius(16)

            Button { onSwap() } label: {
                Label("Load Different Report", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundColor(.accent)
            }
            ReportStatsBar(report: report, savedURL: vm.savedReportURL, actionProgress: vm.actionProgress)
        }.padding(.horizontal)
    }

    // MARK: Intro
    var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("From Your Head Coach", systemImage: "person.fill.checkmark")
                .font(.caption.bold()).foregroundColor(.accent)
            Text(report.intro).font(.body).foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card).cornerRadius(16).padding(.horizontal)
    }

    // MARK: Motivation
    var motivationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Motivational Message", systemImage: "flame.fill")
                .font(.caption.bold()).foregroundColor(.amber)
            Text(cleanMarkdown(report.motivationalMessage))
                .font(.body).foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card).cornerRadius(16).padding(.horizontal)
    }

    // MARK: Workout Days
    var workoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Weekly Workout Plan", systemImage: "dumbbell.fill")
                .font(.headline).foregroundColor(.white)
                .padding(.horizontal)
            ForEach(report.workoutDays) { day in
                WorkoutDayCard(day: day)
            }
        }
    }

    // MARK: Nutrition
    var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Nutrition Approach", systemImage: "fork.knife")
                .font(.headline).foregroundColor(.white)
                .padding(.horizontal)

            if let m = report.macros, !m.calories.isEmpty {
                HStack(spacing: 12) {
                    MacroChip(label: "Calories", value: m.calories, color: .amber)
                    MacroChip(label: "Protein",  value: m.protein,  color: .red)
                    MacroChip(label: "Carbs",    value: m.carbs,    color: .teal)
                    MacroChip(label: "Fat",      value: m.fat,      color: .accent)
                }.padding(.horizontal)
            }

            if !report.nutritionApproach.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(cleanMarkdown(report.nutritionApproach))
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14).background(Color.card).cornerRadius(14).padding(.horizontal)
            }
        }
    }

    // MARK: Top Actions
    var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("This Week's Top Actions", systemImage: "checklist")
                .font(.headline).foregroundColor(.white)
                .padding(.horizontal)
            ForEach(report.topActions.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(i + 1)")
                        .font(.caption.bold()).foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.accent).cornerRadius(11)
                    Text(cleanMarkdown(report.topActions[i]))
                        .font(.subheadline).foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(12).background(Color.card).cornerRadius(12).padding(.horizontal)
            }
        }
    }

    // MARK: Generic text card
    func textCard(_ title: String, icon: String, color: Color, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline).foregroundColor(color)
            Text(cleanMarkdown(text)).font(.subheadline).foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card).cornerRadius(16).padding(.horizontal)
    }

    // Strip markdown bold/italic for plain display
    func cleanMarkdown(_ s: String) -> String {
        s.replacingOccurrences(of: "**", with: "")
         .replacingOccurrences(of: "__", with: "")
         .replacingOccurrences(of: #"\*(?!\*)"#, with: "", options: .regularExpression)
    }
}

struct ReportStatsBar: View {
    let report: CoachingReport
    let savedURL: URL?
    let actionProgress: Double

    var body: some View {
        HStack(spacing: 8) {
            ReportStatChip(title: "Actions", value: "\(Int(actionProgress * 100))%", icon: "checklist", color: .teal)
            ReportStatChip(title: "Steps", value: "\(report.stepGoalValue / 1000)k", icon: "figure.walk", color: .accent)
            ReportStatChip(title: "Calories", value: "\(Int(report.calGoalValue))", icon: "flame.fill", color: .amber)
            ReportStatChip(title: "Saved", value: savedURL == nil ? "--" : ".md", icon: "doc.fill", color: .secondary)
        }
    }
}

struct ReportStatChip: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundColor(color)
            Text(value).font(.caption.bold()).foregroundColor(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundColor(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.card)
        .cornerRadius(10)
    }
}

// MARK: - Workout Day Card
struct WorkoutDayCard: View {
    let day: WorkoutDayPlan
    @State private var expanded = false

    var isRest: Bool { day.title.lowercased().contains("rest") }

    var body: some View {
        VStack(spacing: 0) {
            Button { if !isRest { expanded.toggle() } } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(isRest ? Color.secondary.opacity(0.15) : Color.accent.opacity(0.2))
                            .frame(width: 44, height: 44)
                        Image(systemName: isRest ? "moon.zzz.fill" : "dumbbell.fill")
                            .foregroundColor(isRest ? .secondary : .accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.title).font(.subheadline.bold()).foregroundColor(.white)
                        if !isRest {
                            Text("\(day.exercises.count) exercises")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    if !isRest {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }.padding(14)
            }

            if expanded && !day.exercises.isEmpty {
                Divider().background(Color.bg)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(day.exercises, id: \.self) { ex in
                        HStack(spacing: 10) {
                            Circle().fill(Color.accent).frame(width: 6, height: 6)
                            Text(ex).font(.caption).foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                    }
                }.padding(14)
            }
        }
        .background(Color.card).cornerRadius(14).padding(.horizontal)
    }
}

// MARK: - Macro Chip
struct MacroChip: View {
    let label: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.caption.bold()).foregroundColor(color)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(color.opacity(0.15)).cornerRadius(10)
    }
}
