//
//  YomuhonFeedbackComponents.swift
//  Yomuhon
//

import SwiftUI

typealias YomuhonLoadingState = YomuhonLoadingView

struct YomuhonErrorState: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var retryTitle: LocalizedStringKey?
    var retryAction: (() -> Void)?

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        VStack(spacing: YomuhonSpacing.medium) {
            YomuhonEmptyState(
                systemImage: "exclamationmark.triangle",
                title: title,
                message: message
            )

            if let retryTitle, let retryAction {
                Button(action: retryAction) {
                    Label(retryTitle, systemImage: "arrow.clockwise")
                }
                .buttonStyle(YomuhonSecondaryButtonStyle(theme: theme))
            }
        }
    }
}

struct YomuhonToast: View {
    enum Style {
        case info
        case success
        case error
    }

    let title: LocalizedStringKey
    var message: LocalizedStringKey?
    var style: Style = .info

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: YomuhonSpacing.medium) {
            Image(systemName: systemImage)
                .font(YomuhonTypography.calloutMedium)
                .foregroundColor(tintColor)

            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                Text(title)
                    .font(YomuhonTypography.calloutSemibold)
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(2)

                if let message {
                    Text(message)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(YomuhonSpacing.medium)
        .background(theme.sidebar.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: theme.shadow, radius: YomuhonSpacing.small, y: YomuhonSpacing.small)
    }

    private var systemImage: String {
        switch style {
        case .info:
            return "info.circle"
        case .success:
            return "checkmark.circle"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    private var tintColor: Color {
        switch style {
        case .info, .success:
            return theme.textSecondary
        case .error:
            return theme.accent
        }
    }
}

struct YomuhonDialog<Actions: View>: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let actions: Actions

    @Environment(\.yomuhonTheme) private var theme

    init(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.large) {
            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                Text(title)
                    .font(YomuhonTypography.headline)
                    .foregroundColor(theme.textPrimary)

                Text(message)
                    .font(YomuhonTypography.body)
                    .foregroundColor(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: YomuhonSpacing.small) {
                Spacer()
                actions
            }
        }
        .padding(YomuhonSpacing.large)
        .background(theme.secondaryBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: safePositiveDimension(420, fallback: 420))
    }
}
