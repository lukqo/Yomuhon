//
//  YomuhonListComponents.swift
//  Yomuhon
//

import SwiftUI

struct YomuhonChapterRow: View {
    let title: String
    let subtitle: String?
    var isCurrent = false
    var isDownloaded = false

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        HStack(spacing: YomuhonSpacing.medium) {
            Image(systemName: isDownloaded ? "checkmark.circle.fill" : "book.closed")
                .font(YomuhonTypography.captionMedium)
                .foregroundColor(isDownloaded ? theme.accent : theme.textSecondary)
                .frame(width: safePositiveDimension(YomuhonSpacing.large, fallback: 24))

            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                Text(title)
                    .font(YomuhonTypography.calloutMedium)
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(2)

                if let subtitle {
                    Text(subtitle)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isCurrent {
                YomuhonTag(title: "reader.reading", systemImage: nil, isSelected: true)
            }
        }
        .padding(.horizontal, YomuhonSpacing.medium)
        .padding(.vertical, YomuhonSpacing.medium)
        .contentShape(Rectangle())
    }
}

struct YomuhonDownloadRow: View {
    let title: String
    let subtitle: String
    let metadata: String
    let progress: Double
    let stateTitle: LocalizedStringKey
    var stateSystemImage = "checkmark.circle.fill"

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        HStack(spacing: YomuhonSpacing.medium) {
            CoverStatusIcon(systemName: stateSystemImage)

            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                HStack(alignment: .firstTextBaseline, spacing: YomuhonSpacing.small) {
                    Text(title)
                        .font(YomuhonTypography.calloutSemibold)
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                }

                Text(metadata)
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)

                YomuhonProgressBar(value: progress)
            }

            Spacer()

            Label(stateTitle, systemImage: stateSystemImage)
                .font(YomuhonTypography.captionMedium)
                .foregroundColor(theme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, YomuhonSpacing.medium)
        .padding(.vertical, YomuhonSpacing.medium)
        .contentShape(Rectangle())
    }
}

struct YomuhonSettingsRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let value: String?
    var showsDisclosure = false

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        HStack(spacing: YomuhonSpacing.medium) {
            CoverStatusIcon(systemName: systemImage)

            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                Text(title)
                    .font(YomuhonTypography.calloutMedium)
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let value {
                Text(value)
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
            }

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(YomuhonTypography.captionMedium)
                    .foregroundColor(theme.textSecondary)
            }
        }
        .padding(.horizontal, YomuhonSpacing.medium)
        .padding(.vertical, YomuhonSpacing.medium)
        .contentShape(Rectangle())
    }
}

struct YomuhonSourceSelectorOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
}

struct YomuhonSourceSelector: View {
    enum Layout {
        case vertical
        case horizontal
    }

    let options: [YomuhonSourceSelectorOption]
    @Binding var selectedID: String
    var layout: Layout = .vertical
    let onSelect: (YomuhonSourceSelectorOption) -> Void

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        Group {
            if layout == .horizontal {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: YomuhonSpacing.small) {
                        optionButtons
                    }
                }
            } else {
                VStack(spacing: YomuhonSpacing.small) {
                    optionButtons
                }
            }
        }
    }

    private var optionButtons: some View {
        ForEach(options) { option in
            Button {
                selectedID = option.id
                onSelect(option)
            } label: {
                HStack(spacing: YomuhonSpacing.medium) {
                    Rectangle()
                        .fill(selectedID == option.id ? theme.accent : theme.separator)
                        .frame(width: safePositiveDimension(YomuhonSpacing.small / 2, fallback: 4))
                        .opacity(selectedID == option.id ? 1 : 0.54)

                    VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                        Text(option.title)
                            .font(YomuhonTypography.calloutSemibold)
                            .foregroundColor(theme.textPrimary)
                            .lineLimit(1)

                        if let subtitle = option.subtitle {
                            Text(subtitle)
                                .font(YomuhonTypography.caption)
                                .foregroundColor(theme.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: YomuhonSpacing.medium)
                }
                .padding(.horizontal, YomuhonSpacing.medium)
                .padding(.vertical, YomuhonSpacing.medium)
                .frame(
                    minWidth: layout == .horizontal ? safePositiveDimension(160, fallback: 160) : nil,
                    maxWidth: layout == .vertical ? .infinity : nil,
                    alignment: .leading
                )
                .background(selectedID == option.id ? theme.secondaryBackground.opacity(0.72) : theme.card.opacity(0))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(YomuhonPressableButtonStyle(theme: theme))
        }
    }
}

private struct CoverStatusIcon: View {
    let systemName: String

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        Image(systemName: systemName)
            .font(YomuhonTypography.calloutMedium)
            .foregroundColor(theme.accent)
            .frame(
                width: safePositiveDimension(YomuhonSpacing.extraLarge, fallback: 40),
                height: safePositiveDimension(YomuhonSpacing.extraLarge, fallback: 40)
            )
            .background(theme.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
