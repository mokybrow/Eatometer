import SwiftUI

struct WaterTrackingView: View {
    @EnvironmentObject private var sessionManager: WatchSessionManager
    @State private var feedbackTrigger = 0

    private var intake: Int { sessionManager.todaySnapshot.waterIntakeMilliliters }
    private var goal: Int { max(sessionManager.todaySnapshot.waterGoalMilliliters, 1) }
    private var waterStep: Int { 200 }
    private var progress: Double { min(Double(intake) / Double(goal), 1.0) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                waterRing
                    .frame(width: 120, height: 120)

                controls
            }
            .padding(.horizontal)
        }
        .navigationTitle("💧")
        .sensoryFeedback(.impact(weight: .medium), trigger: feedbackTrigger)
    }

    // MARK: - Water Ring

    private var waterRing: some View {
        ZStack {
            Circle()
                .stroke(Color.cyan.opacity(0.2), lineWidth: 10)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.cyan, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)

            VStack(spacing: 2) {
                Image(systemName: "drop.fill")
                    .font(.title3)
                    .foregroundStyle(.cyan)
                Text(formattedIntake)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text("/ \(formattedGoal)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Button {
                sessionManager.adjustWater(by: waterStep)
                feedbackTrigger += 1
            } label: {
                Text(String(format: NSLocalizedString("water.add_ml", comment: "Add water action"), waterStep))
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan.opacity(0.3))

            Button {
                sessionManager.adjustWater(by: -waterStep)
                feedbackTrigger += 1
            } label: {
                Text(String(format: NSLocalizedString("water.remove_ml", comment: "Remove water action"), waterStep))
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.gray.opacity(0.25))
            .disabled(intake == 0)
        }
    }

    // MARK: - Formatting

    private var formattedIntake: String {
        if intake >= 1000 {
            return String(format: NSLocalizedString("water.goal.preset_ml", comment: "Water liters format"), Double(intake) / 1000.0)
        }
        return "\(intake) \(NSLocalizedString("water.ml", comment: "Water milliliters suffix"))"
    }

    private var formattedGoal: String {
        if goal >= 1000 {
            return String(format: NSLocalizedString("water.goal.preset_ml", comment: "Water liters format"), Double(goal) / 1000.0)
        }
        return "\(goal) \(NSLocalizedString("water.ml", comment: "Water milliliters suffix"))"
    }
}
