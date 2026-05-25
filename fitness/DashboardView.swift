// DashboardView.swift
// Protocol-backed dashboard. Goals and to-do list driven by loaded .md report.

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var dashVM:    DashboardViewModel
    @EnvironmentObject var workoutVM: WorkoutViewModel
    @EnvironmentObject var reportVM:  ReportViewModel
    @StateObject private var recommendationVM = RecommendationViewModel()
    @State private var showRecommendationDetail = false
    @Binding var selectedTab: Int

    var snap: HealthSnapshot { dashVM.snapshot }

    // Overall progress = 50% HealthKit + 50% checked actions
    var combinedProgress: Double {
        let hk = (snap.stepProgress + snap.calProgress) / 2.0
        let ac = reportVM.actionProgress
        return reportVM.report != nil ? (hk + ac) / 2.0 : hk
    }
    var combinedPercentage: Int { Int(combinedProgress * 100) }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    headerRow
                    connectionBanner
                    progressRing
                    metricsRow
                    if let day = todayWorkout { todayWorkoutCard(day) }
                    localRecommendationSection
                    reportActionsSection       // live to-dos from .md
                    reportCard
                    quickStatsRow
                    Spacer(minLength: 30)
                }
                .padding(.top)
            }
            .refreshable { dashVM.refresh() }
        }
        .sheet(isPresented: $showRecommendationDetail) {
            if let plan = recommendationVM.plan {
                WorkoutRecommendationDetailView(plan: plan) {
                    recommendationVM.markCompleted()
                    showRecommendationDetail = false
                }
            }
        }
        .onAppear {
            dashVM.authorize()
            recommendationVM.refresh(snapshot: snap)
        }
        .onChange(of: snap.calories) { _ in
            recommendationVM.refresh(snapshot: snap)
        }
        .onChange(of: snap.calGoal) { _ in
            recommendationVM.refresh(snapshot: snap)
        }
        // Sync goals whenever a new report is loaded
        .onChange(of: reportVM.report?.id) { _ in
            if let r = reportVM.report {
                dashVM.syncGoals(calGoal: r.calGoalValue, stepGoal: r.stepGoalValue)
            }
        }
    }

    // MARK: Header + refresh
    var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Good \(greeting)").font(.subheadline).foregroundColor(.secondary)
                if let name = reportVM.report?.name {
                    Text(name).font(.largeTitle.bold()).foregroundColor(.white)
                } else {
                    Text("Dashboard").font(.largeTitle.bold()).foregroundColor(.white)
                }
            }
            Spacer()
            Button { dashVM.refresh() } label: {
                ZStack {
                    Circle().fill(Color.card).frame(width: 44, height: 44)
                    if dashVM.isLoading {
                        ProgressView().tint(.accent).scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.bold()).foregroundColor(.accent)
                    }
                }
            }
            .disabled(dashVM.isLoading)
        }.padding(.horizontal)
    }

    // MARK: Connection status banner
    @ViewBuilder
    var connectionBanner: some View {
        let s = snap.connectionStatus
        if s != .connected {
            HStack(spacing: 12) {
                Image(systemName: s.icon).foregroundColor(s.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.label).font(.caption.bold()).foregroundColor(s.color)
                    Text(s == .permissionDenied
                         ? "Open Settings → Health to grant access."
                         : "HealthKit is not available on this device.")
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(s.color.opacity(0.12))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    // MARK: Progress ring (combined: HealthKit + actions)
    var progressRing: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().stroke(Color.accent.opacity(0.15), lineWidth: 18)
                Circle()
                    .trim(from: 0, to: CGFloat(combinedProgress))
                    .stroke(
                        LinearGradient(colors: [.accent, .teal],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: combinedProgress)

                VStack(spacing: 2) {
                    Text("\(combinedPercentage)%")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Daily Progress")
                        .font(.caption).foregroundColor(.secondary)
                    if reportVM.report != nil {
                        Text("HK + Actions")
                            .font(.caption2).foregroundColor(.accent)
                    }
                }
            }
            .frame(width: 160, height: 160)
            .padding(.vertical, 8)

            HStack(spacing: 6) {
                Image(systemName: snap.connectionStatus.icon)
                    .font(.caption2).foregroundColor(snap.connectionStatus.color)
                Text(snap.connectionStatus.label)
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20).background(Color.card).cornerRadius(20).padding(.horizontal)
    }

    // MARK: Daily goal + active calories + HR
    var metricsRow: some View {
        HStack(spacing: 12) {
            GoalMetricCard(
                icon: "figure.walk", color: .accent, title: "Daily Goal",
                value: snap.steps >= 1000
                    ? String(format: "%.1fk", snap.steps / 1000)
                    : "\(Int(snap.steps))",
                subtitle: "of \(snap.stepGoal >= 1000 ? "\(snap.stepGoal / 1000)k" : "\(snap.stepGoal)") steps",
                progress: snap.stepProgress
            )
            GoalMetricCard(
                icon: "flame.fill", color: .amber, title: "Active Cal",
                value: "\(Int(snap.calories))",
                subtitle: "of \(Int(snap.calGoal)) kcal goal",
                progress: snap.calProgress
            )
            GoalMetricCard(
                icon: "heart.fill", color: .red, title: "Heart Rate",
                value: snap.heartRate > 0 ? "\(Int(snap.heartRate))" : "--",
                subtitle: "bpm resting",
                progress: nil
            )
        }.padding(.horizontal)
    }

    // MARK: Report to-dos (live checkable actions from .md)
    @ViewBuilder
    var reportActionsSection: some View {
        if let report = reportVM.report, !report.topActions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("This Week's Actions", systemImage: "checklist")
                        .font(.headline).foregroundColor(.white)
                    Spacer()
                    // Actions progress badge
                    Text("\(reportVM.checkedActions.count)/\(report.topActions.count)")
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accent.opacity(0.2))
                        .foregroundColor(.accent).cornerRadius(8)
                }
                .padding(.horizontal)

                ForEach(report.topActions.indices, id: \.self) { i in
                    let checked = reportVM.checkedActions.contains(i)
                    Button { reportVM.toggleAction(i) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle()
                                    .stroke(checked ? Color.teal : Color.secondary.opacity(0.4),
                                            lineWidth: 1.5)
                                    .frame(width: 22, height: 22)
                                if checked {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.teal)
                                }
                            }
                            Text(report.topActions[i])
                                .font(.subheadline)
                                .foregroundColor(checked ? .secondary : .white)
                                .strikethrough(checked, color: .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(12)
                        .background(checked
                            ? Color.teal.opacity(0.08)
                            : Color.card)
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .animation(.easeInOut(duration: 0.2), value: checked)
                    }
                }

                // Actions progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.teal.opacity(0.15)).frame(height: 6)
                        Capsule().fill(Color.teal)
                            .frame(width: geo.size.width * CGFloat(reportVM.actionProgress),
                                   height: 6)
                            .animation(.easeOut(duration: 0.4), value: reportVM.actionProgress)
                    }
                }
                .frame(height: 6)
                .padding(.horizontal)
            }
        }
    }

    // MARK: Local recommendation engine
    var localRecommendationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Workout Recommendation", systemImage: "wand.and.stars")
                    .font(.headline).foregroundColor(.white)
                Spacer()
                if recommendationVM.isLoading {
                    ProgressView().tint(.accent)
                }
            }
            .padding(.horizontal)

            recommendationControls

            Button { showRecommendationDetail = recommendationVM.plan != nil } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.teal.opacity(0.18))
                            .frame(width: 48, height: 48)
                        Image(systemName: "figure.run.circle.fill")
                            .font(.title2).foregroundColor(.teal)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recommendationVM.plan?.title ?? "Preparing local plan")
                            .font(.subheadline.bold()).foregroundColor(.white)
                        if let plan = recommendationVM.plan {
                            Text("\(plan.durationMinutes)m · \(Int(plan.estimatedCalories)) kcal · \(plan.sourceProvider)")
                                .font(.caption).foregroundColor(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        } else {
                            Text("Uses today's active energy and local safety rules")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(16).background(Color.card).cornerRadius(16).padding(.horizontal)
            }
            .disabled(recommendationVM.plan == nil)
        }
    }

    var recommendationControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(WorkoutIntensity.allCases) { intensity in
                    Button {
                        recommendationVM.preferredIntensity = intensity
                        recommendationVM.refresh(snapshot: snap)
                    } label: {
                        Text(intensity.rawValue)
                            .font(.caption.bold())
                            .foregroundColor(recommendationVM.preferredIntensity == intensity ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(recommendationVM.preferredIntensity == intensity ? Color.accent : Color.bg)
                            .cornerRadius(8)
                    }
                }
            }

            HStack {
                Label("Time", systemImage: "timer")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Stepper("\(recommendationVM.availableMinutes) min", value: $recommendationVM.availableMinutes, in: 10...120, step: 5)
                    .labelsHidden()
                    .onChange(of: recommendationVM.availableMinutes) { _ in
                        recommendationVM.refresh(snapshot: snap)
                    }
                Text("\(recommendationVM.availableMinutes)m")
                    .font(.caption.bold()).foregroundColor(.white)
                    .frame(width: 40, alignment: .trailing)
            }

            Picker("Equipment", selection: $recommendationVM.availableEquipment) {
                Text("No equipment").tag("Bodyweight / No equipment")
                Text("Dumbbells").tag("Dumbbells & Bench only")
                Text("Full gym").tag("Full Gym (barbells, machines, cables)")
            }
            .pickerStyle(.segmented)
            .onChange(of: recommendationVM.availableEquipment) { _ in
                recommendationVM.refresh(snapshot: snap)
            }
        }
        .padding(12)
        .background(Color.card)
        .cornerRadius(14)
        .padding(.horizontal)
    }

    // MARK: Report card
    var reportCard: some View {
        Button { selectedTab = 4 } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [.accent, .teal],
                              startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 48, height: 48)
                    Image(systemName: "doc.text.fill")
                        .font(.title3).foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(reportVM.report != nil
                         ? "View Your Coaching Report"
                         : "Load Your AI Coaching Report")
                        .font(.subheadline.bold()).foregroundColor(.white)
                    Text(reportVM.report != nil
                         ? "Goals synced from your .md report →"
                         : "Run python get_plan.py, then import here →")
                        .font(.caption).foregroundColor(.accent)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(16).background(Color.card).cornerRadius(16).padding(.horizontal)
        }
    }

    // MARK: Today's workout
    var todayWorkout: WorkoutDay? {
        let wd  = Calendar.current.component(.weekday, from: Date())
        let idx = (wd + 5) % 7
        let days = workoutVM.activePlan.days
        return idx < days.count ? days[idx] : nil
    }

    func todayWorkoutCard(_ day: WorkoutDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Today — \(day.focus)", systemImage: "checkmark.circle")
                .font(.headline).foregroundColor(.white)
            if day.isRest {
                Text("🛋️ Rest day. Recovery is part of the plan!")
                    .foregroundColor(.secondary).font(.subheadline)
            } else {
                ForEach(day.exercises.prefix(3)) { ex in
                    HStack {
                        Image(systemName: ex.icon).foregroundColor(.accent).frame(width: 24)
                        Text(ex.name).foregroundColor(.white).font(.subheadline)
                        Spacer()
                        Text("\(ex.sets)×\(ex.reps)").foregroundColor(.secondary).font(.caption)
                    }
                }
                if day.exercises.count > 3 {
                    Text("+\(day.exercises.count - 3) more")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(16).background(Color.card).cornerRadius(16).padding(.horizontal)
    }

    // MARK: Quick stats
    var quickStatsRow: some View {
        HStack(spacing: 12) {
            QuickStat(icon: "moon.stars.fill", color: .accent,
                      value: snap.sleepHours > 0 ? String(format: "%.1fh", snap.sleepHours) : "--", label: "Sleep")
            QuickStat(icon: "calendar",        color: .teal,
                      value: "\(workoutVM.activePlan.weeks)w", label: "Plan")
            QuickStat(icon: "figure.run",      color: .amber,
                      value: "\(snap.activeMinutes)m", label: "Active")
        }.padding(.horizontal)
    }

    var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "morning ☀️" : h < 17 ? "afternoon ⚡" : "evening 🌙"
    }
}

// MARK: - Goal Metric Card
struct GoalMetricCard: View {
    let icon: String; let color: Color; let title: String
    let value: String; let subtitle: String; let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundColor(color).font(.subheadline)
                Spacer()
            }
            Text(value).font(.title2.bold()).foregroundColor(.white)
            Text(title).font(.caption2.bold()).foregroundColor(.secondary)
            Text(subtitle).font(.caption2).foregroundColor(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            if let p = progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(color.opacity(0.15)).frame(height: 5)
                        Capsule().fill(color)
                            .frame(width: geo.size.width * CGFloat(p), height: 5)
                            .animation(.easeOut(duration: 0.6), value: p)
                    }
                }.frame(height: 5)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card).cornerRadius(14)
    }
}

// MARK: - Quick Stat
struct QuickStat: View {
    let icon: String; let color: Color; let value: String; let label: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundColor(color)
            Text(value).font(.headline).foregroundColor(.white)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(14)
        .background(Color.card).cornerRadius(14)
    }
}

struct WorkoutRecommendationDetailView: View {
    let plan: WorkoutPlan
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var trackingBlock: ExerciseBlock?
    @State private var completedBlocks: Set<UUID> = []

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.title)
                                .font(.title2.bold()).foregroundColor(.white)
                            Text("\(plan.durationMinutes) min · \(Int(plan.estimatedCalories)) kcal · \(plan.intensity.rawValue)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2).foregroundColor(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Plan Blocks", systemImage: "list.bullet.rectangle")
                            .font(.headline).foregroundColor(.white)
                        ForEach(plan.exercises) { block in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(block.name).font(.subheadline.bold()).foregroundColor(.white)
                                    Spacer()
                                    Text("\(block.durationMinutes)m")
                                        .font(.caption.bold()).foregroundColor(.accent)
                                }
                                Text("\(Int(block.estimatedCalories)) kcal · \(block.equipment)")
                                    .font(.caption).foregroundColor(.secondary)
                                Text(block.instructions)
                                    .font(.caption).foregroundColor(.white)
                                Text(block.safetyCue)
                                    .font(.caption2).foregroundColor(.amber)
                                
                                HStack {
                                    if TrackableExercise.from(name: block.name) != nil, !completedBlocks.contains(block.id) {
                                        Button {
                                            trackingBlock = block
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "camera.fill")
                                                Text("Track")
                                            }
                                            .font(.caption2.bold())
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                LinearGradient(colors: [.accent, .teal],
                                                    startPoint: .leading, endPoint: .trailing)
                                            )
                                            .cornerRadius(8)
                                        }
                                    }
                                    Spacer()
                                    if completedBlocks.contains(block.id) {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(.teal)
                                    }
                                }
                                .padding(.top, 4)
                            }
                            .padding(12).background(Color.card).cornerRadius(12)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Safety Notes", systemImage: "checkmark.shield.fill")
                            .font(.headline).foregroundColor(.white)
                        ForEach(plan.safetyNotes, id: \.self) { note in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption).foregroundColor(.teal)
                                    .padding(.top, 2)
                                Text(note).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(14).background(Color.card).cornerRadius(14)

                    Text("Source: \(plan.sourceProvider)")
                        .font(.caption2).foregroundColor(.secondary)

                    Button(action: onComplete) {
                        Label("Mark Recommendation Complete", systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(14)
                            .background(Color.teal).cornerRadius(14)
                    }
                }
                .padding()
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $trackingBlock) { block in
            if let trackable = TrackableExercise.from(name: block.name) {
                // For recommendations, we default to 1 set of 10 if not specified, or base it on duration
                let estimatedReps = max(10, block.durationMinutes * 5)
                ExerciseTrackingView(
                    exercise: trackable,
                    targetReps: estimatedReps,
                    targetSets: 1
                ) { _ in
                    completedBlocks.insert(block.id)
                }
            }
        }
    }
}
