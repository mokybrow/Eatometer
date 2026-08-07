//
//  EatometerWidgetBundle.swift
//  EatometerWidget
//
//  Created by Михаил Панин on 16/04/2026.
//

import WidgetKit
import SwiftUI

@main
struct EatometerWidgetBundle: WidgetBundle {
    var body: some Widget {
        EatometerWidget()
        EatometerQuickMealWidget()
        EatometerHabitWidget()
        EatometerNutritionWidget()
        EatometerStatsWidget()
    }
}
