// ExerciseTracker.swift — Angle-based rep counting engine + form feedback
// Works with body pose data from PoseDetector
import Foundation
import Vision

// MARK: - Trackable Exercise Definitions

enum TrackableExercise: String, CaseIterable, Identifiable, Codable {
    case squat       = "Squat"
    case pushUp      = "Push-Up"
    case jumpingJack = "Jumping Jack"
    case lunge       = "Lunge"
    case plank       = "Plank"
    case shoulderPress = "Shoulder Press"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .squat:         return "figure.strengthtraining.traditional"
        case .pushUp:        return "figure.arms.open"
        case .jumpingJack:   return "figure.jumprope"
        case .lunge:         return "figure.strengthtraining.functional"
        case .plank:         return "figure.core.training"
        case .shoulderPress: return "figure.strengthtraining.functional"
        }
    }

    var isHoldExercise: Bool { self == .plank }

    var instruction: String {
        switch self {
        case .squat:         return "Stand facing the camera. Bend your knees and lower your hips."
        case .pushUp:        return "Position your phone to see your side profile."
        case .jumpingJack:   return "Stand facing the camera with arms at your sides."
        case .lunge:         return "Stand sideways to the camera. Step forward and lower."
        case .plank:         return "Position your phone to see your side profile."
        case .shoulderPress: return "Stand facing the camera with weights at shoulder height."
        }
    }

    /// Try to match an exercise name to a trackable exercise.
    static func from(name: String) -> TrackableExercise? {
        let lower = name.lowercased()
        if lower.contains("squat") && !lower.contains("jump") { return .squat }
        if lower.contains("push-up") || lower.contains("push up") || lower.contains("pushup") { return .pushUp }
        if lower.contains("jumping jack") || lower.contains("star jump") { return .jumpingJack }
        if lower.contains("lunge") { return .lunge }
        if lower.contains("plank") { return .plank }
        if lower.contains("shoulder press") || lower.contains("ohp") || lower.contains("overhead press") { return .shoulderPress }
        return nil
    }
}

// MARK: - Angle Calculator

struct AngleCalculator {
    /// Calculate the angle at point B formed by points A-B-C, in degrees.
    static func angle(a: CGPoint, b: CGPoint, c: CGPoint) -> Double {
        let vectorBA = CGPoint(x: a.x - b.x, y: a.y - b.y)
        let vectorBC = CGPoint(x: c.x - b.x, y: c.y - b.y)

        let dot = Double(vectorBA.x * vectorBC.x + vectorBA.y * vectorBC.y)
        let magBA = sqrt(Double(vectorBA.x * vectorBA.x + vectorBA.y * vectorBA.y))
        let magBC = sqrt(Double(vectorBC.x * vectorBC.x + vectorBC.y * vectorBC.y))

        guard magBA > 0, magBC > 0 else { return 0 }
        let cosAngle = max(-1, min(1, dot / (magBA * magBC)))
        return acos(cosAngle) * 180.0 / .pi
    }
}

// MARK: - Rep Phase (state machine)

enum RepPhase: Equatable {
    case ready       // Waiting for starting position
    case phaseA      // First phase (e.g. standing for squat)
    case phaseB      // Second phase (e.g. lowered for squat)
}

// MARK: - Form Quality

enum FormQuality: String {
    case good   = "Good"
    case fair   = "Fair"
    case poor   = "Poor"

    var color: String {
        switch self {
        case .good: return "teal"
        case .fair: return "amber"
        case .poor: return "red"
        }
    }
}

// MARK: - Tracking Session Result

struct TrackingSessionResult: Identifiable, Codable {
    var id = UUID()
    var exerciseName: String
    var repsCompleted: Int
    var targetReps: Int
    var setsCompleted: Int
    var targetSets: Int
    var durationSeconds: Int
    var estimatedCalories: Double
    var averageFormScore: Double  // 0-1
    var completedAt: Date = Date()
}

// MARK: - Exercise Tracker (Main Engine)

final class ExerciseTracker: ObservableObject {
    @Published var currentExercise: TrackableExercise
    @Published var repsInCurrentSet: Int = 0
    @Published var currentSet: Int = 1
    @Published var targetReps: Int
    @Published var targetSets: Int
    @Published var phase: RepPhase = .ready
    @Published var formFeedback: String = "Get into position"
    @Published var formQuality: FormQuality = .good
    @Published var holdSeconds: Int = 0   // For plank
    @Published var isActive: Bool = false
    @Published var sessionComplete: Bool = false

    var totalRepsCompleted: Int = 0
    private var formScores: [Double] = []
    private var startTime: Date?
    private var holdTimer: Timer?

    // Thresholds — tuned for typical camera angle
    private let phaseAThreshold: Double = 150   // "extended" angle
    private let phaseBThreshold: Double = 100   // "contracted" angle

    // Debounce — prevent double-counting
    private var lastRepTime: Date = .distantPast
    private let repCooldown: TimeInterval = 0.5

    init(exercise: TrackableExercise, targetReps: Int = 10, targetSets: Int = 3) {
        self.currentExercise = exercise
        self.targetReps = targetReps
        self.targetSets = targetSets
    }

    func start() {
        isActive = true
        startTime = Date()
        phase = .ready
        repsInCurrentSet = 0
        currentSet = 1
        totalRepsCompleted = 0
        formScores = []
        holdSeconds = 0
        sessionComplete = false

        if currentExercise.isHoldExercise {
            startHoldTimer()
        }
    }

    func stop() -> TrackingSessionResult {
        isActive = false
        holdTimer?.invalidate()
        holdTimer = nil

        let duration = Int(Date().timeIntervalSince(startTime ?? Date()))
        let avgForm = formScores.isEmpty ? 0.7 : formScores.reduce(0, +) / Double(formScores.count)
        let calories = estimateCalories(exercise: currentExercise, durationSeconds: duration)

        return TrackingSessionResult(
            exerciseName: currentExercise.displayName,
            repsCompleted: totalRepsCompleted,
            targetReps: targetReps * targetSets,
            setsCompleted: currentSet,
            targetSets: targetSets,
            durationSeconds: duration,
            estimatedCalories: calories,
            averageFormScore: avgForm
        )
    }

    // MARK: - Process Pose (called each frame)

    func processPose(_ pose: BodyPose) {
        guard isActive else { return }

        switch currentExercise {
        case .squat:       processSquat(pose)
        case .pushUp:      processPushUp(pose)
        case .jumpingJack: processJumpingJack(pose)
        case .lunge:       processLunge(pose)
        case .plank:       processPlank(pose)
        case .shoulderPress: processShoulderPress(pose)
        }
    }

    // MARK: - Squat Detection

    private func processSquat(_ pose: BodyPose) {
        // Use right side (or left if right not visible)
        guard let hip = pose.joint(.rightHip) ?? pose.joint(.leftHip),
              let knee = pose.joint(.rightKnee) ?? pose.joint(.leftKnee),
              let ankle = pose.joint(.rightAnkle) ?? pose.joint(.leftAnkle) else {
            formFeedback = "Position your full body in frame"
            return
        }

        let kneeAngle = AngleCalculator.angle(a: hip.point, b: knee.point, c: ankle.point)
        evaluateSquatForm(kneeAngle: kneeAngle, pose: pose)

        switch phase {
        case .ready:
            if kneeAngle > phaseAThreshold {
                phase = .phaseA
                formFeedback = "Standing — now squat down"
            } else {
                formFeedback = "Stand up straight to begin"
            }
        case .phaseA:
            if kneeAngle < phaseBThreshold {
                phase = .phaseB
                formFeedback = "Good depth! Now stand back up"
            } else if kneeAngle < 130 {
                formFeedback = "Keep going lower…"
            }
        case .phaseB:
            if kneeAngle > phaseAThreshold {
                countRep()
                phase = .phaseA
            }
        }
    }

    private func evaluateSquatForm(kneeAngle: Double, pose: BodyPose) {
        // Check if shoulders are roughly above hips (not leaning too far forward)
        if let shoulder = pose.joint(.rightShoulder) ?? pose.joint(.leftShoulder),
           let hip = pose.joint(.rightHip) ?? pose.joint(.leftHip) {
            let forwardLean = abs(shoulder.point.x - hip.point.x)
            if forwardLean > 0.15 {
                formQuality = .fair
                formFeedback = "Keep your chest up — try not to lean forward"
                formScores.append(0.5)
                return
            }
        }
        formQuality = .good
        formScores.append(1.0)
    }

    // MARK: - Push-Up Detection (side view)

    private func processPushUp(_ pose: BodyPose) {
        guard let shoulder = pose.joint(.rightShoulder) ?? pose.joint(.leftShoulder),
              let elbow = pose.joint(.rightElbow) ?? pose.joint(.leftElbow),
              let wrist = pose.joint(.rightWrist) ?? pose.joint(.leftWrist) else {
            formFeedback = "Show your side profile to the camera"
            return
        }

        let elbowAngle = AngleCalculator.angle(a: shoulder.point, b: elbow.point, c: wrist.point)

        switch phase {
        case .ready:
            if elbowAngle > phaseAThreshold {
                phase = .phaseA
                formFeedback = "Arms extended — lower down"
            } else {
                formFeedback = "Start in a high plank position"
            }
        case .phaseA:
            if elbowAngle < 90 {
                phase = .phaseB
                formFeedback = "Good! Now push back up"
                formScores.append(1.0)
                formQuality = .good
            } else if elbowAngle < 120 {
                formFeedback = "Go a bit lower…"
            }
        case .phaseB:
            if elbowAngle > phaseAThreshold {
                countRep()
                phase = .phaseA
            }
        }
    }

    // MARK: - Jumping Jack Detection (front view)

    private func processJumpingJack(_ pose: BodyPose) {
        guard let leftWrist = pose.joint(.leftWrist),
              let rightWrist = pose.joint(.rightWrist),
              let leftShoulder = pose.joint(.leftShoulder),
              let rightShoulder = pose.joint(.rightShoulder),
              let leftAnkle = pose.joint(.leftAnkle),
              let rightAnkle = pose.joint(.rightAnkle) else {
            formFeedback = "Stand facing the camera, full body in frame"
            return
        }

        // Arms up = wrists above shoulders; legs spread = ankles far apart
        let armsUp = leftWrist.point.y > leftShoulder.point.y
            && rightWrist.point.y > rightShoulder.point.y
        let legsSpread = abs(leftAnkle.point.x - rightAnkle.point.x) > 0.15

        let isOpen = armsUp && legsSpread
        let isClosed = !armsUp && !legsSpread

        switch phase {
        case .ready:
            if isClosed {
                phase = .phaseA
                formFeedback = "Ready — jump out!"
            } else {
                formFeedback = "Stand with arms at your sides"
            }
        case .phaseA:
            if isOpen {
                phase = .phaseB
                formFeedback = "Great! Now jump back in"
                formScores.append(1.0)
                formQuality = .good
            }
        case .phaseB:
            if isClosed {
                countRep()
                phase = .phaseA
            }
        }
    }

    // MARK: - Lunge Detection (side view)

    private func processLunge(_ pose: BodyPose) {
        guard let hip = pose.joint(.rightHip) ?? pose.joint(.leftHip),
              let knee = pose.joint(.rightKnee) ?? pose.joint(.leftKnee),
              let ankle = pose.joint(.rightAnkle) ?? pose.joint(.leftAnkle) else {
            formFeedback = "Stand sideways to the camera"
            return
        }

        let kneeAngle = AngleCalculator.angle(a: hip.point, b: knee.point, c: ankle.point)

        switch phase {
        case .ready:
            if kneeAngle > phaseAThreshold {
                phase = .phaseA
                formFeedback = "Standing — step forward and lower"
            } else {
                formFeedback = "Stand tall to begin"
            }
        case .phaseA:
            if kneeAngle < phaseBThreshold {
                phase = .phaseB
                formFeedback = "Good lunge depth! Stand back up"
                formScores.append(1.0)
                formQuality = .good
            } else if kneeAngle < 130 {
                formFeedback = "Lower a bit more…"
            }
        case .phaseB:
            if kneeAngle > phaseAThreshold {
                countRep()
                phase = .phaseA
            }
        }
    }

    // MARK: - Plank Detection (hold-based, side view)

    private func processPlank(_ pose: BodyPose) {
        guard let shoulder = pose.joint(.rightShoulder) ?? pose.joint(.leftShoulder),
              let hip = pose.joint(.rightHip) ?? pose.joint(.leftHip),
              let ankle = pose.joint(.rightAnkle) ?? pose.joint(.leftAnkle) else {
            formFeedback = "Show your side profile in plank position"
            return
        }

        let bodyAngle = AngleCalculator.angle(a: shoulder.point, b: hip.point, c: ankle.point)

        if bodyAngle > 160 {
            formQuality = .good
            formFeedback = "Great alignment! Hold steady 💪"
            formScores.append(1.0)
        } else if bodyAngle > 140 {
            formQuality = .fair
            formFeedback = "Keep your hips level — don't sag"
            formScores.append(0.6)
        } else {
            formQuality = .poor
            formFeedback = "Hips too low — lift up"
            formScores.append(0.3)
        }

        if phase == .ready {
            phase = .phaseA
        }
    }

    // MARK: - Shoulder Press Detection (front view)

    private func processShoulderPress(_ pose: BodyPose) {
        guard let shoulder = pose.joint(.rightShoulder) ?? pose.joint(.leftShoulder),
              let elbow = pose.joint(.rightElbow) ?? pose.joint(.leftElbow),
              let wrist = pose.joint(.rightWrist) ?? pose.joint(.leftWrist) else {
            formFeedback = "Stand facing the camera with arms raised"
            return
        }

        let elbowAngle = AngleCalculator.angle(a: shoulder.point, b: elbow.point, c: wrist.point)
        // Check if wrists are above head level
        let wristAboveHead = wrist.point.y > (pose.joint(.nose)?.point.y ?? 1.0)

        switch phase {
        case .ready:
            if elbowAngle < 100 {
                phase = .phaseA
                formFeedback = "Arms at shoulders — now press up!"
            } else {
                formFeedback = "Bring weights to shoulder height"
            }
        case .phaseA:
            if elbowAngle > phaseAThreshold && wristAboveHead {
                phase = .phaseB
                formFeedback = "Locked out! Lower back down"
                formScores.append(1.0)
                formQuality = .good
            } else if elbowAngle > 120 {
                formFeedback = "Press higher — extend your arms"
            }
        case .phaseB:
            if elbowAngle < 100 {
                countRep()
                phase = .phaseA
            }
        }
    }

    // MARK: - Rep Counting

    private func countRep() {
        let now = Date()
        guard now.timeIntervalSince(lastRepTime) > repCooldown else { return }
        lastRepTime = now

        repsInCurrentSet += 1
        totalRepsCompleted += 1

        if repsInCurrentSet >= targetReps {
            if currentSet < targetSets {
                currentSet += 1
                repsInCurrentSet = 0
                formFeedback = "Set complete! Rest, then go again"
            } else {
                sessionComplete = true
                formFeedback = "All sets done! Great work! 🎉"
            }
        } else {
            formFeedback = "Rep \(repsInCurrentSet) of \(targetReps) ✓"
        }
    }

    // MARK: - Hold Timer (Plank)

    private func startHoldTimer() {
        holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.isActive else { return }
            DispatchQueue.main.async {
                self.holdSeconds += 1
            }
        }
    }

    // MARK: - Calorie Estimation

    private func estimateCalories(exercise: TrackableExercise, durationSeconds: Int) -> Double {
        let met: Double
        switch exercise {
        case .squat:         met = 5.0
        case .pushUp:        met = 3.8
        case .jumpingJack:   met = 8.0
        case .lunge:         met = 5.0
        case .plank:         met = 3.5
        case .shoulderPress: met = 5.0
        }
        // Conservative: assume 70kg body weight, 0.85 factor
        let caloriesPerMinute = met * 3.5 * 70 / 200
        return (caloriesPerMinute * Double(durationSeconds) / 60.0) * 0.85
    }

    // MARK: - Manual Rep (Simulator fallback)

    func manualAddRep() {
        guard isActive, !sessionComplete else { return }
        formFeedback = "Manual rep counted"
        formQuality = .good
        formScores.append(0.7)
        repsInCurrentSet += 1
        totalRepsCompleted += 1

        if repsInCurrentSet >= targetReps {
            if currentSet < targetSets {
                currentSet += 1
                repsInCurrentSet = 0
                formFeedback = "Set complete! Start next set"
            } else {
                sessionComplete = true
                formFeedback = "All sets done! 🎉"
            }
        }
    }

    func manualUndoRep() {
        guard isActive, repsInCurrentSet > 0 else { return }
        repsInCurrentSet -= 1
        totalRepsCompleted -= 1
        formFeedback = "Rep removed"
    }
}
