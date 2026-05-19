// ContentView.swift — Root TabView (owns selectedTab, passes to Dashboard)
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var workoutVM: WorkoutViewModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {

            DashboardView(selectedTab: $selectedTab)
                .tabItem { Label("Dashboard", systemImage: "house.fill") }
                .tag(0)

            FitnessPlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(1)

            GetPlanView()
                .tabItem { Label("Get Plan", systemImage: "sparkles") }
                .tag(2)

            HealthStatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                .tag(3)

            ReportView()
                .tabItem { Label("AI Report", systemImage: "doc.text.fill") }
                .tag(4)
        }
        .accentColor(.accent)
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(red: 0.09, green: 0.09, blue: 0.14, alpha: 1)
            UITabBar.appearance().standardAppearance   = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(WorkoutViewModel())
            .environmentObject(DashboardViewModel(provider: MockHealthDataProvider()))
    }
}
