import SwiftUI
import UIKit
import Combine

/// Selectable app icons. `nil` alternate name == the primary icon (Egg).
enum AppIconOption: String, CaseIterable, Identifiable {
    case egg
    case orange
    case lemon
    case watermelon

    var id: String { rawValue }

    /// Alternate icon name as declared in the asset catalog build settings.
    /// `nil` restores the primary app icon.
    var alternateName: String? {
        switch self {
        case .egg: return nil
        case .orange: return "Orange"
        case .lemon: return "Lemon"
        case .watermelon: return "Watermelon"
        }
    }

    /// Preview thumbnail imageset bundled for the settings picker.
    var previewImageName: String {
        switch self {
        case .egg: return "IconPreviewEgg"
        case .orange: return "IconPreviewOrange"
        case .lemon: return "IconPreviewLemon"
        case .watermelon: return "IconPreviewWatermelon"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .egg: return "settings.app_icon.egg"
        case .orange: return "settings.app_icon.orange"
        case .lemon: return "settings.app_icon.lemon"
        case .watermelon: return "settings.app_icon.watermelon"
        }
    }

    static var current: AppIconOption {
        let name = UIApplication.shared.alternateIconName
        return AppIconOption.allCases.first { $0.alternateName == name } ?? .egg
    }
}

@MainActor
final class AppIconManager: ObservableObject {
    static let shared = AppIconManager()

    @Published private(set) var selected: AppIconOption

    private init() {
        selected = AppIconOption.current
    }

    var supportsAlternateIcons: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    func setIcon(_ option: AppIconOption) {
        guard supportsAlternateIcons else { return }
        guard option.alternateName != UIApplication.shared.alternateIconName else {
            selected = option
            return
        }

        UIApplication.shared.setAlternateIconName(option.alternateName) { error in
            let succeeded = error == nil
            Task { @MainActor [weak self] in
                self?.selected = succeeded ? option : AppIconOption.current
            }
        }
    }
}

struct AppIconPickerView: View {
    @StateObject private var manager = AppIconManager.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: EOTheme.Metrics.headerSpacing) {
                EOCard {
                    ForEach(Array(AppIconOption.allCases.enumerated()), id: \.element.id) { index, option in
                        if index > 0 {
                            EORowSeparator()
                        }

                        Button {
                            manager.setIcon(option)
                        } label: {
                            iconRow(option)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !manager.supportsAlternateIcons {
                    Text("settings.app_icon.unsupported")
                        .font(EOTheme.Typography.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, EOTheme.Metrics.cardInset)
                        .padding(.top, 4)
                }
            }
            .eoCardInsets()
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .eoPageBackground()
        .navigationTitle(Text("settings.app_icon.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Standard list row with a small icon preview on the left.
    private func iconRow(_ option: AppIconOption) -> some View {
        let isSelected = manager.selected == option

        return HStack(spacing: 14) {
            Image(option.previewImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text(option.titleKey)
                .font(EOTheme.Typography.rowTitle)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(EOTheme.Palette.accent)
            }
        }
        .padding(.horizontal, EOTheme.Metrics.cardInset)
        .padding(.vertical, 10)
        .frame(minHeight: EOTheme.Metrics.rowMinHeight)
        .contentShape(Rectangle())
    }
}
