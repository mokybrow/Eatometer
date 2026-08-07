import SwiftUI

struct MainHeaderScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct MainHeaderView: View {
    enum DisplayMode {
        case large
        case compact
    }

    @EnvironmentObject private var userService: UserService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let title: String
    let subtitle: String?
    let username: String
    let onProfileTap: () -> Void
    let onClose: (() -> Void)?
    let trailingAction: TrailingAction?
    let displayMode: DisplayMode

    struct TrailingAction {
        let systemImage: String
        let accessibilityLabelKey: String?
        let action: () -> Void

        init(systemImage: String, accessibilityLabelKey: String? = nil, action: @escaping () -> Void) {
            self.systemImage = systemImage
            self.accessibilityLabelKey = accessibilityLabelKey
            self.action = action
        }
    }

    init(
        title: String,
        subtitle: String? = nil,
        username: String,
        onProfileTap: @escaping () -> Void,
        onClose: (() -> Void)? = nil,
        trailingAction: TrailingAction? = nil,
        displayMode: DisplayMode = .large
    ) {
        self.title = title
        self.subtitle = subtitle
        self.username = username
        self.onProfileTap = onProfileTap
        self.onClose = onClose
        self.trailingAction = trailingAction
        self.displayMode = displayMode
    }

    var body: some View {
        // On iPad / desktop the native navigation bar provides the page title,
        // so the custom in-content header is omitted entirely.
        if horizontalSizeClass == .regular {
            EmptyView()
        } else {
            compactHeader
        }
    }

    private var compactHeader: some View {
        HStack(alignment: .center, spacing: displayMode == .large ? 14 : 12) {
            if let onClose {
                PressableIconButton(action: onClose) {
                    Label("common.close", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .frame(width: closeButtonSize, height: closeButtonSize)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title))
                    .font(titleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()

            // On iPad / desktop (regular width) the profile lives in the sidebar,
            // so the in-header avatar is hidden to avoid duplication.
            if horizontalSizeClass != .regular {
                PressableIconButton(action: onProfileTap) {
                    Label("profile.notifications.inbox.title", systemImage: "bell")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: avatarSize, height: avatarSize)
                        .background(.regularMaterial, in: Circle())
                }
            }

            if let trailingAction {
                PressableIconButton(action: trailingAction.action) {
                    Label(
                        trailingAction.accessibilityLabelKey.map { LocalizedStringKey($0) } ?? LocalizedStringKey("common.add"),
                        systemImage: trailingAction.systemImage
                    )
                    .labelStyle(.iconOnly)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: closeButtonSize, height: closeButtonSize)
                    .background(.regularMaterial, in: Circle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleFont: Font {
        switch displayMode {
        case .large:
            return .system(size: 34, weight: .bold)
        case .compact:
            return .system(size: 18, weight: .semibold)
        }
    }

    private var avatarSize: CGFloat {
        switch displayMode {
        case .large:
            return 44
        case .compact:
            return 34
        }
    }

    private var closeButtonSize: CGFloat {
        switch displayMode {
        case .large:
            return 44
        case .compact:
            return 38
        }
    }

    private var resolvedUsername: String {
        let firstName = userService.currentUser?.firstName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !firstName.isEmpty {
            return firstName
        }

        let lastName = userService.currentUser?.lastName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !lastName.isEmpty {
            return lastName
        }

        let trimmed = userService.currentUser?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }

        let fallback = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "Eatometer" : fallback
    }
}

struct MainHeaderCompactOverlay: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let title: String
    let username: String
    let onProfileTap: () -> Void
    let progress: CGFloat

    var body: some View {
        // The scrolled compact title is only used on iPhone; iPad uses the
        // native navigation bar which already collapses the large title.
        if horizontalSizeClass == .regular {
            EmptyView()
        } else {
            overlayContent
        }
    }

    private var overlayContent: some View {
        VStack(spacing: 0) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black.opacity(0.96))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 52)
                .frame(height: 46)
                .frame(maxWidth: .infinity)
                .shadow(
                    color: colorScheme == .dark ? Color.black.opacity(0.42) : Color.white.opacity(0.36),
                    radius: 12,
                    x: 0,
                    y: 0
                )

            Spacer(minLength: 0)
        }
        .frame(height: 80)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(colorScheme == .dark ? 0.72 : 0.88)

                LinearGradient(
                    colors: [
                        colorScheme == .dark ? Color.black.opacity(0.34) : Color.white.opacity(0.34),
                        colorScheme == .dark ? Color.black.opacity(0.20) : Color.white.opacity(0.18),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Rectangle()
                    .fill(colorScheme == .dark ? Color.black.opacity(0.16) : Color.white.opacity(0.14))

                LinearGradient(
                    colors: [
                        colorScheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.20),
                        colorScheme == .dark ? Color.black.opacity(0.08) : Color.white.opacity(0.08),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.04 : 0.14),
                        Color.white.opacity(colorScheme == .dark ? 0.02 : 0.06),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
                .opacity(progress)
                .frame(height: 120)
                .blur(radius: 24)
                .offset(y: -6)
                .ignoresSafeArea(edges: .top)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(0.99), location: 0.18),
                            .init(color: .black.opacity(0.96), location: 0.36),
                            .init(color: .black.opacity(0.84), location: 0.54),
                            .init(color: .black.opacity(0.58), location: 0.72),
                            .init(color: .black.opacity(0.20), location: 0.90),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .top)
                }
        }
        .opacity(progress * 0.92)
        .allowsHitTesting(false)
        .zIndex(10)
        .animation(.easeInOut(duration: 0.18), value: progress)
    }
}

/// Root-screen navigation chrome. On iPhone (compact) the navigation bar stays
/// hidden and the screen draws its own `MainHeaderView`. On iPad / desktop
/// (regular) the native navigation bar is shown with a large title, which also
/// provides the system sidebar-toggle button for free.
private struct RootNavigationChrome: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let titleKey: LocalizedStringKey

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                .navigationTitle(titleKey)
                .navigationBarTitleDisplayMode(.large)
        } else {
            content
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

extension View {
    func rootNavigationChrome(_ titleKey: LocalizedStringKey) -> some View {
        modifier(RootNavigationChrome(titleKey: titleKey))
    }
}
