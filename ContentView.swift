//
//  ContentView.swift
//  AI Voice Copilot
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var settings = UserSettings.shared
    @ObservedObject var appCoordinator = AppCoordinator.shared
    
    var body: some View {
        Group {
            if !settings.hasSeenOnboarding {
                OnboardingScreen()
            } else {
                MainAppView()
            }
        }
    }
}

struct MainAppView: View {
    @ObservedObject var appCoordinator = AppCoordinator.shared
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                CallScreen()
            }
            .tabItem {
                Label("Call", systemImage: "phone.fill")
            }
            .tag(0)
            
            NavigationStack(path: $appCoordinator.navigationPath) {
                SessionsListScreen()
            }
            .tabItem {
                Label("Sessions", systemImage: "clock.fill")
            }
            .tag(1)
            
            NavigationStack {
                SettingsScreen()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(2)
        }
    }
}

#Preview {
    ContentView()
}
