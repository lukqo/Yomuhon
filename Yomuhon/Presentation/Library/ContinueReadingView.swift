//
//  ContinueReadingView.swift
//  Yomuhon
//

import SwiftUI

struct ContinueReadingView: View {
    @ObservedObject var viewModel: LibraryViewModel
    let compositionRoot: PresentationCompositionRoot

    @Environment(\.yomuhonTheme) private var theme
    @State private var isGrid = true

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: YomuhonSpacing.extraLarge) {
                    header

                    if inProgressMangas.isEmpty {
                        emptyState
                    } else {
                        continueList

                        if !recentlyUpdatedMangas.isEmpty {
                            recentlyUpdated
                        }
                    }
                }
                .padding(.horizontal, proxy.size.width > 1000 ? YomuhonSpacing.grand : YomuhonSpacing.extraLarge)
                .padding(.top, YomuhonSpacing.extraLarge)
                .padding(.bottom, YomuhonSpacing.grand)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(theme.background)
        .navigationTitle("Yomuhon")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                Text("continue.title")
                    .font(YomuhonTypography.largeTitle)
                    .foregroundColor(theme.textPrimary)

                Text("continue.subtitle")
                    .font(YomuhonTypography.body)
                    .foregroundColor(theme.textSecondary)
            }

            Spacer()

            HStack(spacing: YomuhonSpacing.small) {
                ToggleIconButton(systemName: "square.grid.2x2.fill", isSelected: isGrid) { isGrid = true }
                ToggleIconButton(systemName: "list.bullet", isSelected: !isGrid) { isGrid = false }
            }
        }
    }

    private var continueList: some View {
        LazyVStack(spacing: YomuhonSpacing.medium) {
            ForEach(inProgressMangas) { manga in
                NavigationLink {
                    detailDestination(for: manga)
                } label: {
                    ContinueRow(
                        manga: manga,
                        chapterTitle: chapterTitle(for: manga),
                        lastRead: lastReadLabel(for: manga),
                        progress: readingProgress(for: manga)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 820)
    }

    private var recentlyUpdated: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            HStack {
                Text("continue.recentlyUpdated")
                    .font(YomuhonTypography.title)
                    .foregroundColor(theme.textPrimary)

                Spacer()

                Text("continue.seeAll")
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: YomuhonSpacing.medium) {
                    ForEach(recentlyUpdatedMangas) { manga in
                        NavigationLink {
                            detailDestination(for: manga)
                        } label: {
                            RecentUpdateCard(manga: manga, chapterTitle: chapterTitle(for: manga))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, YomuhonSpacing.small)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: YomuhonSpacing.medium) {
            Image(systemName: "clock")
                .font(.system(size: 46, weight: .light))
                .foregroundColor(theme.textSecondary.opacity(0.42))

            Text("continue.empty.title")
                .font(YomuhonTypography.title)
                .foregroundColor(theme.textPrimary)

            Text("continue.empty.message")
                .font(YomuhonTypography.body)
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private func detailDestination(for manga: Manga) -> some View {
        MangaDetailView(
            viewModel: compositionRoot.makeMangaDetailViewModel(
                manga: manga,
                progress: viewModel.progressByMangaID[manga.id]
            )
        )
    }

    private var inProgressMangas: [Manga] {
        viewModel.mangas
            .filter { viewModel.progressByMangaID[$0.id]?.status == .reading }
            .sorted { recentDate(for: $0) > recentDate(for: $1) }
    }

    private var recentlyUpdatedMangas: [Manga] {
        Array(viewModel.mangas.sorted { recentDate(for: $0) > recentDate(for: $1) }.prefix(8))
    }

    private func recentDate(for manga: Manga) -> Date {
        viewModel.progressByMangaID[manga.id]?.lastReadAt ?? .distantPast
    }

    private func chapterTitle(for manga: Manga) -> String {
        guard let progress = viewModel.progressByMangaID[manga.id],
              let chapter = manga.chapters.first(where: { $0.id == progress.currentChapterID }) ?? manga.chapters.first else {
            return ""
        }

        return chapter.displayTitle
    }

    private func lastReadLabel(for manga: Manga) -> String {
        guard let date = viewModel.progressByMangaID[manga.id]?.lastReadAt else {
            return ""
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func readingProgress(for manga: Manga) -> Double {
        guard let progress = viewModel.progressByMangaID[manga.id],
              let chapterIndex = manga.chapters.firstIndex(where: { $0.id == progress.currentChapterID }),
              !manga.chapters.isEmpty else {
            return 0
        }

        return Double(chapterIndex + 1) / Double(manga.chapters.count)
    }
}

private struct ContinueRow: View {
    let manga: Manga
    let chapterTitle: String
    let lastRead: String
    let progress: Double

    @Environment(\.yomuhonTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: YomuhonSpacing.medium) {
            CoverView(title: manga.title, imageURL: manga.coverURL, cornerRadius: 12)
                .frame(width: 72, height: 96)

            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                Text(manga.title)
                    .font(YomuhonTypography.headline)
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)

                if !chapterTitle.isEmpty {
                    Text(chapterTitle)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                }

                if !lastRead.isEmpty {
                    Text(lastRead)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary.opacity(0.72))
                        .lineLimit(1)
                }

                HStack(spacing: YomuhonSpacing.small) {
                    YomuhonProgressBar(value: progress)
                    Text(String.localizedStringWithFormat(NSLocalizedString("common.percentFormat", comment: ""), Int(progress * 100)))
                        .font(YomuhonTypography.captionMedium)
                        .foregroundColor(theme.textSecondary)
                }
                .padding(.top, 2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(YomuhonTypography.captionMedium)
                .foregroundColor(theme.textSecondary.opacity(0.72))
        }
        .padding(YomuhonSpacing.medium)
        .background(theme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.72), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .yomuhonHoverLift(isHovering: isHovering, theme: theme, scale: 1.002, shadowRadius: 8, shadowY: 4)
        .onHover { isHovering = $0 }
    }
}

private struct RecentUpdateCard: View {
    let manga: Manga
    let chapterTitle: String

    @Environment(\.yomuhonTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
            CoverView(title: manga.title, imageURL: manga.coverURL, cornerRadius: 12)
                .frame(width: 118, height: 168)
                .shadow(color: theme.shadow.opacity(isHovering ? 0.8 : 0.4), radius: isHovering ? 10 : 6, x: 0, y: isHovering ? 6 : 3)

            Text(manga.title)
                .font(YomuhonTypography.captionMedium)
                .foregroundColor(theme.textPrimary)
                .lineLimit(2)
                .frame(width: 118, alignment: .leading)

            if !chapterTitle.isEmpty {
                Text(chapterTitle)
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
                    .frame(width: 118, alignment: .leading)
            }
        }
        .scaleEffect(isHovering ? 1.006 : 1)
        .animation(theme.animation, value: isHovering)
        .onHover { isHovering = $0 }
    }
}

private struct ToggleIconButton: View {
    let systemName: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSelected ? theme.background : theme.textPrimary)
                .frame(width: 36, height: 36)
                .background(isSelected ? theme.textPrimary : theme.secondaryBackground.opacity(0.72))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
