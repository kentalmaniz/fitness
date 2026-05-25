// FitnessPlanView.swift
import SwiftUI

struct FitnessPlanView: View {
    @EnvironmentObject var workoutVM: WorkoutViewModel
    @State private var selectedDay: WorkoutDay?

    var plan: FitnessPlan { workoutVM.activePlan }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                planPicker
                planHeader
                Divider().background(Color.card).padding(.top, 8)
                dayList
            }
        }
        .sheet(item: $selectedDay) { day in
            WorkoutDetailSheet(day: day).environmentObject(workoutVM)
        }
    }

    var planPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(workoutVM.plans.indices, id: \.self) { i in
                    let p = workoutVM.plans[i]
                    Button { workoutVM.activePlanIndex = i } label: {
                        HStack(spacing: 6) {
                            Text(p.emoji)
                            Text(p.name).font(.subheadline.bold())
                                .foregroundColor(workoutVM.activePlanIndex == i ? .white : .secondary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(workoutVM.activePlanIndex == i ? Color.accent : Color.card)
                        .cornerRadius(20)
                    }
                }
            }.padding(.horizontal).padding(.top, 16)
        }
    }

    var planHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.name).font(.title2.bold()).foregroundColor(.white)
                Text(plan.desc).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(plan.weeks)w").font(.title3.bold()).foregroundColor(.accent)
                Text(plan.difficulty.rawValue).font(.caption)
                    .foregroundColor(plan.difficulty.color)
            }
        }.padding().padding(.top, 4)
    }

    var dayList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(plan.days) { day in
                    DayCard(day: day) { selectedDay = day }
                }
            }
            .padding(.horizontal).padding(.top, 10).padding(.bottom, 30)
        }
    }
}

// MARK: - Day Card
struct DayCard: View {
    let day: WorkoutDay; let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(day.isRest ? Color.secondary.opacity(0.15) : Color.accent.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: day.isRest ? "moon.zzz.fill" : "dumbbell.fill")
                        .foregroundColor(day.isRest ? .secondary : .accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(day.name).font(.subheadline.bold()).foregroundColor(.white)
                    Text(day.isRest ? "Rest Day" : "\(day.focus) · \(day.duration)m")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if day.isCompleted {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.teal).font(.title3)
                } else if !day.isRest {
                    Text("\(day.exercises.count) ex").font(.caption).foregroundColor(.secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(14).background(Color.card).cornerRadius(14)
        }
    }
}

// MARK: - Workout Detail Sheet
struct WorkoutDetailSheet: View {
    let day: WorkoutDay
    @EnvironmentObject var workoutVM: WorkoutViewModel
    @Environment(\.dismiss) var dismiss
    @State private var trackingExercise: Exercise?
    var liveDay: WorkoutDay? { workoutVM.activePlan.days.first { $0.id == day.id } }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.name).font(.title2.bold()).foregroundColor(.white)
                        Text(day.focus).font(.subheadline).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundColor(.secondary)
                    }
                }.padding()

                if day.isRest {
                    Spacer()
                    Text("🛋️\nRest & Recover").font(.largeTitle)
                        .multilineTextAlignment(.center).foregroundColor(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(liveDay?.exercises ?? day.exercises) { ex in
                                HStack(spacing: 14) {
                                    Image(systemName: ex.icon).foregroundColor(.accent).frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ex.name).foregroundColor(.white).font(.subheadline.bold())
                                        Text("\(ex.sets) sets × \(ex.reps) reps")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()

                                    // Camera tracking button
                                    if ex.isTrackable && !ex.isCompleted {
                                        Button {
                                            trackingExercise = ex
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

                                    Button { workoutVM.toggleExercise(dayId: day.id, exId: ex.id) } label: {
                                        Image(systemName: ex.isCompleted ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(ex.isCompleted ? .teal : .secondary)
                                            .font(.title3)
                                    }
                                }
                                .padding(14).background(Color.card).cornerRadius(12)
                            }
                        }.padding(.horizontal)
                    }
                    Button {
                        workoutVM.completeDay(dayId: day.id); dismiss()
                    } label: {
                        Text("Mark Day Complete ✓")
                            .font(.headline).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding()
                            .background(LinearGradient(colors: [.accent, .teal],
                                                       startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(14)
                    }.padding()
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $trackingExercise) { ex in
            if let trackable = ex.trackableExercise {
                ExerciseTrackingView(
                    exercise: trackable,
                    targetReps: ex.reps,
                    targetSets: ex.sets
                ) { _ in
                    // Mark exercise as completed after tracking
                    workoutVM.toggleExercise(dayId: day.id, exId: ex.id)
                }
            }
        }
    }
}

