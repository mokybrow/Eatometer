import SwiftUI

struct NutritionSummaryView: View {
    @EnvironmentObject private var sessionManager: WatchSessionManager

    private var snapshot: WatchTodaySnapshot { sessionManager.todaySnapshot }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                caloriesRing
                    .frame(width: 120, height: 120)

                VStack(spacing: 10) {
                    macroBar(
                        label: NSLocalizedString("diary.protein", comment: "Protein label"),
                        value: snapshot.protein,
                        goal: snapshot.proteinGoal,
                        color: .orange
                    )
                    macroBar(
                        label: NSLocalizedString("diary.fat", comment: "Fat label"),
                        value: snapshot.fat,
                        goal: snapshot.fatGoal,
                        color: .purple
                    )
                    macroBar(
                        label: NSLocalizedString("diary.carbs", comment: "Carbs label"),
                        value: snapshot.carbs,
                        goal: snapshot.carbsGoal,
                        color: .green
                    )
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("🍽️")
    }

    // MARK: - Calories Ring

    private var caloriesRing: some View {
        let progress = min(Double(snapshot.calories) / Double(max(snapshot.caloriesGoal, 1)), 1.0)
        return ZStack {
            Circle()
                .stroke(Color.orange.opacity(0.2), lineWidth: 10)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)

            VStack(spacing: 2) {
                Text("\(snapshot.calories)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text("/ \(snapshot.caloriesGoal)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(NSLocalizedString("diary.kcal", comment: "Calories suffix"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Macro Bars

    @ViewBuilder
    private func macroBar(label: String, value: Int, goal: Int, color: Color) -> some View {
        let progress = goal > 0 ? min(Double(value) / Double(goal), 1.0) : 0

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text(String(format: NSLocalizedString("today.grams_progress", comment: "Macro progress value"), value, goal))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.2))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * progress, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 6)
        }
    }
}
