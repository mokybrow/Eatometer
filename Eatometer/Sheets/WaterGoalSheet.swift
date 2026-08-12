import SwiftUI

struct AddWaterSheet: View {
    let initialMilliliters: Int
    let goalMilliliters: Int
    let onSet: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Signed delta applied to the current intake. Negative values remove water,
    /// so a mis-tap can be corrected without resetting the whole day.
    @State private var deltaMilliliters: Int

    private let step: Int
    /// Static so the opening delta can be clamped against it in `init`, before
    /// the instance exists.
    private static let maximumMilliliters = 10_000

    init(currentMilliliters: Int, goalMilliliters: Int, step: Int = 200, onSet: @escaping (Int) -> Void) {
        let resolvedStep = max(50, step)
        self.initialMilliliters = currentMilliliters
        self.goalMilliliters = goalMilliliters
        self.step = resolvedStep
        self.onSet = onSet
        // Opening on a figure the row cannot reach would show a number the
        // stepper refuses to move, so the day's remaining headroom wins.
        self._deltaMilliliters = State(
            initialValue: min(resolvedStep, max(0, Self.maximumMilliliters - currentMilliliters))
        )
    }

    /// Water can only be taken back down to zero, and only added up to the cap.
    private var minimumDelta: Int { -initialMilliliters }
    private var maximumDelta: Int { Self.maximumMilliliters - initialMilliliters }

    private var resultingMilliliters: Int {
        min(max(initialMilliliters + deltaMilliliters, 0), Self.maximumMilliliters)
    }

    private var isRemoving: Bool { deltaMilliliters < 0 }

    private var millilitresUnit: String {
        NSLocalizedString("unit.milliliters.short", comment: "Millilitres unit short title")
    }

    /// "+200 ml" / "−200 ml" – the sign makes the direction obvious at a glance.
    private var deltaText: String {
        let sign = isRemoving ? "−" : "+"
        return "\(sign)\(abs(deltaMilliliters)) \(millilitresUnit)"
    }

    private var deltaRowTitle: LocalizedStringKey {
        isRemoving ? "water.was_removed" : "water.was_added"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EOCard {
                    EOListRow(
                        title: Text("water.current_value"),
                        accessory: .value(Text(verbatim: "\(initialMilliliters) \(millilitresUnit)"))
                    )
                    EORowSeparator()

                    EOListRow(title: Text(deltaRowTitle)) {
                        Text(verbatim: deltaText)
                            .font(EOTheme.Typography.rowValue)
                            .foregroundStyle(
                                deltaMilliliters == 0
                                    ? Color.secondary
                                    : (isRemoving ? EOTheme.Palette.destructive : EOTheme.Palette.water)
                            )
                            .monospacedDigit()
                    }
                    EORowSeparator()

                    // Stepped only, deliberately. Water is logged in glasses and
                    // bottles, not in arbitrary figures, and the amount is a
                    // correction to the day rather than a measurement — a typed
                    // field invites precision the reading does not have.
                    EOStepperRow(
                        title: Text("water.add"),
                        subtitle: Text(String(format: NSLocalizedString("water.step_format", comment: "Water step"), step)),
                        canDecrement: deltaMilliliters > minimumDelta,
                        canIncrement: deltaMilliliters < maximumDelta,
                        onDecrement: { deltaMilliliters = max(minimumDelta, deltaMilliliters - step) },
                        onIncrement: { deltaMilliliters = min(maximumDelta, deltaMilliliters + step) }
                    )
                }
                .eoCardInsets()
                .padding(.top, 12)

                Text("water.adjust.hint")
                    .font(EOTheme.Typography.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, EOTheme.Metrics.screenInset + EOTheme.Metrics.cardInset)
                    .padding(.top, 8)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .eoPageBackground()
            .eoSheetChrome(
                "water.add_title",
                trailing: .confirm(isEnabled: deltaMilliliters != 0) {
                    onSet(resultingMilliliters)
                    dismiss()
                },
                onClose: { dismiss() }
            )
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
