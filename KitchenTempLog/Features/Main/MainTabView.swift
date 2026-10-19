import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "checklist") }
            CoolingView()
                .tabItem { Label("Cooling", systemImage: "timer") }
            LogView()
                .tabItem { Label("Log", systemImage: "doc.text.fill") }
            SetupView()
                .tabItem { Label("Setup", systemImage: "slider.horizontal.3") }
        }
    }
}
