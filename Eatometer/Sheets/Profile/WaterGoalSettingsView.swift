import SwiftUI

/// The two numbers the water tracker runs on: where the day should finish, and
/// how much one tap adds.
///
/// The step used to be a menu of presets in the profile list, two screens away
/// from the goal it works towards — the reader had to know both to set either
/// sensibly. Here they are one card and one Save, and the step moves in the
/// same 50 ml the goal does so the two controls feel like one setting.
struct WaterGoalSettingsView: View {
    @EnvironmentObject private var diaryService: FoodDiaryService
    @ObservedObject private var appSettings = AppSettings.shared

    @State private var goalValue = 2_000
    @State private var stepValue = AppSettings.defaultWaterWidgetStepMilliliters

    private static let stepIncrement = 50
    private static let stepRange = 50...2_000

    private var hasChanges: Bool {
        goalValue != diaryService.dailyWaterGoalMilliliters
            || stepValue != appSettings.waterWidgetStepMilliliters
    }

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

                    EOStepperRow(
                        title: Text(
                            verbatim: String(
                                format: NSLocalizedString("water.settings.step", comment: "Water step"),
                                stepValue
                            )
                        ),
                        canDecrement: stepValue > Self.stepRange.lowerBound,
                        canIncrement: stepValue < Self.stepRange.upperBound,
                        onDecrement: {
                            stepValue = max(Self.stepRange.lowerBound, stepValue - Self.stepIncrement)
                        },
                        onIncrement: {
                            stepValue = min(Self.stepRange.upperBound, stepValue + Self.stepIncrement)
                        }
                    )
                    EORowSeparator()

                    EOInlineActionRow("common.save", isEnabled: hasChanges) {
                        diaryService.setWaterPlan(goalMilliliters: goalValue, stepMilliliters: stepValue)
                    }
                }

                Text("water.settings.help")
                    .font(EOTheme.Typography.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, EOTheme.Metrics.cardInset)
                    .padding(.top, 4)

                Text("water.settings.step.help")
                    .font(EOTheme.Typography.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, EOTheme.Metrics.cardInset)
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
            stepValue = appSettings.waterWidgetStepMilliliters
        }
    }
}
