//  fitnessApp.swift — App entry point
import SwiftUI

@main
struct fitnessApp: App {
    @StateObject private var dashVM    = DashboardViewModel(provider: LiveHealthDataProvider())
    @StateObject private var workoutVM = WorkoutViewModel()
    @StateObject private var healthVM  = HealthKitViewModel()   // HealthStatsView
    @StateObject private var reportVM  = ReportViewModel()      // shared across all tabs

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dashVM)
                .environmentObject(workoutVM)
                .environmentObject(healthVM)
                .environmentObject(reportVM)
                .preferredColorScheme(.dark)
        }
    }
}
