//
//  YomuhonReaderComponents.swift
//  Yomuhon
//

import SwiftUI

struct ReaderProgressFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

struct YomuhonReaderProgress: View {
    let value: Double
    let label: String?
    let hoverLabel: String?

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(theme.id == .ink ? 0.18 : 0.22))

                    Capsule()
                        .fill(Color.white.opacity(theme.id == .ink ? 0.88 : 0.82))
                        .frame(width: max(0, min(proxy.size.width, proxy.size.width * value)))
                }
            }
            .frame(height: 4)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: ReaderProgressFramePreferenceKey.self,
                            value: proxy.frame(in: .global)
                        )
                }
            )

            if let displayLabel = hoverLabel ?? label {
                Text(displayLabel)
                    .font(YomuhonTypography.captionMedium)
                    .foregroundColor(Color.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
    }
}

struct YomuhonReaderHUD<Trailing: View, BottomControls: View>: View {
    let title: String
    let subtitle: String
    let progress: Double
    let progressLabel: String?
    let hoverProgressLabel: String?
    let trailing: Trailing
    let bottomControls: BottomControls
    let showsBottomControls: Bool
    let closeAction: () -> Void
    let isDark: Bool

    @Environment(\.yomuhonTheme) private var theme

    init(
        title: String,
        subtitle: String,
        progress: Double,
        progressLabel: String? = nil,
        hoverProgressLabel: String? = nil,
        showsBottomControls: Bool = true,
        closeAction: @escaping () -> Void = {},
        isDark: Bool = true,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder bottomControls: () -> BottomControls
    ) {
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.progressLabel = progressLabel
        self.hoverProgressLabel = hoverProgressLabel
        self.showsBottomControls = showsBottomControls
        self.closeAction = closeAction
        self.isDark = isDark
        self.trailing = trailing()
        self.bottomControls = bottomControls()
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            Spacer(minLength: 0)

            if showsBottomControls {
                bottomBar
            }
        }
        .padding(.horizontal, YomuhonSpacing.medium)
        .padding(.vertical, 6)
    }

    private var topBar: some View {
        HStack(spacing: YomuhonSpacing.medium) {
            ReaderRoundButton(systemName: "xmark", label: "common.close", action: closeAction, isDark: isDark)
                .accessibilityIdentifier("reader.close")

            Spacer(minLength: YomuhonSpacing.small)

            VStack(spacing: 3) {
                Text(subtitle)
                    .font(YomuhonTypography.calloutSemibold)
                    .foregroundColor(isDark ? Color.white.opacity(0.92) : Color.black.opacity(0.86))
                    .lineLimit(1)

                if let progressLabel {
                    Text(progressLabel)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(isDark ? Color.white.opacity(0.58) : Color.black.opacity(0.55))
                        .lineLimit(1)
                } else {
                    Text(title)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(isDark ? Color.white.opacity(0.58) : Color.black.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 420)

            Spacer(minLength: YomuhonSpacing.small)

            HStack(spacing: YomuhonSpacing.small) {
                trailing
            }
        }
        .padding(.horizontal, YomuhonSpacing.small)
        .padding(.vertical, 8)
        .readerHUDSurface(theme: theme, radius: 22, isDark: isDark)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            YomuhonReaderProgress(
                value: progress,
                label: progressLabel,
                hoverLabel: hoverProgressLabel
            )

            HStack(spacing: YomuhonSpacing.large) {
                bottomControls
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, YomuhonSpacing.medium)
        .padding(.vertical, 10)
        .readerHUDSurface(theme: theme, radius: 22, isDark: isDark)
        .frame(maxWidth: 620)
    }
}

struct ReaderRoundButton: View {
    let systemName: String
    let label: LocalizedStringKey
    let action: () -> Void
    var isDark: Bool = true

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(YomuhonTypography.calloutMedium)
                .foregroundColor(isDark ? Color.white.opacity(0.88) : Color.black.opacity(0.82))
                .frame(width: 34, height: 34)
                .background(isDark ? Color.white.opacity(0.105) : Color.black.opacity(0.075))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private extension View {
    func readerHUDSurface(theme: YomuhonTheme, radius: CGFloat, isDark: Bool = true) -> some View {
        background(
            ZStack {
                if isDark {
                    Color.black.opacity(theme.id == .ink ? 0.72 : 0.64)
                    Color.white.opacity(theme.id == .ink ? 0.045 : 0.060)
                } else {
                    Color.white.opacity(0.78)
                    Color.black.opacity(0.035)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(isDark ? Color.white.opacity(0.115) : Color.black.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: Color.black.opacity(isDark ? 0.35 : 0.16), radius: 22, x: 0, y: 12)
    }
}


struct YomuhonSkeletonBlock: View {
    var cornerRadius: CGFloat = 12

    @Environment(\.yomuhonTheme) private var theme
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(theme.secondaryBackground.opacity(theme.id == .ink ? 0.72 : 1.0))
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.00),
                        Color.white.opacity(theme.id == .ink ? 0.10 : 0.36),
                        Color.white.opacity(0.00)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: pulse ? 180 : -180)
            )
            .clipped()
            .onAppear {
                withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
            .accessibilityHidden(true)
    }
}
