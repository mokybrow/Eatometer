import SwiftUI

struct WaterGoalSettingsView: View {
    @EnvironmentObject private var diaryService: FoodDiaryService
    @State private var goalValue = 2_000

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: EOTheme.Metrics.headerSpacing) {
                EOCard {
                    EOStepperRow(
                        title: Text(
                            verbatim: String(
                                format: NSLocalizedString("water.settings.daily_plan", comment: "Daily water plan"),
                                goalValue
                            )
                        ),
                        canDecrement: goalValue > 500,
                        canIncrement: goalValue < 10_000,
                        onDecrement: { goalValue = max(500, goalValue - 50) },
                        onIncrement: { goalValue = min(10_000, goalValue + 50) }
                    )
                    EORowSeparator()

                    EOInlineActionRow(
                        "common.save",
                        isEnabled: goalValue != diaryService.dailyWaterGoalMilliliters
                    ) {
                        diaryService.setDailyWaterGoal(goalValue)
                    }
                }

                Text("water.settings.help")
                    .font(EOTheme.Typography.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, EOTheme.Metrics.cardInset)
                    .padding(.top, 4)
            }
            .eoCardInsets()
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .eoPageBackground()
        .navigationTitle("profile.nutrition.water_tracker")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            goalValue = diaryService.dailyWaterGoalMilliliters
        }
    }
}
