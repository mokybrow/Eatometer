import SwiftUI
import UIKit

// MARK: - Design tokens

/// Central design tokens derived from the Eatometer mock-ups.
/// Everything visual (radii, paddings, typography, palette) lives here so the
/// whole app can be re-skinned from one place.
enum EOTheme {

    // MARK: Metrics

    enum Metrics {
        /// Horizontal inset from the screen edge to a card's edge.
        static let screenInset: CGFloat = 20
        /// Horizontal inset from the screen edge to text that sits *outside* a
        /// card (section headers, footnotes) – aligns with in-card text.
        static let textInset: CGFloat = 36
        /// Inner horizontal padding of a card.
        static let cardInset: CGFloat = 16
        /// Card corner radius.
        static let cardRadius: CGFloat = 24
        /// Corner radius of small tappable pills (steppers, segmented picker).
        static let pillRadius: CGFloat = 18
        /// Vertical padding of a standard list row.
        static let rowVerticalPadding: CGFloat = 13
        /// Minimum height of a standard list row.
        static let rowMinHeight: CGFloat = 44
        /// Spacing between stacked cards / sections.
        static let sectionSpacing: CGFloat = 20
        /// Spacing between a section header and its card.
        static let headerSpacing: CGFloat = 8
    }

    // MARK: Palette

    enum Palette {
        /// Page background (light lavender-grey in light mode).
        static var pageBackground: Color {
            Color(UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor.systemBackground
                    : UIColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1) // #F2F2F7
            })
        }

        /// Card / grouped-row background.
        static var card: Color {
            Color(UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor.secondarySystemBackground
                    : UIColor.white
            })
        }

        /// Hairline separator between rows inside a card.
        static var rowSeparator: Color {
            Color(UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor.separator.withAlphaComponent(0.55)
                    : UIColor(white: 0.86, alpha: 1)
            })
        }

        /// Neutral fill used by steppers and the segmented picker track.
        static var controlFill: Color {
            Color(UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor.tertiarySystemFill
                    : UIColor(red: 0.902, green: 0.902, blue: 0.914, alpha: 1) // #E6E6E9
            })
        }

        /// Text colour for a label drawn on top of a bottom-up "liquid level"
        /// fill. Once the level rises past the label, tinted text would be
        /// tint-on-tint and vanish, so it flips to white.
        static func levelLabel(_ tint: Color, isSubmerged: Bool) -> Color {
            isSubmerged ? .white : tint
        }

        static let accent = Color.appAccent
        static let water = Color(red: 0.0, green: 0.533, blue: 1.0)         // #0088FF
        static let calories = Color(red: 1.0, green: 0.196, blue: 0.529)    // #FF3287
        static let protein = Color(red: 0.0, green: 0.792, blue: 0.871)     // #00CADE
        static let carbs = Color(red: 0.302, green: 0.886, blue: 0.0)       // #4DE200
        // Amber, not the magenta it used to be. Magenta sat a shade away from
        // the calories pink, so on a row of four rings the two read as one
        // colour repeated — which is the one thing the row exists to avoid.
        static let fat = Color(red: 0.906, green: 0.576, blue: 0.047)       // #E79310
        static let destructive = Color(red: 1.0, green: 0.176, blue: 0.333) // #FF2D55

        /// The unfilled part of a nutrition ring.
        ///
        /// One neutral grey for all four rather than each ring's own colour at
        /// low opacity. Tinted tracks made an empty ring look part-filled — a
        /// pale pink circle reads as progress against a pink target — and put
        /// four more colours on a card that already has four.
        static var ringTrack: Color {
            Color(UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.231, green: 0.231, blue: 0.243, alpha: 1)  // #3B3B3E
                    : UIColor(red: 0.898, green: 0.898, blue: 0.910, alpha: 1)  // #E5E5E8
            })
        }
    }

    // MARK: Typography

    enum Typography {
        /// Large screen title ("Diary", "Library", "Profile").
        static let screenTitle = Font.largeTitle.bold()
        /// Big section header standing alone on the page ("Meals" on Diary).
        static let sectionHeader = Font.system(.title3, design: .default).weight(.bold)
        /// Compact group header above a settings card ("General", "Security").
        static let groupHeader = Font.headline.weight(.bold)
        /// Primary text of a list row.
        static let rowTitle = Font.body
        /// Secondary text under a row title.
        static let rowSubtitle = Font.subheadline
        /// Trailing value of a row ("Edit", "grams", "230 Kcal").
        static let rowValue = Font.body
        /// Footnote under a card.
        static let footnote = Font.subheadline
        /// Big grey placeholder headline of an empty state.
        static let emptyTitle = Font.system(.title2, design: .default).weight(.bold)
        static let emptySubtitle = Font.body
    }
}

// MARK: - Liquid level cards

/// Frames of labels drawn on top of a "liquid level" fill, keyed by an id.
///
/// The card compares each frame against the current water line instead of
/// guessing a progress threshold, so the text flips to white exactly when the
/// fill actually reaches it — whatever the card's height or font size.
struct EOLevelLabelFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publishes this label's frame within `space` for submersion checks.
    func eoLevelLabelFrame(_ id: String, in space: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: EOLevelLabelFramePreferenceKey.self,
                    value: [id: proxy.frame(in: .named(space))]
                )
            }
        )
    }
}

/// Shared submersion test: the label counts as submerged once the water line
/// passes its vertical midpoint.
enum EOLevelGeometry {
    static func isSubmerged(
        labelFrames: [String: CGRect],
        id: String,
        cardHeight: CGFloat,
        progress: CGFloat
    ) -> Bool {
        guard let frame = labelFrames[id], cardHeight > 0 else { return false }
        let waterLineY = cardHeight * (1 - progress)
        return frame.midY >= waterLineY
    }
}

// MARK: - Card container

/// White rounded container that groups rows, matching the mock-ups.
struct EOCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EOTheme.Palette.card)
        // Clipping (rather than only drawing a rounded background) keeps rows
        // that paint their own background – e.g. context-menu rows – inside the
        // card's rounded corners.
        .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }
}

/// Hairline divider used between rows inside `EOCard`.
struct EORowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(EOTheme.Palette.rowSeparator)
            .frame(height: 0.5)
            .padding(.horizontal, EOTheme.Metrics.cardInset)
    }
}

// MARK: - Section header & footnote

struct EOSectionHeader: View {
    private let title: Text

    init(_ key: LocalizedStringKey) { self.title = Text(key) }
    init(verbatim value: String) { self.title = Text(verbatim: value) }

    var body: some View {
        title
            .font(EOTheme.Typography.sectionHeader)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, EOTheme.Metrics.textInset)
    }
}

struct EOFootnote: View {
    private let text: Text

    init(_ key: LocalizedStringKey) { self.text = Text(key) }
    init(verbatim value: String) { self.text = Text(verbatim: value) }

    var body: some View {
        text
            .font(EOTheme.Typography.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, EOTheme.Metrics.textInset)
    }
}

// MARK: - Rows

/// Trailing accessory of a standard row.
enum EORowAccessory {
    case none
    case chevron
    case value(Text)
    /// Grey value + chevron, e.g. "Edit ›".
    case valueChevron(Text)
    case symbol(name: String, color: Color)
}

/// Generic list row matching the mock-ups: title (+ optional subtitle) on the
/// left, an accessory on the right, 16pt inner padding, 44pt minimum height.
struct EOListRow<Trailing: View>: View {
    private let title: Text
    private let subtitle: Text?
    private let titleColor: Color
    private let trailing: Trailing

    init(
        title: Text,
        subtitle: Text? = nil,
        titleColor: Color = .primary,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.titleColor = titleColor
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(EOTheme.Typography.rowTitle)
                    .foregroundStyle(titleColor)
                if let subtitle {
                    subtitle
                        .font(EOTheme.Typography.rowSubtitle)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.horizontal, EOTheme.Metrics.cardInset)
        .padding(.vertical, EOTheme.Metrics.rowVerticalPadding)
        .frame(minHeight: EOTheme.Metrics.rowMinHeight)
        .contentShape(Rectangle())
    }
}

extension EOListRow where Trailing == EORowAccessoryView {
    init(
        title: Text,
        subtitle: Text? = nil,
        titleColor: Color = .primary,
        accessory: EORowAccessory = .none
    ) {
        self.init(title: title, subtitle: subtitle, titleColor: titleColor) {
            EORowAccessoryView(accessory: accessory)
        }
    }

    init(
        _ titleKey: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        titleColor: Color = .primary,
        accessory: EORowAccessory = .none
    ) {
        self.init(
            title: Text(titleKey),
            subtitle: subtitle.map { Text($0) },
            titleColor: titleColor,
            accessory: accessory
        )
    }
}

struct EORowAccessoryView: View {
    let accessory: EORowAccessory

    var body: some View {
        switch accessory {
        case .none:
            EmptyView()
        case .chevron:
            EOChevron()
        case .value(let text):
            text
                .font(EOTheme.Typography.rowValue)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .valueChevron(let text):
            HStack(spacing: 6) {
                text
                    .font(EOTheme.Typography.rowValue)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                EOChevron()
            }
        case .symbol(let name, let color):
            Image(systemName: name)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(color)
        }
    }
}

struct EOChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.secondary.opacity(0.65))
    }
}

/// Row with a toggle on the trailing side (Profile / Onboarding screens).
struct EOToggleRow: View {
    private let title: Text
    private let subtitle: Text?
    @Binding private var isOn: Bool

    init(_ titleKey: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, isOn: Binding<Bool>) {
        self.title = Text(titleKey)
        self.subtitle = subtitle.map { Text($0) }
        self._isOn = isOn
    }

    init(title: Text, subtitle: Text? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        EOListRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.green)
        }
    }
}

/// Editable row: a plain text field with the grey clear button from the mock-ups.
struct EOTextFieldRow: View {
    private let placeholder: LocalizedStringKey
    @Binding private var text: String
    private let axis: Axis
    private let showsClearButton: Bool

    init(
        _ placeholder: LocalizedStringKey,
        text: Binding<String>,
        axis: Axis = .horizontal,
        showsClearButton: Bool = true
    ) {
        self.placeholder = placeholder
        self._text = text
        self.axis = axis
        self.showsClearButton = showsClearButton
    }

    var body: some View {
        HStack(spacing: 12) {
            TextField(placeholder, text: $text, axis: axis)
                .font(EOTheme.Typography.rowTitle)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsClearButton, !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, EOTheme.Metrics.cardInset)
        .padding(.vertical, EOTheme.Metrics.rowVerticalPadding)
        .frame(minHeight: EOTheme.Metrics.rowMinHeight)
    }
}

/// Row whose trailing accessory is a `−  |  +` stepper (Age, Weight, macros…).
struct EOStepperRow: View {
    private let title: Text
    private let subtitle: Text?
    private let canDecrement: Bool
    private let canIncrement: Bool
    private let onDecrement: () -> Void
    private let onIncrement: () -> Void

    init(
        title: Text,
        subtitle: Text? = nil,
        canDecrement: Bool = true,
        canIncrement: Bool = true,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.canDecrement = canDecrement
        self.canIncrement = canIncrement
        self.onDecrement = onDecrement
        self.onIncrement = onIncrement
    }

    var body: some View {
        EOListRow(title: title, subtitle: subtitle) {
            EOStepperControl(
                canDecrement: canDecrement,
                canIncrement: canIncrement,
                onDecrement: onDecrement,
                onIncrement: onIncrement
            )
        }
    }
}

/// A stepper row whose value can also be typed.
///
/// `−  |  +` is right for a nudge and hopeless for a figure read off a packet:
/// reaching 1 850 kcal in steps of ten is 185 taps. The number sits in a field
/// on the same row, so the buttons keep the small corrections and the keypad
/// takes everything else.
struct EOStepperFieldRow: View {
    private let title: Text
    private let subtitle: Text?
    private let range: ClosedRange<Int>
    private let step: Int
    @Binding private var value: Int

    /// What the field holds, which is not the value. On the way to "1850" the
    /// field passes through "" and "18"; writing those back would clamp and
    /// rewrite the number under the cursor as it is being typed.
    @State private var draft = ""
    @FocusState private var isEditing: Bool

    /// A zero is shown as a prompt rather than as content.
    ///
    /// Grey "0" says the field is empty and waiting; a black "0" says someone
    /// decided on none — and worse, it has to be selected and deleted before a
    /// real figure can be typed over it.
    private var placeholder: Text {
        Text(verbatim: "0").foregroundStyle(.secondary)
    }

    /// An idle row holding nothing shows the prompt rather than a typed "0".
    ///
    /// Keyed on the value, not on the text. A row whose floor is above zero —
    /// calories, say — is never empty and so never shows the prompt, which is
    /// right: "0" would be a figure it cannot hold.
    private var displayedDraft: String {
        !isEditing && value == 0 ? "" : draft
    }

    init(
        title: Text,
        subtitle: Text? = nil,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) {
        self.title = title
        self.subtitle = subtitle
        self._value = value
        self.range = range
        self.step = max(1, step)
    }

    /// "Protein, g" — the unit named once, in the label.
    ///
    /// It used to sit after the number, which made every field a different
    /// width: a column of them read "20 g", "1 850", "45 %", with the digits
    /// stepping left and right down the card. Moving the unit into the label
    /// leaves the numbers to line up under one another and still says what they
    /// are.
    static func title(_ name: String, unit: String) -> String {
        unit.isEmpty ? name : "\(name), \(unit)"
    }

    var body: some View {
        EOListRow(title: title, subtitle: subtitle) {
            HStack(spacing: 10) {
                TextField("", text: draftBinding, prompt: placeholder)
                    // A plain number pad has no minus, which would leave a
                    // negative value unreachable by typing — so the row asks for
                    // one only when its range actually goes below zero.
                    .keyboardType(range.lowerBound < 0 ? .numbersAndPunctuation : .numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(EOTheme.Typography.rowValue.monospacedDigit())
                    .focused($isEditing)
                    .frame(maxWidth: 96, alignment: .trailing)
                    // The visible label is the row's title, which the field
                    // itself does not carry.
                    .accessibilityLabel(title)

                EOStepperControl(
                    canDecrement: value > range.lowerBound,
                    canIncrement: value < range.upperBound,
                    onDecrement: { commitEditing(); apply(-step) },
                    onIncrement: { commitEditing(); apply(step) }
                )
            }
        }
        .onAppear { draft = String(value) }
        .onChange(of: value) { _, newValue in
            // While the field has focus it is the source of truth; the rest of
            // the time it follows the value.
            if !isEditing { draft = String(newValue) }
        }
        .onChange(of: draft) { _, typed in
            // Written through on every keystroke rather than only when the field
            // gives up focus. A sheet's Save button lives outside the keyboard
            // and does not resign it first, and there is no Done key above the
            // pad to force the issue — so a number still being typed has to
            // already be the value, or the save drops it.
            //
            // The two ends are not symmetrical. Past the ceiling is settled — no
            // further digit brings a number back down — so it is held there at
            // once. Below the floor may still be on its way up: on the road to
            // 1 850 the field passes through 1 and 18, and a row starting at 500
            // that snapped each of those up would be writing figures nobody
            // typed and fighting the next keystroke. Those wait for the edit to
            // end, where `commitEditing` settles them.
            guard isEditing, let parsed = parsedDraft(typed) else { return }
            if parsed > range.upperBound {
                value = range.upperBound
            } else if parsed >= range.lowerBound {
                value = parsed
            }
        }
        .onChange(of: isEditing) { _, editing in
            // Focusing a zero starts on an empty field: the prompt already said
            // zero, and the first digit typed should be the number rather than
            // the second digit of "0…".
            if editing {
                draft = value == 0 ? "" : String(value)
            } else {
                commitEditing()
            }
        }
    }

    /// Hides a zero behind the prompt while the field is idle, and hands typing
    /// straight through while it is not.
    private var draftBinding: Binding<String> {
        Binding(get: { displayedDraft }, set: { draft = $0 })
    }

    /// Steps the value and shows it. The field is written to explicitly because
    /// tapping a button does not take focus away from a text field, so the sync
    /// that runs on losing focus would not have run.
    private func apply(_ delta: Int) {
        value = clamped(value + delta)
        draft = String(value)
    }

    /// Reads the field back into the value, clamped to the range.
    ///
    /// Something unreadable — or nothing at all — falls back to the value rather
    /// than to zero: clearing the field to retype it is not the same as asking
    /// for none.
    private func commitEditing() {
        value = clamped(parsedDraft(draft) ?? value)
        draft = String(value)
    }

    private func clamped(_ candidate: Int) -> Int {
        min(max(candidate, range.lowerBound), range.upperBound)
    }

    /// ASCII digits, with a single leading minus where the range allows one.
    ///
    /// `Character.isNumber` is also true of "٣" and "½", and a minus in the
    /// middle is not a number either — in both cases `Int` returns nil and the
    /// edit would quietly revert to the previous figure.
    private func parsedDraft(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let isNegative = range.lowerBound < 0
            && (trimmed.hasPrefix("-") || trimmed.hasPrefix("\u{2212}"))
        let digits = trimmed.filter { $0.isASCII && $0.isNumber }
        guard let magnitude = Int(digits) else { return nil }
        return isNegative ? -magnitude : magnitude
    }
}

/// The standalone `−  |  +` capsule control.
struct EOStepperControl: View {
    var canDecrement: Bool = true
    var canIncrement: Bool = true
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    private let height: CGFloat = 34
    private let buttonWidth: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            button(symbol: "minus", enabled: canDecrement, action: onDecrement)

            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 1, height: height * 0.5)

            button(symbol: "plus", enabled: canIncrement, action: onIncrement)
        }
        .frame(height: height)
        .background(
            EOTheme.Palette.controlFill,
            in: RoundedRectangle(cornerRadius: EOTheme.Metrics.pillRadius, style: .continuous)
        )
    }

    private func button(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
                .frame(width: buttonWidth, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Destructive row for a `Menu` or `.contextMenu`.
///
/// `role: .destructive` alone only reddens the title — the SF Symbol keeps
/// inheriting the ambient tint (which the app sets to `.primary` for toolbars),
/// so the icon stays black. Pinning the tint makes the whole row red.
struct EODestructiveMenuButton: View {
    private let title: Text
    private let systemImage: String
    private let action: () -> Void

    init(_ titleKey: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.title = Text(titleKey)
        self.systemImage = systemImage
        self.action = action
    }

    init(title: Text, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(role: .destructive, action: action) {
            Label {
                title
            } icon: {
                Image(systemName: systemImage)
            }
        }
        .tint(EOTheme.Palette.destructive)
    }
}

/// Centred tinted action inside a card ("Save", "Clear").
struct EOInlineActionRow: View {
    private let title: Text
    private let tint: Color
    private let isEnabled: Bool
    private let action: () -> Void

    init(
        _ titleKey: LocalizedStringKey,
        tint: Color = EOTheme.Palette.accent,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = Text(titleKey)
        self.tint = tint
        self.isEnabled = isEnabled
        self.action = action
    }

    init(
        title: Text,
        tint: Color = EOTheme.Palette.accent,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.tint = tint
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            title
                .font(EOTheme.Typography.rowTitle)
                .foregroundStyle(isEnabled ? tint : Color.secondary.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, EOTheme.Metrics.rowVerticalPadding)
                .frame(minHeight: EOTheme.Metrics.rowMinHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

/// Header row of a card that carries a trailing tinted glyph
/// ("Add Food 🔍", "Add Servings ＋", "Add Meal ＋").
struct EOCardHeaderRow: View {
    private let title: Text
    private let systemImage: String
    private let tint: Color
    private let action: () -> Void

    init(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        tint: Color = EOTheme.Palette.accent,
        action: @escaping () -> Void
    ) {
        self.title = Text(titleKey)
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    init(
        title: Text,
        systemImage: String,
        tint: Color = EOTheme.Palette.accent,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            EOListRow(
                title: title,
                accessory: .symbol(name: systemImage, color: tint)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Plain title row used as the first line of a read-only card
/// ("Food in Meal:", "Ingredients:", "Nutrition Facts").
struct EOCardTitleRow: View {
    private let title: Text

    init(_ titleKey: LocalizedStringKey) { self.title = Text(titleKey) }
    init(title: Text) { self.title = title }

    var body: some View {
        title
            .font(EOTheme.Typography.rowTitle)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, EOTheme.Metrics.cardInset)
            .padding(.vertical, EOTheme.Metrics.rowVerticalPadding)
            .frame(minHeight: EOTheme.Metrics.rowMinHeight)
    }
}

// MARK: - Segmented picker

/// Segmented control (Products / Meals / Recipes).
struct EOSegmentedPicker<Value: Hashable>: View {
    struct Segment: Identifiable {
        let id: Value
        let title: Text

        init(_ id: Value, title: Text) {
            self.id = id
            self.title = title
        }
    }

    @Binding var selection: Value
    let segments: [Segment]

    /// The platform control, not a drawing of one.
    ///
    /// This was a row of buttons with a capsule slid between them by
    /// `matchedGeometryEffect`. It looked close enough standing still and was
    /// wrong the moment it was touched: the system control can be dragged —
    /// press the selection and scrub along the track, and it follows the finger
    /// and settles under it — which a row of buttons cannot do, because a button
    /// only knows it was tapped. It also missed the material, the selection
    /// haptic, the pressed state, and the way the control reflows under larger
    /// text.
    ///
    /// Reproducing all of that is a rewrite of something the platform ships and
    /// keeps changing. Wrapping it costs the custom shadow, which is the one
    /// thing here worth losing.
    var body: some View {
        Picker("", selection: $selection) {
            ForEach(segments) { segment in
                segment.title.tag(segment.id)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

// MARK: - Search bar

/// Bottom-docked search row from the "Find Products" mock-up: a circular
/// barcode-scanner button on the left and a capsule search field on the right.
struct EOSearchBar: View {
    @Binding var text: String
    var showsScanner: Bool = true
    var onScan: () -> Void = {}

    @FocusState private var isFocused: Bool

    private let height: CGFloat = 52

    var body: some View {
        HStack(spacing: 12) {
            if showsScanner {
                Button(action: onScan) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: height, height: height)
                        .background(EOTheme.Palette.card, in: Circle())
                        .shadow(color: .black.opacity(0.10), radius: 10, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("barcode.scanner.title"))
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.secondary)

                TextField("search.prompt", text: $text)
                    .textFieldStyle(.plain)
                    .font(EOTheme.Typography.rowTitle)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .focused($isFocused)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.secondary.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(EOTheme.Palette.card, in: Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 10, y: 3)
            .contentShape(Capsule(style: .continuous))
            .onTapGesture { isFocused = true }
        }
        .padding(.horizontal, EOTheme.Metrics.screenInset)
        .padding(.bottom, 8)
    }
}

// MARK: - Buttons

/// Blue capsule call-to-action (Continue / Finish).
///
/// `fillsWidth` is for the one that sits at the foot of a sheet and spans it —
/// the import buttons. Those used to be a `PressableIconButton` with an accent
/// rectangle put behind it, which drew two buttons: that component ends in
/// `.glassEffect()`, so a glass capsule sat inside the rectangle, and its
/// press animation scaled the whole thing up by 12% until it overflowed what it
/// was drawn in.
struct EOPrimaryButton: View {
    private let title: Text
    private let systemImage: String?
    private let isEnabled: Bool
    private let isLoading: Bool
    private let fillsWidth: Bool
    private let action: () -> Void

    init(
        _ titleKey: LocalizedStringKey,
        systemImage: String? = nil,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        fillsWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = Text(titleKey)
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.fillsWidth = fillsWidth
        self.action = action
    }

    init(
        title: Text,
        systemImage: String? = nil,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        fillsWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.fillsWidth = fillsWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                label
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 30)
            .padding(.vertical, 14)
            // Applied to the content, before the background, so the fill is
            // the shape that grows rather than a pill floating in a wider box.
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .background(
                (isEnabled ? EOTheme.Palette.accent : Color.secondary.opacity(0.45)),
                in: Capsule(style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label { title } icon: { Image(systemName: systemImage) }
                .labelStyle(.titleAndIcon)
                .font(.body.weight(.semibold))
        } else {
            title.font(.body.weight(.regular))
        }
    }
}

// MARK: - Sheet header

/// Trailing action of a sheet header.
enum EOSheetHeaderTrailing {
    case none
    /// Blue filled circle with a checkmark (confirm / save).
    case confirm(isEnabled: Bool, action: () -> Void)
    /// Grey circle with an arbitrary SF Symbol (share, ellipsis…).
    case symbol(name: String, action: () -> Void)
}

/// Native toolbar chrome for a modal sheet.
///
/// The mock-ups' "grey ⨉ / title / blue ✓" header is exactly what the system
/// renders for `ButtonRole.close` and `ButtonRole.confirm` in an inline
/// navigation bar, so sheets use the real toolbar instead of a hand-rolled one.
/// Apply to the sheet's root view *inside* a `NavigationStack`.
extension View {
    func eoSheetChrome(
        title: Text,
        trailing: EOSheetHeaderTrailing = .none,
        onClose: @escaping () -> Void
    ) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close, action: onClose)
                }

                ToolbarItem(placement: .confirmationAction) {
                    switch trailing {
                    case .none:
                        EmptyView()
                    case .confirm(let isEnabled, let action):
                        // The prominent confirm button draws its fill from the
                        // tint, so it opts back into the accent colour.
                        Button(role: .confirm, action: action)
                            .disabled(!isEnabled)
                            .tint(EOTheme.Palette.accent)
                    case .symbol(let name, let action):
                        Button(action: action) {
                            Image(systemName: name)
                        }
                    }
                }
            }
            // Bar glyphs use the label colour, not the accent, as in the mock-ups.
            .tint(.primary)
    }

    func eoSheetChrome(
        _ titleKey: LocalizedStringKey,
        trailing: EOSheetHeaderTrailing = .none,
        onClose: @escaping () -> Void
    ) -> some View {
        eoSheetChrome(title: Text(titleKey), trailing: trailing, onClose: onClose)
    }

    /// Sheet chrome whose trailing control is drawn by the caller.
    ///
    /// For the times that control is not a button — a `Menu`, a `ShareLink` —
    /// which `EOSheetHeaderTrailing` cannot express and which must not be faked
    /// with a button that raises another sheet: SwiftUI presents one sheet at a
    /// time, so a share sheet asked for from inside a sheet is simply dropped
    /// with "only presenting a single sheet is supported" in the log.
    func eoSheetChrome<Trailing: View>(
        title: Text,
        onClose: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close, action: onClose)
                }

                ToolbarItem(placement: .confirmationAction) {
                    trailing()
                }
            }
            .tint(.primary)
    }
}

// MARK: - Empty state

/// Centred grey placeholder shown when a screen has no content.
struct EOEmptyState: View {
    private let title: Text
    private let subtitle: Text?

    init(_ titleKey: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.title = Text(titleKey)
        self.subtitle = subtitle.map { Text($0) }
    }

    init(title: Text, subtitle: Text? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 8) {
            title
                .font(EOTheme.Typography.emptyTitle)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)

            if let subtitle {
                subtitle
                    .font(EOTheme.Typography.emptySubtitle)
                    .foregroundStyle(Color.secondary.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Screen scaffolding

extension View {
    /// Applies the standard page background to a screen.
    func eoPageBackground() -> some View {
        background(EOTheme.Palette.pageBackground.ignoresSafeArea())
    }

    /// Long-press context menu for a row inside `EOCard`.
    ///
    /// Rows are transparent (the card paints the background), so the system
    /// would lift a see-through, square preview. Giving the row an opaque card
    /// background and an explicit rounded preview shape makes the lifted
    /// snapshot line up with the row.
    func eoRowContextMenu<MenuItems: View>(
        @ViewBuilder menuItems: () -> MenuItems
    ) -> some View {
        background(EOTheme.Palette.card)
            .contentShape(
                .contextMenuPreview,
                RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
            )
            .contextMenu(menuItems: menuItems)
    }

    /// Long-press context menu for a view that already paints its own card
    /// background (the water tile, meal cards…).
    ///
    /// Unlike `eoRowContextMenu` this adds no background — doing so would draw
    /// an opaque rectangle behind the card's rounded corners.
    func eoCardContextMenu<MenuItems: View>(
        cornerRadius: CGFloat = EOTheme.Metrics.cardRadius,
        @ViewBuilder menuItems: () -> MenuItems
    ) -> some View {
        contentShape(
            .contextMenuPreview,
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .contextMenu(menuItems: menuItems)
    }

    /// Card context menu with a custom lifted preview — used where the long
    /// press exists to *show* something rather than to offer actions.
    func eoCardContextMenu<MenuItems: View, Preview: View>(
        cornerRadius: CGFloat = EOTheme.Metrics.cardRadius,
        @ViewBuilder menuItems: () -> MenuItems,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        contentShape(
            .contextMenuPreview,
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .contextMenu(menuItems: menuItems, preview: preview)
    }

    /// Standard horizontal inset for a card placed directly on the page.
    func eoCardInsets() -> some View {
        padding(.horizontal, EOTheme.Metrics.screenInset)
    }
}

/// A section = optional header + card + optional footnote, spaced per the mock-ups.
struct EOSection<Content: View>: View {
    private let header: Text?
    private let footnote: Text?
    private let content: Content

    init(
        header: Text? = nil,
        footnote: Text? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header
        self.footnote = footnote
        self.content = content()
    }

    init(
        _ headerKey: LocalizedStringKey,
        footnote: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(header: Text(headerKey), footnote: footnote.map { Text($0) }, content: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EOTheme.Metrics.headerSpacing) {
            if let header {
                header
                    .font(EOTheme.Typography.groupHeader)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, EOTheme.Metrics.cardInset)
            }

            EOCard {
                content
            }

            if let footnote {
                footnote
                    .font(EOTheme.Typography.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, EOTheme.Metrics.cardInset)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, EOTheme.Metrics.screenInset)
    }
}
