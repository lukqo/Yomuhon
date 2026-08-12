//
//  LibraryView.swift
//  Yomuhon
//

import SwiftUI

struct LibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel
    var showsSidebar = true
    var onFindManga: (() -> Void)? = nil
    var onOpenMangaDetail: ((MangaDetailViewModel) -> Void)? = nil
    let compositionRoot: PresentationCompositionRoot

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: YomuhonSpacing.extraLarge) {
                    header(width: proxy.size.width)

                    if proxy.size.width < 720 {
                        categoryBar(width: proxy.size.width)
                    }

                    if !viewModel.hasAnyVisibleContent {
                        emptyState(width: proxy.size.width)
                    } else if isSearchingLibrary {
                        libraryGrid(
                            width: proxy.size.width,
                            title: NSLocalizedString("library.searchResults", comment: "")
                        )
                    } else {
                        categoryContent(width: proxy.size.width)
                    }
                }
                .padding(.horizontal, contentPadding(for: proxy.size.width))
                .padding(.top, proxy.size.width > 760 ? YomuhonSpacing.extraLarge : YomuhonSpacing.large)
                .padding(.bottom, YomuhonSpacing.grand)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(theme.background)
        .navigationTitle("Yomuhon")
        .onAppear { viewModel.loadLibrary() }
        .animation(theme.animation, value: viewModel.visibleMangas)
        .animation(theme.animation, value: viewModel.selectedCategory)
    }

    @ViewBuilder
    private func categoryContent(width: CGFloat) -> some View {
        switch viewModel.selectedCategory {
        case .all:
            overviewContent(width: width)
        case .reading:
            focusedCollection(
                width: width,
                icon: LibraryCategory.reading.iconName,
                title: NSLocalizedString("library.reading.summary.title", comment: ""),
                message: NSLocalizedString("library.reading.summary.message", comment: ""),
                primaryValue: "\(viewModel.readingMangas.count)",
                primaryLabel: NSLocalizedString("library.metric.activeTitles", comment: ""),
                secondaryValue: "\(Int((viewModel.averageReadingProgress * 100).rounded()))%",
                secondaryLabel: NSLocalizedString("library.metric.averageProgress", comment: ""),
                collectionTitle: NSLocalizedString("library.reading.collection", comment: "")
            )
        case .completed:
            focusedCollection(
                width: width,
                icon: LibraryCategory.completed.iconName,
                title: NSLocalizedString("library.completed.summary.title", comment: ""),
                message: NSLocalizedString("library.completed.summary.message", comment: ""),
                primaryValue: "\(viewModel.completedMangas.count)",
                primaryLabel: NSLocalizedString("library.metric.finishedTitles", comment: ""),
                secondaryValue: "\(viewModel.completedOfflineCount)",
                secondaryLabel: NSLocalizedString("library.metric.offlineTitles", comment: ""),
                collectionTitle: NSLocalizedString("library.completed.collection", comment: "")
            )
        case .planToRead:
            focusedCollection(
                width: width,
                icon: LibraryCategory.planToRead.iconName,
                title: NSLocalizedString("library.plan.summary.title", comment: ""),
                message: NSLocalizedString("library.plan.summary.message", comment: ""),
                primaryValue: "\(viewModel.planToReadMangas.count)",
                primaryLabel: NSLocalizedString("library.metric.queuedTitles", comment: ""),
                secondaryValue: "\(viewModel.planToReadChapterCount)",
                secondaryLabel: NSLocalizedString("library.metric.knownChapters", comment: ""),
                collectionTitle: NSLocalizedString("library.plan.collection", comment: "")
            )
        }
    }

    @ViewBuilder
    private func overviewContent(width: CGFloat) -> some View {
        if let manga = continueReadingMangas.first {
            heroSection(manga: manga, width: width)
        }

        if continueReadingMangas.count > 1 {
            continueRail(width: width)
        }

        if !downloadedMangas.isEmpty {
            downloadedRail(width: width)
        }

        libraryGrid(
            width: width,
            title: NSLocalizedString("library.yourLibrary", comment: "")
        )
    }

    private func focusedCollection(
        width: CGFloat,
        icon: String,
        title: String,
        message: String,
        primaryValue: String,
        primaryLabel: String,
        secondaryValue: String,
        secondaryLabel: String,
        collectionTitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.extraLarge) {
            LibraryCollectionSummaryCard(
                icon: icon,
                title: title,
                message: message,
                primaryValue: primaryValue,
                primaryLabel: primaryLabel,
                secondaryValue: secondaryValue,
                secondaryLabel: secondaryLabel,
                isCompact: width < 720
            )

            libraryGrid(width: width, title: collectionTitle)
        }
    }

    @ViewBuilder
    private func header(width: CGFloat) -> some View {
        if width < 720 {
            VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
                titleBlock

                YomuhonNativeSearchField(
                    text: $viewModel.searchText,
                    placeholder: "library.search.placeholder",
                    maxWidth: nil
                )
            }
        } else {
            HStack(alignment: .top, spacing: YomuhonSpacing.extraLarge) {
                titleBlock

                Spacer(minLength: YomuhonSpacing.extraLarge)

                VStack(alignment: .trailing, spacing: YomuhonSpacing.small) {
                    YomuhonNativeSearchField(
                        text: $viewModel.searchText,
                        placeholder: "library.search.placeholder",
                        maxWidth: width > 1100 ? 420 : 340
                    )

                    Text(categoryContextLabel)
                        .font(YomuhonTypography.captionMedium)
                        .foregroundColor(theme.textSecondary)
                }
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
            Text(activeTitle)
                .font(YomuhonTypography.largeTitle)
                .foregroundColor(theme.textPrimary)
                .lineLimit(2)

            Text(activeSubtitle)
                .font(YomuhonTypography.body)
                .foregroundColor(theme.textSecondary)
                .lineLimit(2)
        }
    }

    private func categoryBar(width: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: YomuhonSpacing.small) {
                ForEach(LibraryCategory.allCases) { category in
                    Button {
                        withAnimation(theme.animation) {
                            viewModel.selectedCategory = category
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: category.iconName)
                                .font(.system(size: YomuhonIconSize.chip, weight: .medium))

                            Text(category.title)
                                .font(YomuhonTypography.captionMedium)

                            Text("\(viewModel.categoryCount(category))")
                                .font(YomuhonTypography.badge)
                                .foregroundColor(
                                    viewModel.selectedCategory == category
                                        ? selectedPillTextColor.opacity(0.72)
                                        : theme.textSecondary.opacity(0.72)
                                )
                        }
                        .foregroundColor(viewModel.selectedCategory == category ? selectedPillTextColor : theme.textSecondary)
                        .padding(.horizontal, YomuhonSpacing.medium)
                        .padding(.vertical, 9)
                        .background(viewModel.selectedCategory == category ? theme.accent : theme.secondaryBackground.opacity(0.72))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: width > 980 ? 820 : .infinity, alignment: .leading)
    }

    private func heroSection(manga: Manga, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            Text("library.continueReading")
                .font(YomuhonTypography.title)
                .foregroundColor(theme.textPrimary)

            mangaDetailTrigger(for: manga) {
                LibraryHeroCard(
                    manga: manga,
                    chapterTitle: chapterTitle(for: manga),
                    synopsis: manga.displaySynopsis,
                    progress: viewModel.readingProgress(for: manga),
                    isCompact: width < 820,
                    onDelete: { viewModel.deleteManga(manga) }
                )
            }
        }
    }

    private func continueRail(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text("library.recentActivity")
                    .font(YomuhonTypography.title)
                    .foregroundColor(theme.textPrimary)

                Spacer()

                Text(resultCountText(continueReadingMangas.count))
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: YomuhonSpacing.large) {
                    ForEach(continueReadingMangas.dropFirst()) { manga in
                        mangaDetailTrigger(for: manga) {
                            LibraryRailPoster(
                                manga: manga,
                                chapterTitle: chapterTitle(for: manga),
                                progress: viewModel.readingProgress(for: manga)
                            )
                            .contextMenu {
                                Button(role: .destructive) {
                                    viewModel.deleteManga(manga)
                                } label: {
                                    Label("library.removeManga", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, YomuhonSpacing.small)
            }
        }
    }

    private func downloadedRail(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text("library.downloadedOffline")
                    .font(YomuhonTypography.title)
                    .foregroundColor(theme.textPrimary)

                Spacer()

                Text(resultCountText(downloadedMangas.count))
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: YomuhonSpacing.large) {
                    ForEach(downloadedMangas) { manga in
                        mangaDetailTrigger(for: manga) {
                            LibraryRailPoster(
                                manga: manga,
                                chapterTitle: offlineSubtitle(for: manga),
                                progress: viewModel.readingProgress(for: manga)
                            )
                            .contextMenu {
                                Button(role: .destructive) {
                                    viewModel.deleteManga(manga)
                                } label: {
                                    Label("library.removeManga", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, YomuhonSpacing.small)
            }
        }
    }

    private func libraryGrid(width: CGFloat, title: String) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(YomuhonTypography.title)
                    .foregroundColor(theme.textPrimary)

                Spacer()

                Text(resultCountText(viewModel.visibleMangas.count))
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
            }

            LazyVGrid(columns: gridColumns(for: width), alignment: .leading, spacing: YomuhonSpacing.large) {
                ForEach(viewModel.visibleMangas) { manga in
                    mangaDetailTrigger(for: manga) {
                        LibraryPoster(
                            manga: manga,
                            chapterTitle: chapterTitle(for: manga),
                            progress: viewModel.readingProgress(for: manga),
                            status: viewModel.progressByMangaID[manga.id]?.status,
                            onDelete: { viewModel.deleteManga(manga) }
                        )
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.deleteManga(manga)
                            } label: {
                                Label("library.removeManga", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private func emptyState(width: CGFloat) -> some View {
        VStack(spacing: YomuhonSpacing.large) {
            Image(systemName: isSearchingLibrary ? "magnifyingglass" : viewModel.selectedCategory.iconName)
                .font(.system(size: YomuhonIconSize.emptyState, weight: .light))
                .foregroundColor(theme.textSecondary.opacity(0.44))

            VStack(spacing: YomuhonSpacing.small) {
                Text(emptyTitle)
                    .font(YomuhonTypography.title)
                    .foregroundColor(theme.textPrimary)

                Text(emptyMessage)
                    .font(YomuhonTypography.body)
                    .foregroundColor(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            if !isSearchingLibrary, let onFindManga {
                Button(action: onFindManga) {
                    Text("library.findManga")
                }
                .buttonStyle(YomuhonPrimaryButtonStyle(theme: theme))
            }
        }
        .frame(maxWidth: .infinity, minHeight: width > 760 ? 460 : 360)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.card.opacity(theme.id == .ink ? 0.45 : 1.0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.6), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func mangaDetailTrigger<Content: View>(
        for manga: Manga,
        @ViewBuilder content: () -> Content
    ) -> some View {
        MangaDetailNavigationTrigger(
            compositionRoot: compositionRoot,
            manga: manga,
            progress: viewModel.progressByMangaID[manga.id],
            onOpenMangaDetail: onOpenMangaDetail,
            content: content
        )
    }

    private func contentPadding(for width: CGFloat) -> CGFloat {
        if width >= 1180 {
            return YomuhonSpacing.grand
        }

        return width >= 720 ? YomuhonSpacing.extraLarge : YomuhonSpacing.large
    }

    private func gridColumns(for width: CGFloat) -> [GridItem] {
        let minWidth: CGFloat
        if width >= 1180 {
            minWidth = 148
        } else if width >= 820 {
            minWidth = 136
        } else {
            minWidth = 118
        }

        return [GridItem(.adaptive(minimum: minWidth, maximum: minWidth + 22), spacing: YomuhonSpacing.large)]
    }

    private var selectedPillTextColor: Color {
        theme.id == .ink ? theme.textPrimary : theme.background
    }

    private var isSearchingLibrary: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var activeTitle: String {
        viewModel.selectedCategory == .all
            ? NSLocalizedString("library.title", comment: "")
            : viewModel.selectedCategory.title
    }

    private var activeSubtitle: String {
        if isSearchingLibrary {
            return NSLocalizedString("library.search.subtitle", comment: "")
        }

        switch viewModel.selectedCategory {
        case .all:
            return String.localizedStringWithFormat(
                NSLocalizedString("library.summary.format", comment: ""),
                viewModel.allLibraryMangas.count,
                viewModel.historyCount
            )
        case .reading:
            return NSLocalizedString("library.reading.subtitle", comment: "")
        case .completed:
            return NSLocalizedString("library.completed.subtitle", comment: "")
        case .planToRead:
            return NSLocalizedString("library.plan.subtitle", comment: "")
        }
    }

    private var categoryContextLabel: String {
        switch viewModel.selectedCategory {
        case .all:
            return NSLocalizedString("library.overview.context", comment: "")
        case .reading:
            return NSLocalizedString("library.reading.context", comment: "")
        case .completed:
            return NSLocalizedString("library.completed.context", comment: "")
        case .planToRead:
            return NSLocalizedString("library.plan.context", comment: "")
        }
    }

    private var emptyTitle: String {
        if isSearchingLibrary {
            return NSLocalizedString("library.noResults.title", comment: "")
        }

        switch viewModel.selectedCategory {
        case .all:
            return NSLocalizedString("library.empty.title", comment: "")
        case .reading:
            return NSLocalizedString("library.reading.empty.title", comment: "")
        case .completed:
            return NSLocalizedString("library.completed.empty.title", comment: "")
        case .planToRead:
            return NSLocalizedString("library.plan.empty.title", comment: "")
        }
    }

    private var emptyMessage: String {
        if isSearchingLibrary {
            return NSLocalizedString("library.noResults.message", comment: "")
        }

        switch viewModel.selectedCategory {
        case .all:
            return NSLocalizedString("library.empty.message", comment: "")
        case .reading:
            return NSLocalizedString("library.reading.empty.message", comment: "")
        case .completed:
            return NSLocalizedString("library.completed.empty.message", comment: "")
        case .planToRead:
            return NSLocalizedString("library.plan.empty.message", comment: "")
        }
    }

    private var continueReadingMangas: [Manga] {
        Array(viewModel.readingMangas.prefix(8))
    }

    private var downloadedMangas: [Manga] {
        Array(viewModel.downloadedMangas.prefix(8))
    }

    private func resultCountText(_ count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("search.results.summary", comment: ""),
            count
        )
    }

    private func offlineSubtitle(for manga: Manga) -> String {
        let count = manga.chapters.filter(\.isDownloaded).count

        return String.localizedStringWithFormat(
            NSLocalizedString("library.downloadedChapterCount", comment: ""),
            count
        )
    }

    private func chapterTitle(for manga: Manga) -> String {
        guard let progress = viewModel.progressByMangaID[manga.id],
              let chapter = manga.chapters.first(where: { $0.id == progress.currentChapterID }) ?? manga.chapters.first else {
            return manga.chapters.first?.displayTitle ?? ""
        }

        return chapter.displayTitle
    }
}

private struct LibraryCollectionSummaryCard: View {
    let icon: String
    let title: String
    let message: String
    let primaryValue: String
    let primaryLabel: String
    let secondaryValue: String
    let secondaryLabel: String
    let isCompact: Bool

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        Group {
            if isCompact {
                compactContent
            } else {
                regularContent
            }
        }
        .padding(YomuhonSpacing.large)
        .background(theme.card.opacity(theme.id == .ink ? 0.58 : 1.0))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.62), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var regularContent: some View {
        HStack(alignment: .center, spacing: YomuhonSpacing.extraLarge) {
            iconView
            copyView
            Spacer(minLength: YomuhonSpacing.large)
            metricsView
        }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.large) {
            HStack(alignment: .top, spacing: YomuhonSpacing.medium) {
                iconView
                copyView
            }

            metricsView
        }
    }

    private var iconView: some View {
        Image(systemName: icon)
            .font(.system(size: YomuhonIconSize.stat, weight: .medium))
            .foregroundColor(theme.accent)
            .frame(width: 58, height: 58)
            .background(theme.secondaryBackground.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var copyView: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
            Text(title)
                .font(YomuhonTypography.title)
                .foregroundColor(theme.textPrimary)

            Text(message)
                .font(YomuhonTypography.body)
                .foregroundColor(theme.textSecondary)
                .lineLimit(3)
        }
    }

    private var metricsView: some View {
        HStack(spacing: YomuhonSpacing.extraLarge) {
            metric(value: primaryValue, label: primaryLabel)
            metric(value: secondaryValue, label: secondaryLabel)
        }
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(YomuhonTypography.statValue)
                .foregroundColor(theme.textPrimary)

            Text(label)
                .font(YomuhonTypography.caption)
                .foregroundColor(theme.textSecondary)
                .lineLimit(2)
        }
        .frame(minWidth: 88, alignment: .leading)
    }
}

private struct LibraryHeroCard: View {
    let manga: Manga
    let chapterTitle: String
    let synopsis: String
    let progress: Double
    let isCompact: Bool
    let onDelete: () -> Void

    @Environment(\.yomuhonTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        Group {
            if isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .padding(isCompact ? YomuhonSpacing.medium : YomuhonSpacing.large)
        .background(theme.card.opacity(theme.id == .ink ? 0.58 : 1.0))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.62), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("library.removeManga", systemImage: "trash")
            }
        }
        .yomuhonHoverLift(isHovering: isHovering, theme: theme, scale: 1.002, shadowRadius: 14, shadowY: 8)
        .onHover { isHovering = $0 }
    }

    private var readableSynopsisColor: Color {
        theme.id == .ink ? theme.textSecondary : theme.textPrimary.opacity(0.78)
    }

    private var regularLayout: some View {
        HStack(alignment: .center, spacing: YomuhonSpacing.large) {
            CoverView(title: manga.title, imageURL: manga.coverURL, cornerRadius: 18)
                .frame(width: 150, height: 218)
                .clipped()
                .shadow(color: theme.shadow.opacity(0.56), radius: 12, x: 0, y: 7)
                .layoutPriority(0)

            VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
                VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                    Text(manga.title)
                        .font(manga.title.count > 58 ? YomuhonTypography.headline : .title.weight(.semibold))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if !chapterTitle.isEmpty {
                        Text(chapterTitle)
                            .font(YomuhonTypography.calloutMedium)
                            .foregroundColor(theme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Text(synopsis)
                    .font(YomuhonTypography.body)
                    .foregroundColor(readableSynopsisColor)
                    .lineSpacing(4)
                    .lineLimit(3)
                    .frame(maxWidth: 560, alignment: .leading)

                HStack(spacing: YomuhonSpacing.medium) {
                    Text("detail.continueReading")
                        .font(YomuhonTypography.calloutSemibold)
                        .foregroundColor(continueButtonForeground)
                        .padding(.horizontal, YomuhonSpacing.large)
                        .padding(.vertical, 10)
                        .background(continueButtonBackground)
                        .overlay(
                            Capsule()
                                .strokeBorder(theme.separator.opacity(theme.id == .ink ? 0.7 : 0), lineWidth: theme.id == .ink ? 1 : 0)
                        )
                        .clipShape(Capsule())

                    progressLabel
                }

                YomuhonProgressBar(value: progress)
                    .frame(maxWidth: 360)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)
        }
    }

    private var compactLayout: some View {
        HStack(spacing: YomuhonSpacing.medium) {
            CoverView(title: manga.title, imageURL: manga.coverURL, cornerRadius: 16)
                .frame(width: 96, height: 140)
                .clipped()
                .shadow(color: theme.shadow.opacity(0.56), radius: 9, x: 0, y: 5)

            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                Text(manga.title)
                    .font(YomuhonTypography.headline)
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(2)

                if !chapterTitle.isEmpty {
                    Text(chapterTitle)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                }

                progressLabel

                YomuhonProgressBar(value: progress)
            }

            Spacer(minLength: 0)
        }
    }

    private var continueButtonForeground: Color {
        theme.id == .ink ? Color.black : theme.background
    }

    private var continueButtonBackground: Color {
        theme.id == .ink ? theme.textPrimary : theme.accent
    }

    private var progressLabel: some View {
        Text(String.localizedStringWithFormat(NSLocalizedString("common.percentFormat", comment: ""), Int(progress * 100)))
            .font(YomuhonTypography.captionMedium)
            .foregroundColor(theme.textSecondary)
    }
}

private struct LibraryRailPoster: View {
    let manga: Manga
    let chapterTitle: String
    let progress: Double

    @Environment(\.yomuhonTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
            CoverView(title: manga.title, imageURL: manga.coverURL, cornerRadius: 14)
                .frame(width: 118, height: 172)
                .shadow(color: theme.shadow.opacity(isHovering ? 0.75 : 0.45), radius: isHovering ? 12 : 7, x: 0, y: isHovering ? 7 : 4)
                .overlay(alignment: .bottomTrailing) {
                    if let languageBadgeLabel = manga.languageBadgeLabel {
                        YomuhonLanguageBadge(label: languageBadgeLabel)
                            .padding(6)
                    }
                }

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

            if progress > 0 {
                YomuhonProgressBar(value: progress)
                    .frame(width: 118)
            }
        }
        .contentShape(Rectangle())
        .scaleEffect(isHovering ? 1.006 : 1)
        .animation(theme.animation, value: isHovering)
        .onHover { isHovering = $0 }
    }
}

private struct LibraryPoster: View {
    let manga: Manga
    let chapterTitle: String
    let progress: Double
    let status: ReadingStatus?
    let onDelete: () -> Void

    @Environment(\.yomuhonTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
            CoverView(title: manga.title, imageURL: manga.coverURL, cornerRadius: 14)
                .aspectRatio(0.68, contentMode: .fit)
                .shadow(color: theme.shadow.opacity(isHovering ? 0.75 : 0.42), radius: isHovering ? 12 : 7, x: 0, y: isHovering ? 7 : 4)
                .overlay(alignment: .topTrailing) {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: YomuhonIconSize.overlay, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.92))
                            .frame(width: 26, height: 26)
                            .background(Color.black.opacity(0.62))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(7)
                    .opacity(isHovering ? 1 : 0)
                }
                .overlay(alignment: .bottomLeading) {
                    if let status {
                        Image(systemName: statusIcon(status))
                            .font(.system(size: YomuhonIconSize.overlay, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.94))
                            .frame(width: 27, height: 27)
                            .background(Color.black.opacity(0.64))
                            .clipShape(Circle())
                            .padding(7)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let languageBadgeLabel = manga.languageBadgeLabel {
                        YomuhonLanguageBadge(label: languageBadgeLabel)
                            .padding(7)
                    }
                }

            Text(manga.title)
                .font(YomuhonTypography.captionMedium)
                .foregroundColor(theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !chapterTitle.isEmpty {
                Text(chapterTitle)
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
            }

            if progress > 0 {
                YomuhonProgressBar(value: progress)
                    .padding(.top, 2)
            }
        }
        .contentShape(Rectangle())
        .scaleEffect(isHovering ? 1.006 : 1)
        .animation(theme.animation, value: isHovering)
        .onHover { isHovering = $0 }
    }

    private func statusIcon(_ status: ReadingStatus) -> String {
        switch status {
        case .reading:
            return "book"
        case .completed:
            return "checkmark"
        case .planToRead:
            return "bookmark.fill"
        }
    }
}
