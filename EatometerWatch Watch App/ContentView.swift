//
//  ContentView.swift
//  EatometerWatch Watch App
//
//  Created by Михаил Панин on 20.04.2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var sessionManager: WatchSessionManager

    private var shouldShowWaterTab: Bool {
        sessionManager.todaySnapshot.isWaterTrackingEnabled
    }

    var body: some View {
        TabView {
            Tab("watch.tab.nutrition", systemImage: "fork.knife") {
                NutritionSummaryView()
            }

            if shouldShowWaterTab {
                Tab("water.title", systemImage: "drop.fill") {
                    WaterTrackingView()
                }
            }

            Tab("today.meals.title", systemImage: "list.bullet") {
                MealsOverviewView()
            }
        }
    }
}
