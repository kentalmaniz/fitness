// GetPlanView.swift — 5-step intake form that calls crew_server /report
// Replaces the terminal-based get_plan.py with a native in-app experience.
import SwiftUI

// MARK: - Main View
struct GetPlanView: View {
    @EnvironmentObject var dashVM:   DashboardViewModel
    @EnvironmentObject var reportVM: ReportViewModel
    @EnvironmentObject var workoutVM: WorkoutViewModel

    @State private var step: Int = 0
    @State private var intake = IntakeData()
    @State private var isGenerating = false
    @State private var generationError: String? = nil
    @State private var showSuccess = false
    @State private var agentProgress: String = ""

    // Server URL — change for real-device testing
    @AppStorage("crewServerURL") private var serverURL: String = "http://localhost:8000"
    @State private var showServerConfig = false
    @State private var serverCheckStatus: String? = nil
    @State private var isCheckingServer = false

    private let totalSteps = 5
    private let stepTitles = [
        "Personal Info", "Goals & Schedule",
        "Health Metrics", "Nutrition", "Lifestyle"
    ]
    private let stepIcons = [
        "person.fill", "target", "heart.fill", "fork.knife", "leaf.fill"
    ]

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                topBar
                // Step indicator
                stepIndicator
                    .padding(.top, 8)

                // Content
                TabView(selection: $step) {
                    personalInfoStep.tag(0)
                    goalsStep.tag(1)
                    healthMetricsStep.tag(2)
                    nutritionStep.tag(3)
                    lifestyleStep.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: step)

                // Navigation buttons
                bottomButtons
            }

            // Loading overlay
            if isGenerating {
                generatingOverlay
            }
        }
        .sheet(isPresented: $showServerConfig) {
            serverConfigSheet
        }
        .alert("Report Generated! 🎉", isPresented: $showSuccess) {
            Button("OK") { }
        } message: {
            Text("Your personalized plan was saved as a .md file, loaded into AI Report, and added to the Plan tab.")
        }
        .alert("Generation Error", isPresented: .constant(generationError != nil)) {
            Button("OK") { generationError = nil }
        } message: {
            Text(generationError ?? "")
        }
    }

    // MARK: - Top Bar
    var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Get Your Plan")
                    .font(.title2.bold()).foregroundColor(.white)
                Text("Step \(step + 1) of \(totalSteps) — \(stepTitles[step])")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button { showServerConfig = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.subheadline).foregroundColor(.secondary)
                    .padding(10)
                    .background(Color.card).cornerRadius(10)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Step Indicator
    var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(i <= step ? Color.accent : Color.card)
                            .frame(width: 36, height: 36)
                        if i < step {
                            Image(systemName: "checkmark")
                                .font(.caption.bold()).foregroundColor(.white)
                        } else {
                            Image(systemName: stepIcons[i])
                                .font(.caption2).foregroundColor(i == step ? .white : .secondary)
                        }
                    }
                    Text(stepTitles[i])
                        .font(.system(size: 9)).foregroundColor(i <= step ? .white : .secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                if i < totalSteps - 1 {
                    Rectangle()
                        .fill(i < step ? Color.accent : Color.card)
                        .frame(height: 2)
                        .frame(maxWidth: 20)
                        .padding(.bottom, 16)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Bottom Buttons
    var bottomButtons: some View {
        HStack(spacing: 14) {
            if step > 0 {
                Button {
                    withAnimation { step -= 1 }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.headline).foregroundColor(.accent)
                    .frame(maxWidth: .infinity).padding(14)
                    .background(Color.card).cornerRadius(14)
                }
            }

            if step < totalSteps - 1 {
                Button {
                    withAnimation { step += 1 }
                } label: {
                    HStack(spacing: 6) {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                    .font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(14)
                    .background(LinearGradient(colors: [.accent, .teal],
                        startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(14)
                }
            } else {
                Button { generateReport() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Generate Plan")
                    }
                    .font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(14)
                    .background(LinearGradient(colors: [.accent, Color.teal],
                        startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(14)
                }
                .disabled(isGenerating)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
    }

    // MARK: - Step 1: Personal Info
    var personalInfoStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                sectionCard {
                    VStack(spacing: 16) {
                        iconHeader(icon: "person.fill", title: "About You", color: .accent)

                        FormField(label: "First Name", icon: "person.text.rectangle") {
                            TextField("Your name", text: $intake.name)
                                .textFieldStyle(.plain).foregroundColor(.white)
                        }

                        FormField(label: "Age", icon: "calendar") {
                            HStack {
                                TextField("28", value: $intake.age, format: .number)
                                    .textFieldStyle(.plain).foregroundColor(.white)
                                    .keyboardType(.numberPad)
                                Text("years").font(.caption).foregroundColor(.secondary)
                            }
                        }

                        FormField(label: "Weight", icon: "scalemass.fill") {
                            HStack {
                                TextField("75", value: $intake.weightKg, format: .number)
                                    .textFieldStyle(.plain).foregroundColor(.white)
                                    .keyboardType(.decimalPad)
                                Text("kg").font(.caption).foregroundColor(.secondary)
                            }
                        }

                        FormField(label: "Height", icon: "ruler.fill") {
                            HStack {
                                TextField("175", value: $intake.heightCm, format: .number)
                                    .textFieldStyle(.plain).foregroundColor(.white)
                                    .keyboardType(.decimalPad)
                                Text("cm").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // BMI preview card
                if intake.heightCm > 0 && intake.weightKg > 0 {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(bmiColor.opacity(0.2))
                                .frame(width: 50, height: 50)
                            Text(String(format: "%.1f", intake.bmi))
                                .font(.headline.bold()).foregroundColor(bmiColor)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("BMI").font(.subheadline.bold()).foregroundColor(.white)
                            Text(bmiLabel).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(16).background(Color.card).cornerRadius(14)
                    .padding(.horizontal)
                }
            }
            .padding(.top, 12).padding(.bottom, 80)
        }
    }

    // MARK: - Step 2: Goals & Schedule
    var goalsStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                sectionCard {
                    VStack(spacing: 16) {
                        iconHeader(icon: "target", title: "Your Goals", color: .teal)

                        FormPicker(label: "Primary Goal", selection: $intake.goal,
                            options: ["Weight Loss", "Muscle Gain", "Endurance",
                                      "Flexibility & Mobility", "General Fitness"])

                        FormPicker(label: "Fitness Level", selection: $intake.level,
                            options: ["Beginner (0-6 months)",
                                      "Intermediate (6 months-2 years)",
                                      "Advanced (2+ years)"])

                        FormPicker(label: "Equipment", selection: $intake.equipment,
                            options: ["Full Gym (barbells, machines, cables)",
                                      "Dumbbells & Bench only",
                                      "Resistance Bands only",
                                      "Bodyweight / No equipment"])
                    }
                }

                sectionCard {
                    VStack(spacing: 16) {
                        iconHeader(icon: "calendar.badge.clock", title: "Schedule", color: .amber)

                        FormStepper(label: "Days per week", value: $intake.daysPerWeek,
                                    range: 1...7, icon: "calendar")
                        FormStepper(label: "Session length (min)", value: $intake.sessionMins,
                                    range: 15...180, step: 15, icon: "timer")
                        FormStepper(label: "Target weeks", value: $intake.targetWeeks,
                                    range: 1...52, icon: "flag.fill")
                    }
                }

                sectionCard {
                    VStack(spacing: 16) {
                        iconHeader(icon: "chart.bar.fill", title: "Current Progress", color: .accent)

                        FormStepper(label: "Weeks training so far", value: $intake.weeksActive,
                                    range: 0...520, icon: "clock.fill")
                        FormStepper(label: "Total workouts done", value: $intake.workoutsDone,
                                    range: 0...5000, icon: "dumbbell.fill")
                        FormStepper(label: "Current streak (days)", value: $intake.streakDays,
                                    range: 0...365, icon: "flame.fill")
                    }
                }
            }
            .padding(.top, 12).padding(.bottom, 80)
        }
    }

    // MARK: - Step 3: Health Metrics
    var healthMetricsStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Auto-fill banner
                if dashVM.snapshot.connectionStatus == .connected {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.text.square.fill")
                            .foregroundColor(.teal).font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("HealthKit Connected")
                                .font(.caption.bold()).foregroundColor(.teal)
                            Text("Steps, calories & heart rate auto-filled from Health.")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Refresh") { autoFillHealthKit() }
                            .font(.caption.bold()).foregroundColor(.accent)
                    }
                    .padding(12).background(Color.teal.opacity(0.1))
                    .cornerRadius(12).padding(.horizontal)
                }

                sectionCard {
                    VStack(spacing: 16) {
                        iconHeader(icon: "heart.fill", title: "Health Metrics", color: .red)

                        FormField(label: "Steps today", icon: "figure.walk") {
                            TextField("8000", value: $intake.steps, format: .number)
                                .textFieldStyle(.plain).foregroundColor(.white)
                                .keyboardType(.numberPad)
                        }

                        FormField(label: "Active calories (kcal)", icon: "flame.fill") {
                            TextField("400", value: $intake.calories, format: .number)
                                .textFieldStyle(.plain).foregroundColor(.white)
                                .keyboardType(.decimalPad)
                        }

                        FormField(label: "Resting heart rate (bpm)", icon: "heart.fill") {
                            TextField("65", value: $intake.heartRate, format: .number)
                                .textFieldStyle(.plain).foregroundColor(.white)
                                .keyboardType(.decimalPad)
                        }

                        FormField(label: "Sleep last night (hours)", icon: "moon.stars.fill") {
                            TextField("7.5", value: $intake.sleepHours, format: .number)
                                .textFieldStyle(.plain).foregroundColor(.white)
                                .keyboardType(.decimalPad)
                        }

                        FormField(label: "Active minutes today", icon: "figure.run") {
                            TextField("30", value: $intake.activeMinutes, format: .number)
                                .textFieldStyle(.plain).foregroundColor(.white)
                                .keyboardType(.numberPad)
                        }
                    }
                }
            }
            .padding(.top, 12).padding(.bottom, 80)
        }
        .onAppear { autoFillHealthKit() }
    }

    // MARK: - Step 4: Nutrition
    var nutritionStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                sectionCard {
                    VStack(spacing: 16) {
                        iconHeader(icon: "fork.knife", title: "Nutrition", color: .amber)

                        FormPicker(label: "Dietary Preference", selection: $intake.diet,
                            options: ["No restrictions (Omnivore)", "Vegetarian", "Vegan",
                                      "Pescatarian", "Keto / Low-carb", "Gluten-free"])

                        FormStepper(label: "Meals per day", value: $intake.mealsPerDay,
                                    range: 1...8, icon: "fork.knife")

                        FormField(label: "Water intake (liters)", icon: "drop.fill") {
                            TextField("2.0", value: $intake.waterLiters, format: .number)
                                .textFieldStyle(.plain).foregroundColor(.white)
                                .keyboardType(.decimalPad)
                        }

                        FormField(label: "Food allergies / avoid", icon: "exclamationmark.triangle.fill") {
                            TextField("None", text: $intake.allergies)
                                .textFieldStyle(.plain).foregroundColor(.white)
                        }

                        FormField(label: "Supplements", icon: "pills.fill") {
                            TextField("None", text: $intake.supplements)
                                .textFieldStyle(.plain).foregroundColor(.white)
                        }
                    }
                }
            }
            .padding(.top, 12).padding(.bottom, 80)
        }
    }

    // MARK: - Step 5: Lifestyle
    var lifestyleStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                sectionCard {
                    VStack(spacing: 16) {
                        iconHeader(icon: "leaf.fill", title: "Lifestyle", color: .teal)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Stress Level").font(.subheadline).foregroundColor(.white)
                                Spacer()
                                Text("\(intake.stressLevel)/10")
                                    .font(.subheadline.bold())
                                    .foregroundColor(intake.stressLevel > 7 ? .red : intake.stressLevel > 4 ? .amber : .teal)
                            }
                            Slider(value: Binding(
                                get: { Double(intake.stressLevel) },
                                set: { intake.stressLevel = Int($0) }
                            ), in: 1...10, step: 1)
                            .tint(.accent)

                            HStack {
                                Text("Low").font(.caption2).foregroundColor(.secondary)
                                Spacer()
                                Text("Very High").font(.caption2).foregroundColor(.secondary)
                            }
                        }

                        FormField(label: "Injuries / limitations", icon: "bandage.fill") {
                            TextField("None", text: $intake.injuries)
                                .textFieldStyle(.plain).foregroundColor(.white)
                        }

                        FormField(label: "Other goals or notes", icon: "text.bubble.fill") {
                            TextField("Improve overall health...", text: $intake.extraGoals)
                                .textFieldStyle(.plain).foregroundColor(.white)
                        }
                    }
                }

                // Summary card
                summaryPreview
            }
            .padding(.top, 12).padding(.bottom, 80)
        }
    }

    // MARK: - Summary Preview
    var summaryPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            iconHeader(icon: "checkmark.seal.fill", title: "Review Summary", color: .accent)

            Group {
                summaryRow("Name", intake.name)
                summaryRow("Age", "\(intake.age) yrs")
                summaryRow("Body", "\(String(format: "%.0f", intake.weightKg))kg / \(String(format: "%.0f", intake.heightCm))cm — BMI \(String(format: "%.1f", intake.bmi))")
                summaryRow("Goal", "\(intake.goal) in \(intake.targetWeeks) weeks")
                summaryRow("Level", intake.level)
                summaryRow("Schedule", "\(intake.daysPerWeek)×/week, \(intake.sessionMins) min")
                summaryRow("Diet", intake.diet)
                summaryRow("Metrics", "\(intake.steps) steps · \(Int(intake.calories)) cal · \(Int(intake.heartRate)) bpm")
            }
        }
        .padding(16).background(Color.card).cornerRadius(14).padding(.horizontal)
    }

    // MARK: - Generating Overlay
    var generatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .stroke(Color.accent.opacity(0.2), lineWidth: 6)
                        .frame(width: 80, height: 80)
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(LinearGradient(colors: [.accent, .teal],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .modifier(SpinModifier())
                    Image(systemName: "sparkles")
                        .font(.title2).foregroundColor(.accent)
                }

                Text("Generating Your Plan")
                    .font(.title3.bold()).foregroundColor(.white)

                VStack(spacing: 8) {
                    Text(agentProgress)
                        .font(.subheadline).foregroundColor(.accent)
                        .animation(.easeInOut, value: agentProgress)
                    Text("Our 3 AI agents are crafting your\npersonalized coaching report…")
                        .font(.caption).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Text("This may take 30–60 seconds")
                    .font(.caption2).foregroundColor(.secondary.opacity(0.7))
            }
            .padding(40)
            .background(Color.card.opacity(0.95))
            .cornerRadius(24)
        }
    }

    // MARK: - Server Config Sheet
    var serverConfigSheet: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Server Configuration")
                    .font(.title3.bold()).foregroundColor(.white)

                Text("Enter the URL of your Mac running crew_server.py")
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                TextField("http://localhost:8000", text: $serverURL)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .padding(14)
                    .background(Color.card)
                    .cornerRadius(12)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Tips").font(.caption.bold()).foregroundColor(.accent)
                    Text("• Use localhost for Simulator testing")
                        .font(.caption2).foregroundColor(.secondary)
                    Text("• Use your Mac's IP (e.g. 192.168.1.x) for iPhone")
                        .font(.caption2).foregroundColor(.secondary)
                    Text("• Start the server with fitness_crew/run_server.sh")
                        .font(.caption2).foregroundColor(.secondary)
                }
                .padding(12).background(Color.card).cornerRadius(10)

                if let serverCheckStatus {
                    Text(serverCheckStatus)
                        .font(.caption)
                        .foregroundColor(serverCheckStatus.hasPrefix("Connected") ? .teal : .amber)
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color.card)
                        .cornerRadius(10)
                }

                Button { checkServer() } label: {
                    HStack {
                        if isCheckingServer {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "network")
                        }
                        Text(isCheckingServer ? "Checking..." : "Test Connection")
                    }
                    .font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(14)
                    .background(Color.teal).cornerRadius(14)
                }
                .disabled(isCheckingServer)

                Button {
                    CrewAPIService.baseURL = serverURL
                    showServerConfig = false
                } label: {
                    Text("Save").font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(14)
                        .background(Color.accent).cornerRadius(14)
                }
            }
            .padding(24)
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    // MARK: - Helpers

    var bmiColor: Color {
        let b = intake.bmi
        if b < 18.5 { return .amber }
        if b < 25   { return .teal }
        if b < 30   { return .amber }
        return .red
    }

    var bmiLabel: String {
        let b = intake.bmi
        if b < 18.5 { return "Underweight" }
        if b < 25   { return "Normal weight" }
        if b < 30   { return "Overweight" }
        return "Obese"
    }

    func autoFillHealthKit() {
        let snap = dashVM.snapshot
        if snap.connectionStatus == .connected {
            intake.steps     = Int(snap.steps)
            intake.calories  = snap.calories
            intake.heartRate = snap.heartRate
            intake.sleepHours = snap.sleepHours > 0 ? snap.sleepHours : intake.sleepHours
            intake.activeMinutes = snap.activeMinutes > 0 ? snap.activeMinutes : intake.activeMinutes
        }
    }

    func generateReport() {
        isGenerating = true
        agentProgress = "⏳ HealthKitAgent — analysing metrics…"
        CrewAPIService.baseURL = serverURL

        Task {
            do {
                // Simulate progress updates
                try await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { agentProgress = "🏋️ UIAgent — building your plan…" }

                let markdown = try await CrewAPIService.generateReport(intake: intake)

                await MainActor.run {
                    agentProgress = "✅ QAAgent — finalizing report…"
                }
                try await Task.sleep(nanoseconds: 500_000_000)

                await MainActor.run {
                    do {
                        let report = try reportVM.importGeneratedReport(markdown, preferredName: intake.name)
                        workoutVM.installGeneratedPlan(from: report, intake: intake)
                        dashVM.syncGoals(calGoal: report.calGoalValue, stepGoal: report.stepGoalValue)
                    } catch {
                        generationError = "The plan was generated, but saving it inside the app failed: \(error.localizedDescription)"
                    }
                    isGenerating = false
                    showSuccess = generationError == nil
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    generationError = error.localizedDescription
                }
            }
        }
    }

    func checkServer() {
        isCheckingServer = true
        serverCheckStatus = nil
        Task {
            do {
                CrewAPIService.baseURL = serverURL
                _ = try await CrewAPIService.checkHealth(baseURL: serverURL)
                await MainActor.run {
                    serverCheckStatus = "Connected to \(serverURL)"
                    isCheckingServer = false
                }
            } catch {
                await MainActor.run {
                    serverCheckStatus = error.localizedDescription
                    isCheckingServer = false
                }
            }
        }
    }

    // Reusable UI components

    func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16).background(Color.card).cornerRadius(16).padding(.horizontal)
    }

    func iconHeader(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.2))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.subheadline).foregroundColor(color)
            }
            Text(title).font(.headline).foregroundColor(.white)
            Spacer()
        }
    }

    func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value).font(.caption.bold()).foregroundColor(.white)
            Spacer()
        }
    }
}

// MARK: - Form Components

struct FormField<Content: View>: View {
    let label: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.caption).foregroundColor(.secondary)
            content
                .padding(12)
                .background(Color.bg)
                .cornerRadius(10)
        }
    }
}

struct FormPicker: View {
    let label: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).foregroundColor(.secondary)
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selection == option ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selection == option ? .accent : .secondary)
                            .font(.subheadline)
                        Text(option)
                            .font(.subheadline)
                            .foregroundColor(selection == option ? .white : .secondary)
                        Spacer()
                    }
                    .padding(10)
                    .background(selection == option ? Color.accent.opacity(0.12) : Color.bg)
                    .cornerRadius(10)
                }
            }
        }
    }
}

struct FormStepper: View {
    let label: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...100
    var step: Int = 1
    var icon: String = "number"

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.caption).foregroundColor(.secondary)
            Spacer()
            HStack(spacing: 12) {
                Button {
                    if value - step >= range.lowerBound { value -= step }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.secondary).font(.title3)
                }
                Text("\(value)")
                    .font(.subheadline.bold()).foregroundColor(.white)
                    .frame(minWidth: 36)
                Button {
                    if value + step <= range.upperBound { value += step }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accent).font(.title3)
                }
            }
        }
    }
}

// MARK: - Spin animation
struct SpinModifier: ViewModifier {
    @State private var rotation: Double = 0
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
