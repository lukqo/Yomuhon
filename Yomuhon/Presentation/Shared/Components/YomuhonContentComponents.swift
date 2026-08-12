//
//  YomuhonContentComponents.swift
//  Yomuhon
//

import SwiftUI

struct YomuhonCoverCard: View {
    enum Variant {
        case standard
        case compact
    }

    let title: String
    let imageURL: URL?
    var metadata: String?
    var progress: Double?
    var variant: Variant = .standard

    @Environment(\.yomuhonTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
            CoverView(title: title, imageURL: imageURL, cornerRadius: 14)
                .aspectRatio(0.68, contentMode: .fit)
                .shadow(
                    color: .black.opacity(isHovering ? 0.18 : 0.10),
                    radius: isHovering ? 14 : 8,
                    x: 0,
                    y: isHovering ? 8 : 4
                )

            Text(title)
                .font(variant == .compact ? YomuhonTypography.captionMedium : YomuhonTypography.headline)
                .foregroundColor(theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let metadata {
                Text(metadata)
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
            }

            if let progress, progress > 0 {
                YomuhonProgressBar(value: progress)
                    .padding(.top, 2)
            }
        }
        .contentShape(Rectangle())
        .scaleEffect(isHovering ? 1.012 : 1.0)
        .animation(.easeOut(duration: 0.18), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct YomuhonContinueReadingCard: View {
    let title: String
    let currentChapter: String
    let imageURL: URL?
    let progress: Double
    let openAction: () -> Void
    let continueAction: () -> Void

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        Button(action: continueAction) {
            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                CoverView(title: title, imageURL: imageURL, cornerRadius: 14)
                    .aspectRatio(0.68, contentMode: .fit)
                    .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)

                Text(title)
                    .font(YomuhonTypography.headline)
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(2)

                Text(currentChapter)
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)

                if progress > 0 {
                    YomuhonProgressBar(value: progress)
                }
            }
        }
        .buttonStyle(YomuhonPressableButtonStyle(theme: theme))
        .contextMenu {
            Button(action: openAction) {
                Label("detail.viewDetails", systemImage: "info.circle")
            }
        }
    }
}

struct YomuhonProgressBar: View {
    let value: Double

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(value, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.separator.opacity(0.55))

                Capsule()
                    .fill(theme.accent.opacity(0.9))
                    .frame(width: max(0, proxy.size.width * clamped))
            }
        }
        .frame(height: 2)
    }
}

struct YomuhonMetadataItem: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let value: String

    init(id: String, title: LocalizedStringKey, value: String) {
        self.id = id
        self.title = title
        self.value = value
    }
}

struct YomuhonMetadataBlock: View {
    let items: [YomuhonMetadataItem]

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: YomuhonSpacing.large) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.value)
                        .font(YomuhonTypography.headline)
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)

                    Text(item.title)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Compact pill overlay used on cover posters/thumbnails to show the
/// available reading language(s), e.g. "EN" or "EN +2". Styled to match
/// the existing dark circular badges (delete/status) used on posters.
struct YomuhonLanguageBadge: View {
    let label: String
    var isCompact: Bool = false

    var body: some View {
        Text(label)
            .font(isCompact ? YomuhonTypography.badgeCompact : YomuhonTypography.badge)
            .foregroundColor(Color.white.opacity(0.94))
            .lineLimit(1)
            .padding(.horizontal, isCompact ? 5 : 7)
            .padding(.vertical, isCompact ? 2.5 : 4)
            .background(Color.black.opacity(0.62))
            .clipShape(Capsule())
    }
}

struct YomuhonTag: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var isSelected = false

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .font(YomuhonTypography.captionMedium)
        .foregroundColor(isSelected ? theme.textPrimary : theme.textSecondary)
        .padding(.horizontal, YomuhonSpacing.medium)
        .padding(.vertical, 6)
        .background(isSelected ? theme.secondaryBackground.opacity(0.78) : theme.card.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
