// HealthStatsView.swift
import SwiftUI

struct HealthStatsView: View {
    @EnvironmentObject var healthVM: HealthKitViewModel
    @EnvironmentObject var dashVM: DashboardViewModel

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Text("Health Stats")
                        .font(.largeTitle.bold()).foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    // Big stat grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        BigStat(icon: "figure.walk",  color: .accent,
                                value: String(Int(dashVM.snapshot.steps)),    label: "Steps Today",   unit: "/ \(dashVM.snapshot.stepGoal) goal")
                        BigStat(icon: "flame.fill",   color: .amber,
                                value: String(Int(dashVM.snapshot.calories)), label: "Active Cal",    unit: "kcal burned")
                        BigStat(icon: "heart.fill",   color: .red,
                                value: String(Int(dashVM.snapshot.heartRate)),label: "Heart Rate",    unit: "bpm")
                        BigStat(icon: "moon.stars.fill", color: .accent,
                                value: String(format: "%.1f", dashVM.snapshot.sleepHours), label: "Sleep", unit: "hours")
                    }.padding(.horizontal)

                    // Step bar chart (simulated weekly)
                    WeeklyBarChart()

                    // Progress rings section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Daily Goals").font(.headline).foregroundColor(.white)
                        GoalRow(label: "Steps", current: dashVM.snapshot.steps, goal: Double(dashVM.snapshot.stepGoal), color: .accent, unit: "steps")
                        GoalRow(label: "Calories", current: dashVM.snapshot.calories, goal: dashVM.snapshot.calGoal, color: .amber, unit: "kcal")
                        GoalRow(label: "Active Minutes", current: Double(dashVM.snapshot.activeMinutes), goal: 30, color: .teal, unit: "min")
                    }
                    .padding(16).background(Color.card).cornerRadius(16).padding(.horizontal)

                    Spacer(minLength: 30)
                }
                .padding(.top)
            }
        }
        .onAppear {
            healthVM.refresh()
            dashVM.authorize()
        }
    }
}

struct BigStat: View {
    let icon: String; let color: Color
    let value: String; let label: String; let unit: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundColor(color)
            Text(value).font(.title.bold()).foregroundColor(.white)
            Text(label).font(.caption).foregroundColor(.white)
            Text(unit).font(.caption2).foregroundColor(.secondary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card).cornerRadius(16)
    }
}

struct WeeklyBarChart: View {
    // Simulated weekly steps (replace with real HealthKit query if desired)
    let data: [Double] = [6200, 8100, 5300, 9800, 7400, 10200, 4500]
    let days = ["M","T","W","T","F","S","S"]
    var maxVal: Double { data.max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Steps").font(.headline).foregroundColor(.white)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(i == 5 ? Color.teal : Color.accent.opacity(0.8))
                            .frame(height: CGFloat(data[i] / maxVal) * 100)
                        Text(days[i]).font(.caption2).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 120, alignment: .bottom)
        }
        .padding(16).background(Color.card).cornerRadius(16).padding(.horizontal)
    }
}

struct GoalRow: View {
    let label: String; let current: Double
    let goal: Double;  let color: Color; let unit: String
    var progress: Double { Swift.min(current / goal, 1.0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.subheadline).foregroundColor(.white)
                Spacer()
                Text("\(Int(current)) / \(Int(goal)) \(unit)")
                    .font(.caption).foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.2))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4).fill(color)
                        .frame(width: geo.size.width * progress, height: 8)
                }
            }.frame(height: 8)
        }
    }
}
