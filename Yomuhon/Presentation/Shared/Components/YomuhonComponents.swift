//
//  YomuhonComponents.swift
//  Yomuhon
//

import SwiftUI

enum YomuhonSpacing {
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let extraLarge: CGFloat = 40
    static let grand: CGFloat = 64
}

enum YomuhonLayout {
    static let sidebarMinWidth: CGFloat = 240
    static let regularShellExitBreakpoint: CGFloat = 880
    static let regularShellEnterBreakpoint: CGFloat = 920
    static let compactContentPadding = YomuhonSpacing.large
    static let regularContentPadding = YomuhonSpacing.extraLarge
    static let emptyStateMinHeight: CGFloat = 360
    static let emptyStateMessageWidth: CGFloat = 280
    static let mangaCoverMinWidth: CGFloat = 208
    static let mangaCoverMaxWidth: CGFloat = 280
    static let detailCoverCompactWidth: CGFloat = 176
    static let detailCoverRegularWidth: CGFloat = 240
    static let detailSidebarWidth: CGFloat = 280
    static let detailContentWidth: CGFloat = 780
    static let searchMaxWidth: CGFloat = 400
    static let sourceSearchMaxWidth: CGFloat = 460
    static let sourceSettingsContentWidth: CGFloat = 820
    static let sourceRepositoryNameWidth: CGFloat = 280
    static let sourceRepositoryURLWidth: CGFloat = 560
    static let readableTextWidth: CGFloat = 780
    static let readerPageMaxWidth: CGFloat = 640
    static let readerPageMaxHeight: CGFloat = 896
    static let readerHUDWidth: CGFloat = 640
    static let readerModePickerWidth: CGFloat = 160
    static let readerPageControlSize: CGFloat = 40
    static let readerPageAspectRatio: CGFloat = 0.72
    static let quietProgressHeight: CGFloat = 2
    static let coverAccentWidth = YomuhonSpacing.extraLarge
    static let coverAccentHeight: CGFloat = 2
    static let loadingIndicatorScale: CGFloat = 0.82
}

func safeDimension(_ value: CGFloat, fallback: CGFloat = 0) -> CGFloat {
    guard value.isFinite, value >= 0 else {
        return fallback
    }

    return value
}

func safePositiveDimension(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
    guard value.isFinite, value > 0 else {
        return fallback
    }

    return value
}

func safeOptionalDimension(_ value: CGFloat?) -> CGFloat? {
    guard let value, value.isFinite, value >= 0 else {
        return nil
    }

    return value
}

enum YomuhonTypography {
    static let largeTitle = Font.largeTitle.weight(.semibold)
    static let title = Font.title.weight(.semibold)
    static let headline = Font.headline.weight(.semibold)
    static let body = Font.body
    static let caption = Font.caption
    static let captionMedium = Font.caption.weight(.medium)
    static let calloutMedium = Font.callout.weight(.medium)
    static let calloutSemibold = Font.callout.weight(.semibold)
}

enum YomuhonMotion {
    static let subtle = Animation.easeInOut(duration: 0.18)
    static let relaxed = Animation.easeInOut(duration: 0.22)
}

struct SurfacePanel: ViewModifier {
    @Environment(\.yomuhonTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background(theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.separator, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct YomuhonPressableButtonStyle: ButtonStyle {
    let theme: YomuhonTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(theme.animation, value: configuration.isPressed)
    }
}

struct YomuhonHoverLift: ViewModifier {
    let isHovering: Bool
    let theme: YomuhonTheme
    let scale: CGFloat
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering ? scale : 1)
            .shadow(
                color: isHovering ? theme.shadow : theme.background.opacity(0),
                radius: isHovering ? shadowRadius : 0,
                x: 0,
                y: isHovering ? shadowY : 0
            )
            .animation(theme.animation, value: isHovering)
    }
}

extension View {
    func surfacePanel() -> some View {
        modifier(SurfacePanel())
    }

    func yomuhonHoverLift(
        isHovering: Bool,
        theme: YomuhonTheme,
        scale: CGFloat = 1.004,
        shadowRadius: CGFloat = YomuhonSpacing.small,
        shadowY: CGFloat = YomuhonSpacing.small
    ) -> some View {
        modifier(
            YomuhonHoverLift(
                isHovering: isHovering,
                theme: theme,
                scale: scale,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }
}

struct YomuhonPageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing

    @Environment(\.yomuhonTheme) private var theme

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: YomuhonSpacing.extraLarge) {
            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                Text(title)
                    .font(YomuhonTypography.title)
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(2)

                if let subtitle {
                    Text(subtitle)
                        .font(YomuhonTypography.body)
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: YomuhonSpacing.large)

            trailing
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension YomuhonPageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

struct YomuhonNativeSearchField: View {
    @Binding var text: String
    let placeholder: LocalizedStringKey
    var maxWidth: CGFloat?

    @Environment(\.yomuhonTheme) private var theme

    init(
        text: Binding<String>,
        placeholder: LocalizedStringKey = "search.placeholder",
        maxWidth: CGFloat? = nil
    ) {
        _text = text
        self.placeholder = placeholder
        self.maxWidth = maxWidth
    }

    var body: some View {
        HStack(spacing: YomuhonSpacing.small) {
            Image(systemName: "magnifyingglass")
                .font(YomuhonTypography.captionMedium)
                .foregroundColor(theme.textSecondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("search.field")
                .font(.body)
                .foregroundColor(theme.textPrimary)

            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(YomuhonTypography.captionMedium)
                        .foregroundColor(theme.textSecondary)
                }
                .buttonStyle(YomuhonPressableButtonStyle(theme: theme))
                .help("search.clear")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, YomuhonSpacing.medium)
        .padding(.vertical, YomuhonSpacing.small)
        .background(theme.secondaryBackground.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.72), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: safeOptionalDimension(maxWidth))
        .frame(minHeight: safePositiveDimension(YomuhonSpacing.extraLarge, fallback: 40))
        .animation(theme.animation, value: text)
    }
}

struct YomuhonSidebarSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Section(title) {
            content
        }
    }
}

struct YomuhonSidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        HStack(spacing: YomuhonSpacing.small) {
            Image(systemName: systemImage)
                .font(YomuhonTypography.captionMedium)
                .foregroundColor(isSelected ? theme.accent : theme.textSecondary)
                .frame(width: safePositiveDimension(YomuhonSpacing.medium, fallback: 16))

            Text(title)
                .font(YomuhonTypography.calloutMedium)
                .foregroundColor(isSelected ? theme.textPrimary : theme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, YomuhonSpacing.small)
        .padding(.vertical, YomuhonSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? theme.secondaryBackground.opacity(0.52) : theme.sidebar.opacity(0))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct YomuhonSectionTitle: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var detail: String?

    @Environment(\.yomuhonTheme) private var theme

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        detail: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: YomuhonSpacing.medium) {
            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                Text(title)
                    .font(YomuhonTypography.headline)
                    .foregroundColor(theme.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(YomuhonTypography.body)
                        .foregroundColor(theme.textSecondary)
                }
            }

            Spacer()

            if let detail {
                Text(detail)
                    .font(YomuhonTypography.captionMedium)
                    .foregroundColor(theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct YomuhonMangaCoverCard: View {
    let title: String
    let imageURL: URL?
    let progressValue: Double

    @Environment(\.yomuhonTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
            CoverView(title: title, imageURL: imageURL)
                .aspectRatio(0.70, contentMode: .fit)

            Text(title)
                .font(YomuhonTypography.captionMedium)
                .foregroundColor(theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            YomuhonQuietProgressIndicator(value: progressValue)
                .opacity(progressValue > 0 ? 1 : 0)
        }
        .contentShape(Rectangle())
        .yomuhonHoverLift(isHovering: isHovering, theme: theme)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct YomuhonQuietProgressIndicator: View {
    let value: Double

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let width = safeWidth(proxy.size.width)
            let progress = clampedValue

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.textPrimary.opacity(0.18))

                Capsule()
                    .fill(theme.accent)
                    .frame(width: safeDimension(width * progress))
            }
        }
        .frame(height: safePositiveDimension(YomuhonLayout.quietProgressHeight, fallback: 2))
        .animation(theme.animation, value: value)
    }

    private var clampedValue: CGFloat {
        guard value.isFinite else {
            return 0
        }

        return CGFloat(max(0, min(value, 1)))
    }

    private func safeWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else {
            return 0
        }

        return width
    }
}

struct YomuhonEmptyState: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    @Environment(\.yomuhonTheme) private var theme

    init(
        systemImage: String = "books.vertical",
        title: LocalizedStringKey,
        message: LocalizedStringKey
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    var body: some View {
        VStack(spacing: YomuhonSpacing.medium) {
            Image(systemName: systemImage)
                .font(YomuhonTypography.largeTitle.weight(.light))
                .foregroundColor(theme.textSecondary)

            VStack(spacing: YomuhonSpacing.small) {
                Text(title)
                    .font(YomuhonTypography.headline)
                    .foregroundColor(theme.textPrimary)

                Text(message)
                    .font(YomuhonTypography.body)
                    .foregroundColor(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: safePositiveDimension(YomuhonLayout.emptyStateMessageWidth, fallback: 420))
            }
        }
        .padding(YomuhonSpacing.large)
    }
}

struct YomuhonLoadingView: View {
    let title: LocalizedStringKey?
    let message: LocalizedStringKey?

    @Environment(\.yomuhonTheme) private var theme

    init(title: LocalizedStringKey? = nil, message: LocalizedStringKey? = nil) {
        self.title = title
        self.message = message
    }

    var body: some View {
        VStack(spacing: YomuhonSpacing.medium) {
            ProgressView()
                .scaleEffect(YomuhonLayout.loadingIndicatorScale)

            VStack(spacing: YomuhonSpacing.small) {
                if let title {
                    Text(title)
                        .font(YomuhonTypography.headline)
                        .foregroundColor(theme.textPrimary)
                }

                if let message {
                    Text(message)
                        .font(YomuhonTypography.body)
                        .foregroundColor(theme.textSecondary)
                }
            }
        }
        .padding(YomuhonSpacing.large)
    }
}

struct YomuhonCardContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .surfacePanel()
    }
}

struct YomuhonPrimaryButtonStyle: ButtonStyle {
    let theme: YomuhonTheme

    func makeBody(configuration: Configuration) -> some View {
        YomuhonPrimaryButtonBody(configuration: configuration, theme: theme)
    }
}

private struct YomuhonPrimaryButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let theme: YomuhonTheme

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(YomuhonTypography.calloutSemibold)
            .foregroundColor(foregroundColor)
            .padding(.horizontal, YomuhonSpacing.medium)
            .padding(.vertical, YomuhonSpacing.small)
            .background(backgroundColor)
            .overlay(
                Capsule()
                    .strokeBorder(borderColor, lineWidth: isEnabled ? 0 : 1)
            )
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(theme.animation, value: configuration.isPressed)
            .animation(theme.animation, value: isEnabled)
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return theme.textSecondary
        }

        return theme.id == .ink ? Color.black : theme.background
    }

    private var backgroundColor: Color {
        if !isEnabled {
            return theme.secondaryBackground.opacity(theme.id == .ink ? 0.74 : 0.62)
        }

        return theme.accent
    }

    private var borderColor: Color {
        isEnabled ? Color.clear : theme.separator.opacity(0.7)
    }
}

struct YomuhonSecondaryButtonStyle: ButtonStyle {
    let theme: YomuhonTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(YomuhonTypography.calloutMedium)
            .foregroundColor(theme.textPrimary)
            .padding(.horizontal, YomuhonSpacing.medium)
            .padding(.vertical, YomuhonSpacing.small)
            .background(theme.card)
            .overlay(
                Capsule()
                    .strokeBorder(theme.separator, lineWidth: 1)
            )
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(theme.animation, value: configuration.isPressed)
    }
}
