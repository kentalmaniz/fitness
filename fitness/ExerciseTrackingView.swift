// ExerciseTrackingView.swift — Full-screen camera tracking experience
// Integrates PoseDetector, ExerciseTracker, and SkeletonOverlayView
import SwiftUI

struct ExerciseTrackingView: View {
    let exercise: TrackableExercise
    let targetReps: Int
    let targetSets: Int
    let onComplete: (TrackingSessionResult) -> Void

    @StateObject private var poseDetector = PoseDetector()
    @StateObject private var tracker: ExerciseTracker
    @Environment(\.dismiss) private var dismiss
    @State private var showResult = false
    @State private var result: TrackingSessionResult?
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?
    @State private var showInstructions = true

    init(exercise: TrackableExercise, targetReps: Int = 10, targetSets: Int = 3,
         onComplete: @escaping (TrackingSessionResult) -> Void) {
        self.exercise = exercise
        self.targetReps = targetReps
        self.targetSets = targetSets
        self.onComplete = onComplete
        _tracker = StateObject(wrappedValue: ExerciseTracker(
            exercise: exercise, targetReps: targetReps, targetSets: targetSets
        ))
    }

    var cameraAvailable: Bool {
        poseDetector.cameraManager.permissionGranted && poseDetector.cameraManager.cameraAvailable
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if cameraAvailable {
                cameraTrackingView
            } else {
                manualTrackingView
            }

            // Top overlay
            VStack {
                topBar
                Spacer()
            }

            // Instructions overlay
            if showInstructions {
                instructionsOverlay
            }

            // Completion overlay
            if showResult, let result {
                completionOverlay(result)
            }
        }
        .onAppear {
            poseDetector.cameraManager.checkPermission()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                poseDetector.start()
            }
        }
        .onDisappear {
            poseDetector.stop()
            timer?.invalidate()
        }
        .onChange(of: poseDetector.currentPose) { pose in
            if let pose {
                tracker.processPose(pose)
            }
        }
        .onChange(of: tracker.sessionComplete) { complete in
            if complete {
                finishSession()
            }
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
    }

    // MARK: - Camera Tracking View

    var cameraTrackingView: some View {
        GeometryReader { geo in
            ZStack {
                // Camera preview
                CameraPreviewView(session: poseDetector.cameraManager.session)
                    .ignoresSafeArea()

                // Skeleton overlay
                SkeletonOverlayView(
                    pose: poseDetector.currentPose,
                    formQuality: tracker.formQuality,
                    size: geo.size
                )

                // Bottom HUD
                VStack {
                    Spacer()
                    trackingHUD
                }
            }
        }
    }

    // MARK: - Manual Tracking View (Simulator fallback)

    var manualTrackingView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Camera not available message
            VStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Camera Not Available")
                    .font(.headline).foregroundColor(.white)
                Text("Use the manual counter below to track your reps.\nCamera tracking requires a physical iPhone.")
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .background(Color.card.opacity(0.8))
            .cornerRadius(20)

            // Exercise info
            VStack(spacing: 8) {
                Image(systemName: exercise.icon)
                    .font(.system(size: 44))
                    .foregroundColor(.accent)
                Text(exercise.displayName)
                    .font(.title2.bold()).foregroundColor(.white)
            }

            // Large rep counter
            if exercise.isHoldExercise {
                // Plank timer
                Text(formatTime(tracker.holdSeconds))
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(.teal)
                    .animation(.easeInOut, value: tracker.holdSeconds)
            } else {
                Text("\(tracker.repsInCurrentSet)")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundColor(.teal)
                    .animation(.spring(response: 0.3), value: tracker.repsInCurrentSet)

                Text("of \(targetReps) reps · Set \(tracker.currentSet)/\(targetSets)")
                    .font(.subheadline).foregroundColor(.secondary)
            }

            // Manual controls
            if !exercise.isHoldExercise {
                HStack(spacing: 32) {
                    Button { tracker.manualUndoRep() } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 56))
                                .foregroundColor(.red.opacity(0.8))
                            Text("Undo").font(.caption).foregroundColor(.secondary)
                        }
                    }

                    Button { tracker.manualAddRep() } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 56))
                                .foregroundColor(.teal)
                            Text("Rep").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Form feedback
            Text(tracker.formFeedback)
                .font(.subheadline.bold())
                .foregroundColor(formFeedbackColor)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(formFeedbackColor.opacity(0.15))
                .cornerRadius(12)
                .animation(.easeInOut, value: tracker.formFeedback)

            // Timer
            Text(formatTime(elapsedSeconds))
                .font(.caption).foregroundColor(.secondary)

            Spacer()

            // Bottom buttons
            HStack(spacing: 16) {
                Button { finishSession() } label: {
                    Text("End Workout")
                        .font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(14)
                        .background(Color.red.opacity(0.8)).cornerRadius(14)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .padding(.top, 60)
    }

    // MARK: - Top Bar

    var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2).foregroundColor(.white.opacity(0.8))
                    .padding(4)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }

            Spacer()

            // Exercise name + timer
            VStack(spacing: 2) {
                Text(exercise.displayName)
                    .font(.subheadline.bold()).foregroundColor(.white)
                Text(formatTime(elapsedSeconds))
                    .font(.caption.monospacedDigit()).foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5))
            .cornerRadius(20)

            Spacer()

            // Finish button
            Button { finishSession() } label: {
                Text("Done")
                    .font(.subheadline.bold()).foregroundColor(.teal)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(20)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Tracking HUD (camera mode)

    var trackingHUD: some View {
        VStack(spacing: 12) {
            // Form feedback banner
            HStack(spacing: 8) {
                Circle()
                    .fill(formFeedbackColor)
                    .frame(width: 10, height: 10)
                Text(tracker.formFeedback)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.6))
            .cornerRadius(20)
            .animation(.easeInOut, value: tracker.formFeedback)

            // Rep counter
            HStack(spacing: 24) {
                if exercise.isHoldExercise {
                    VStack(spacing: 4) {
                        Text(formatTime(tracker.holdSeconds))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.teal)
                        Text("Hold Time")
                            .font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    VStack(spacing: 4) {
                        Text("\(tracker.repsInCurrentSet)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.teal)
                            .animation(.spring(response: 0.3), value: tracker.repsInCurrentSet)
                        Text("of \(targetReps) reps")
                            .font(.caption).foregroundColor(.secondary)
                    }

                    VStack(spacing: 4) {
                        Text("\(tracker.currentSet)/\(targetSets)")
                            .font(.title2.bold())
                            .foregroundColor(.accent)
                        Text("Sets")
                            .font(.caption).foregroundColor(.secondary)
                    }

                    VStack(spacing: 4) {
                        Text("\(tracker.totalRepsCompleted)")
                            .font(.title2.bold())
                            .foregroundColor(.amber)
                        Text("Total")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.8), Color.black.opacity(0.6)],
                    startPoint: .bottom, endPoint: .top
                )
            )
            .cornerRadius(20)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Instructions Overlay

    var instructionsOverlay: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: exercise.icon)
                    .font(.system(size: 56))
                    .foregroundColor(.accent)

                Text(exercise.displayName)
                    .font(.title.bold()).foregroundColor(.white)

                Text(exercise.instruction)
                    .font(.body).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(alignment: .leading, spacing: 8) {
                    if exercise.isHoldExercise {
                        instructionRow(icon: "timer", text: "Hold the position as long as you can")
                    } else {
                        instructionRow(icon: "arrow.up.arrow.down", text: "\(targetSets) sets × \(targetReps) reps")
                    }
                    instructionRow(icon: "camera.fill", text: cameraAvailable
                        ? "Camera will track your movement"
                        : "Manual mode — tap to count reps")
                    instructionRow(icon: "hand.raised.fill", text: "Stop if you feel pain or dizziness")
                }
                .padding(20)
                .background(Color.card)
                .cornerRadius(16)

                Button {
                    withAnimation { showInstructions = false }
                    tracker.start()
                    startTimer()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Start Tracking")
                    }
                    .font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(16)
                    .background(
                        LinearGradient(colors: [.accent, .teal],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(16)
                }
                .padding(.horizontal, 32)
            }
            .padding(24)
        }
    }

    func instructionRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.accent)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white)
        }
    }

    // MARK: - Completion Overlay

    func completionOverlay(_ result: TrackingSessionResult) -> some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 20) {
                // Celebration
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(colors: [.accent, .teal],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )

                Text("Workout Complete!")
                    .font(.title.bold()).foregroundColor(.white)

                Text(exercise.displayName)
                    .font(.headline).foregroundColor(.accent)

                // Stats grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    completionStat(icon: "repeat", label: "Reps",
                                   value: "\(result.repsCompleted)/\(result.targetReps)")
                    completionStat(icon: "square.stack.fill", label: "Sets",
                                   value: "\(result.setsCompleted)/\(result.targetSets)")
                    completionStat(icon: "timer", label: "Duration",
                                   value: formatTime(result.durationSeconds))
                    completionStat(icon: "flame.fill", label: "Calories",
                                   value: "\(Int(result.estimatedCalories))")
                }

                // Form quality
                HStack(spacing: 8) {
                    Text("Form Quality:")
                        .font(.subheadline).foregroundColor(.secondary)
                    Text(formQualityText(result.averageFormScore))
                        .font(.subheadline.bold())
                        .foregroundColor(formQualityColor(result.averageFormScore))

                    // Stars
                    HStack(spacing: 2) {
                        ForEach(0..<5) { i in
                            Image(systemName: Double(i) < result.averageFormScore * 5
                                  ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundColor(.amber)
                        }
                    }
                }
                .padding(12)
                .background(Color.card)
                .cornerRadius(12)

                Button {
                    onComplete(result)
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save & Return")
                    }
                    .font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(16)
                    .background(
                        LinearGradient(colors: [.accent, .teal],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(16)
                }

                Button {
                    dismiss()
                } label: {
                    Text("Discard")
                        .font(.subheadline).foregroundColor(.secondary)
                }
            }
            .padding(24)
        }
    }

    func completionStat(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3).foregroundColor(.teal)
            Text(value)
                .font(.title3.bold()).foregroundColor(.white)
            Text(label)
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Color.card)
        .cornerRadius(14)
    }

    // MARK: - Helpers

    var formFeedbackColor: Color {
        switch tracker.formQuality {
        case .good: return .teal
        case .fair: return .amber
        case .poor: return .red
        }
    }

    func formQualityText(_ score: Double) -> String {
        if score > 0.8 { return "Excellent" }
        if score > 0.6 { return "Good" }
        if score > 0.4 { return "Fair" }
        return "Needs Work"
    }

    func formQualityColor(_ score: Double) -> Color {
        if score > 0.8 { return .teal }
        if score > 0.6 { return .accent }
        if score > 0.4 { return .amber }
        return .red
    }

    func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedSeconds += 1
        }
    }

    func finishSession() {
        timer?.invalidate()
        let sessionResult = tracker.stop()
        poseDetector.stop()
        result = sessionResult
        withAnimation { showResult = true }
    }
}
