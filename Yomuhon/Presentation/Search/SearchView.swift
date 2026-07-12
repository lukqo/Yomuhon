//
//  SearchView.swift
//  Yomuhon
//

import Combine
import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    private let compositionRoot: PresentationCompositionRoot
    private let onOpenMangaDetail: ((MangaDetailViewModel) -> Void)?

    @Environment(\.yomuhonTheme) private var theme
    @State private var pendingSearch: DispatchWorkItem?

    init(
        viewModel: SearchViewModel,
        compositionRoot: PresentationCompositionRoot = .live,
        onOpenMangaDetail: ((MangaDetailViewModel) -> Void)? = nil
    ) {
        self.compositionRoot = compositionRoot
        self.onOpenMangaDetail = onOpenMangaDetail
        _viewModel = StateObject(wrappedValue: viewModel)
    }


    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: YomuhonSpacing.extraLarge) {
                    searchHero(width: proxy.size.width)
                    resultsContent(width: proxy.size.width)
                }
                .padding(.horizontal, contentPadding(for: proxy.size.width))
                .padding(.top, proxy.size.width > 760 ? YomuhonSpacing.extraLarge : YomuhonSpacing.large)
                .padding(.bottom, YomuhonSpacing.grand)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(theme.background)
        .navigationTitle("Yomuhon")
        .onChange(of: viewModel.query) { _ in scheduleSearch() }
        .onAppear {
            viewModel.refreshSourceAvailability()
            viewModel.loadDiscovery()
        }
        .onDisappear {
            pendingSearch?.cancel()
            viewModel.cancelSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .yomuhonSourceCatalogDidChange)) { _ in
            DispatchQueue.main.async {
                viewModel.reloadDiscoveryForSourceCatalogChange()
            }
        }
        .animation(theme.animation, value: viewModel.results)
        .animation(theme.animation, value: viewModel.isSearching)
        .animation(theme.animation, value: viewModel.query)
    }

    @ViewBuilder
    private func searchHero(width: CGFloat) -> some View {
        if width < 760 {
            VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
                heroCopy
                YomuhonNativeSearchField(text: $viewModel.query, placeholder: "search.placeholder", maxWidth: nil)
            }
        } else {
            HStack(alignment: .top, spacing: YomuhonSpacing.grand) {
                heroCopy
                    .frame(maxWidth: 440, alignment: .leading)

                Spacer(minLength: YomuhonSpacing.large)

                VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
                    YomuhonNativeSearchField(text: $viewModel.query, placeholder: "search.placeholder", maxWidth: 460)
                    }
                .frame(maxWidth: 520, alignment: .leading)
            }
        }
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
            Text("search.title")
                .font(YomuhonTypography.largeTitle)
                .foregroundColor(theme.textPrimary)

            Text("search.subtitle")
                .font(YomuhonTypography.body)
                .foregroundColor(theme.textSecondary)
                .lineLimit(3)
        }
    }

    @ViewBuilder
    private func resultsContent(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text(resultsTitle)
                    .font(YomuhonTypography.title)
                    .foregroundColor(theme.textPrimary)

                Spacer()

                if viewModel.hasSearched, !viewModel.activeReadableGroups.isEmpty {
                    Text(resultsSummary)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                }
            }

            if viewModel.hasSearched, !viewModel.results.isEmpty {
                searchResultFilters
            }

            if let progressMessage = viewModel.searchProgressMessage,
               !viewModel.results.isEmpty {
                HStack(spacing: YomuhonSpacing.small) {
                    ProgressView()
                        .controlSize(.small)

                    Text(progressMessage)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                }
                .transition(.opacity)
            }

            if !viewModel.hasEnabledSources {
                centeredState(
                    icon: "books.vertical",
                    title: "search.noSources.title",
                    message: "search.noSources.message",
                    width: width
                )
            } else if viewModel.trimmedQuery.isEmpty && !viewModel.hasSearched {
                discoveryState(width: width)
            } else if viewModel.isSearching && viewModel.results.isEmpty {
                searchSkeletonList(width: width)
            } else if let errorMessage = viewModel.errorMessage {
                centeredState(
                    icon: "exclamationmark.triangle",
                    title: "search.error.title",
                    message: LocalizedStringKey(errorMessage),
                    width: width
                )
            } else if viewModel.hasSearched && viewModel.activeReadableGroups.isEmpty && !viewModel.hasCatalogOnlyResults {
                centeredState(
                    icon: "doc.text.magnifyingglass",
                    title: "search.noResults.title",
                    message: "search.noResults.message",
                    width: width
                )
            } else {
                VStack(alignment: .leading, spacing: YomuhonSpacing.extraLarge) {
                    if !viewModel.activeReadableGroups.isEmpty {
                        resultsList(
                            title: "search.availableToRead",
                            message: "search.availableToRead.message",
                            groups: viewModel.activeReadableGroups,
                            width: width,
                            isCatalogOnly: false
                        )
                    }

                    if viewModel.hasCatalogOnlyResults {
                        resultsList(
                            title: "search.catalogMatches",
                            message: "search.catalogMatches.message",
                            groups: viewModel.catalogOnlyGroupedResults,
                            width: width,
                            isCatalogOnly: true
                        )
                    }
                }
            }
        }
    }

    private func discoveryState(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.large) {
            // Genre capabilities are primary Discover navigation, not a hidden
            // disclosure below the manga shelves.
            if !viewModel.discoveryGenres.isEmpty {
                genreSection(width: width)
            }

            if let genre = viewModel.selectedGenre {
                genreResultsSection(genre: genre, width: width)
            }

            if !viewModel.popularMangas.isEmpty {
                mangaPosterSection(
                    title: "search.popularManga",
                    subtitle: "search.popularManga.subtitle",
                    mangas: viewModel.popularMangas,
                    width: width
                )
            } else if viewModel.isLoadingDiscovery {
                discoveryLoadingSection(width: width)
            } else {
                discoveryUnavailableSection(width: width)
            }
        }
    }

    private func discoveryLoadingSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            VStack(alignment: .leading, spacing: 4) {
                Text("search.popularManga")
                    .font(YomuhonTypography.headline)
                    .foregroundColor(theme.textPrimary)

                Text("search.discovery.loading")
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
            }

            HStack(spacing: YomuhonSpacing.medium) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                        YomuhonSkeletonBlock(cornerRadius: 16)
                            .frame(width: 118, height: 172)

                        YomuhonSkeletonBlock(cornerRadius: 4)
                            .frame(width: 84, height: 10)
                    }
                    .redacted(reason: .placeholder)
                }
            }
        }
        .padding(YomuhonSpacing.large)
        .background(theme.card.opacity(theme.id == .ink ? 0.5 : 1.0))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.62), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func discoveryUnavailableSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
            Label("search.discovery.unavailable", systemImage: "photo.on.rectangle.angled")
                .font(YomuhonTypography.headline)
                .foregroundColor(theme.textPrimary)

            Text("search.discovery.unavailable.message")
                .font(YomuhonTypography.body)
                .foregroundColor(theme.textSecondary)
                .frame(maxWidth: 520, alignment: .leading)
        }
        .padding(YomuhonSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card.opacity(theme.id == .ink ? 0.5 : 1.0))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.62), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func mangaPosterSection(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        mangas: [Manga],
        width: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(YomuhonTypography.headline)
                    .foregroundColor(theme.textPrimary)

                Text(subtitle)
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: YomuhonSpacing.medium) {
                    ForEach(Array(mangas.enumerated()), id: \.offset) { item in
                        let manga = item.element
                        discoveryTrigger(for: manga) {
                            DiscoveryMangaPoster(manga: manga)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(YomuhonSpacing.large)
        .background(theme.card.opacity(theme.id == .ink ? 0.5 : 1.0))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.62), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private func genreResultsSection(genre: SourceDiscoveryGenre, width: CGFloat) -> some View {
        if !viewModel.genreMangas.isEmpty {
            VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(genre.title)
                        .font(YomuhonTypography.headline)
                        .foregroundColor(theme.textPrimary)

                    Text("search.genre.results.subtitle")
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: YomuhonSpacing.medium) {
                        ForEach(Array(viewModel.genreMangas.enumerated()), id: \.offset) { item in
                            let manga = item.element
                            discoveryTrigger(for: manga) {
                                DiscoveryMangaPoster(manga: manga)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(YomuhonSpacing.large)
            .background(theme.card.opacity(theme.id == .ink ? 0.5 : 1.0))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(theme.separator.opacity(0.62), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else if viewModel.isLoadingGenre {
            HStack(spacing: YomuhonSpacing.medium) {
                ProgressView()
                    .controlSize(.small)

                VStack(alignment: .leading, spacing: 3) {
                    Text(genre.title)
                        .font(YomuhonTypography.headline)
                        .foregroundColor(theme.textPrimary)

                    Text("search.genre.loading")
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                }
            }
            .padding(YomuhonSpacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card.opacity(theme.id == .ink ? 0.5 : 1.0))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(theme.separator.opacity(0.62), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                Text(genre.title)
                    .font(YomuhonTypography.headline)
                    .foregroundColor(theme.textPrimary)

                Text("search.genre.unavailable")
                    .font(YomuhonTypography.body)
                    .foregroundColor(theme.textSecondary)
            }
            .padding(YomuhonSpacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card.opacity(theme.id == .ink ? 0.5 : 1.0))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(theme.separator.opacity(0.62), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func genreSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            VStack(alignment: .leading, spacing: 4) {
                Text("search.genre.title")
                    .font(YomuhonTypography.headline)
                    .foregroundColor(theme.textPrimary)

                Text("search.genre.subtitle")
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
            }

            LazyVGrid(columns: genreColumns(for: width), alignment: .leading, spacing: YomuhonSpacing.small) {
                ForEach(viewModel.discoveryGenres) { genre in
                    let isSelected = viewModel.selectedGenre?.id == genre.id
                    Button {
                        viewModel.selectGenre(genre)
                    } label: {
                        Text(genre.title)
                            .font(YomuhonTypography.captionMedium)
                            .foregroundColor(isSelected ? theme.accent : theme.textPrimary)
                            .padding(.horizontal, YomuhonSpacing.medium)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .background(
                                isSelected
                                    ? theme.accent.opacity(0.16)
                                    : theme.secondaryBackground.opacity(0.72)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(YomuhonSpacing.large)
        .background(theme.card.opacity(theme.id == .ink ? 0.5 : 1.0))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.62), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func centeredState(
        icon: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        width: CGFloat
    ) -> some View {
        VStack(spacing: YomuhonSpacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .light))
                .foregroundColor(theme.textSecondary.opacity(0.5))

            Text(title)
                .font(YomuhonTypography.headline)
                .foregroundColor(theme.textPrimary)

            Text(message)
                .font(YomuhonTypography.body)
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, minHeight: width > 760 ? 360 : 280)
        .background(theme.card.opacity(theme.id == .ink ? 0.42 : 1.0))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.58), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func searchSkeletonList(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            VStack(alignment: .leading, spacing: 4) {
                Text("search.searching.title")
                    .font(YomuhonTypography.headline)
                    .foregroundColor(theme.textPrimary)

                Text("search.searching.message")
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
            }

            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { index in
                    SearchResultSkeletonRow(isCompact: width < 720)

                    if index != 4 {
                        Rectangle()
                            .fill(theme.separator.opacity(0.55))
                            .frame(height: 1)
                            .padding(.leading, width < 720 ? 76 : 112)
                    }
                }
            }
            .background(theme.card.opacity(theme.id == .ink ? 0.46 : 1.0))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(theme.separator.opacity(0.58), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var searchResultFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: YomuhonSpacing.small) {
                Button {
                    viewModel.onlyReadableResults.toggle()
                } label: {
                    Label(
                        viewModel.onlyReadableResults ? "search.filter.readableOnly" : "search.filter.allResults",
                        systemImage: viewModel.onlyReadableResults ? "bolt.circle.fill" : "square.grid.2x2"
                    )
                    .font(YomuhonTypography.captionMedium)
                    .padding(.horizontal, YomuhonSpacing.medium)
                    .padding(.vertical, 8)
                    .background(theme.secondaryBackground.opacity(0.72))
                    .foregroundColor(theme.textSecondary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                ForEach(viewModel.availableSearchSourceFilters) { filter in
                    Button {
                        viewModel.selectedSearchSourceID = filter.id
                    } label: {
                        Text(filter.title)
                            .font(YomuhonTypography.captionMedium)
                            .padding(.horizontal, YomuhonSpacing.medium)
                            .padding(.vertical, 8)
                            .background(viewModel.selectedSearchSourceID == filter.id ? theme.accent.opacity(0.16) : theme.secondaryBackground.opacity(0.52))
                            .foregroundColor(viewModel.selectedSearchSourceID == filter.id ? theme.accent : theme.textSecondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func resultsList(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        groups: [MangaSearchGroup],
        width: CGFloat,
        isCatalogOnly: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(YomuhonTypography.headline)
                    .foregroundColor(theme.textPrimary)

                Text(message)
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
            }

            LazyVStack(spacing: 0) {
                ForEach(groups) { group in
                    if let primary = group.primaryManga {
                        resultTrigger(for: group, primary: primary) {
                            SearchResultBookRow(
                                manga: primary,
                                title: group.title,
                                metadata: metadataText(for: group, isCatalogOnly: isCatalogOnly),
                                sourceBreakdown: group.sourceBreakdown,
                                sourceBadges: group.sourceBadges,
                                bestSourceName: group.bestSourceName,
                                isCompact: width < 720,
                                availability: isCatalogOnly ? "search.catalogOnly.badge" : "search.readable.badge"
                            )
                        }

                        if group.id != groups.last?.id {
                            Rectangle()
                                .fill(theme.separator.opacity(0.65))
                                .frame(height: 1)
                                .padding(.leading, width < 720 ? 76 : 112)
                        }
                    }
                }
            }
            .background(theme.card.opacity(theme.id == .ink ? 0.46 : 1.0))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(theme.separator.opacity(0.58), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    @ViewBuilder
    private func discoveryTrigger<Content: View>(
        for manga: Manga,
        @ViewBuilder content: () -> Content
    ) -> some View {
        MangaDetailNavigationTrigger(
            compositionRoot: compositionRoot,
            manga: manga,
            onOpenMangaDetail: onOpenMangaDetail,
            content: content
        )
    }

    @ViewBuilder
    private func resultTrigger<Content: View>(
        for group: MangaSearchGroup,
        primary: Manga,
        @ViewBuilder content: () -> Content
    ) -> some View {
        MangaDetailNavigationTrigger(
            compositionRoot: compositionRoot,
            manga: primary,
            alternativeMangas: group.mangas,
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

    private func discoveryColumns(for width: CGFloat) -> [GridItem] {
        let minimum: CGFloat = width > 900 ? 180 : 140
        return [GridItem(.adaptive(minimum: minimum, maximum: minimum + 80), spacing: YomuhonSpacing.medium)]
    }

    private func genreColumns(for width: CGFloat) -> [GridItem] {
        let minimum: CGFloat = width > 900 ? 120 : 96
        return [GridItem(.adaptive(minimum: minimum, maximum: minimum + 54), spacing: YomuhonSpacing.small)]
    }

    private var resultsTitle: LocalizedStringKey {
        viewModel.trimmedQuery.isEmpty ? "search.discover.title" : "search.results"
    }

    private var resultsSummary: String {
        String.localizedStringWithFormat(
            NSLocalizedString("search.results.summary", comment: ""),
            viewModel.readableGroupedResults.count
        )
    }

    private func metadataText(for group: MangaSearchGroup, isCatalogOnly: Bool = false) -> String {
        let chapters = group.chapterCount > 0
            ? String.localizedStringWithFormat(NSLocalizedString("search.chapterCount", comment: ""), group.chapterCount)
            : NSLocalizedString("search.untitled", comment: "")

        let versions = group.sourceCount > 1
            ? String.localizedStringWithFormat(NSLocalizedString("search.versionCount", comment: ""), group.sourceCount)
            : sourceTitle(for: group.primaryManga?.sourceID ?? "")

        if isCatalogOnly {
            return String.localizedStringWithFormat(
                NSLocalizedString("search.catalogOnly.metadataFormat", comment: ""),
                chapters,
                versions
            )
        }

        return String.localizedStringWithFormat(
            NSLocalizedString("search.metadata.format", comment: ""),
            chapters,
            versions
        )
    }

    private func sourceTitle(for sourceID: String) -> String {
        sourceID.isEmpty
            ? NSLocalizedString("detail.source", comment: "")
            : NativeSourceCatalog.displayName(for: sourceID)
    }

    private func scheduleSearch() {
        pendingSearch?.cancel()
        viewModel.cancelSearch()

        guard !viewModel.trimmedQuery.isEmpty else {
            viewModel.reset()
            return
        }

        let workItem = DispatchWorkItem {
            viewModel.search()
        }

        pendingSearch = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }
}



private struct SearchResultSkeletonRow: View {
    let isCompact: Bool

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: isCompact ? YomuhonSpacing.medium : YomuhonSpacing.large) {
            YomuhonSkeletonBlock(cornerRadius: 12)
                .frame(width: isCompact ? 58 : 82, height: isCompact ? 82 : 116)

            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                YomuhonSkeletonBlock(cornerRadius: 5)
                    .frame(width: isCompact ? 180 : 260, height: 16)

                HStack(spacing: 6) {
                    YomuhonSkeletonBlock(cornerRadius: 5)
                        .frame(width: 74, height: 10)
                    YomuhonSkeletonBlock(cornerRadius: 5)
                        .frame(width: 94, height: 10)
                }

                HStack(spacing: 6) {
                    YomuhonSkeletonBlock(cornerRadius: 10)
                        .frame(width: 84, height: 22)
                    YomuhonSkeletonBlock(cornerRadius: 10)
                        .frame(width: 96, height: 22)
                    if !isCompact {
                        YomuhonSkeletonBlock(cornerRadius: 10)
                            .frame(width: 72, height: 22)
                    }
                }

                if !isCompact {
                    YomuhonSkeletonBlock(cornerRadius: 5)
                        .frame(width: 360, height: 10)
                    YomuhonSkeletonBlock(cornerRadius: 5)
                        .frame(width: 280, height: 10)
                }
            }

            Spacer()
        }
        .padding(isCompact ? YomuhonSpacing.medium : YomuhonSpacing.large)
    }
}

private struct DiscoveryMangaPoster: View {
    let manga: Manga

    @Environment(\.yomuhonTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
            CoverView(title: manga.title, imageURL: manga.coverURL, cornerRadius: 16)
                .frame(width: 118, height: 172)
                .clipped()
                .shadow(color: theme.shadow.opacity(isHovering ? 0.72 : 0.42), radius: isHovering ? 12 : 7, x: 0, y: isHovering ? 7 : 4)

            Text(manga.title)
                .font(YomuhonTypography.captionMedium)
                .foregroundColor(theme.textPrimary)
                .lineLimit(2)
                .frame(width: 118, alignment: .leading)
        }
        .contentShape(Rectangle())
        .scaleEffect(isHovering ? 1.018 : 1)
        .onHover { isHovering = $0 }
        .animation(theme.animation, value: isHovering)
    }
}

private struct SearchResultBookRow: View {
    let manga: Manga
    let title: String
    let metadata: String
    let sourceBreakdown: String
    let sourceBadges: [SearchSourceBadge]
    let bestSourceName: String
    let isCompact: Bool
    let availability: LocalizedStringKey

    @Environment(\.yomuhonTheme) private var theme
    @State private var isHovering = false

    private var sourceChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sourceBadges) { badge in
                    HStack(spacing: 4) {
                        if badge.isBest {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9, weight: .semibold))
                        }

                        Text(badge.displayTitle)
                            .lineLimit(1)
                    }
                    .font(YomuhonTypography.captionMedium)
                    .foregroundColor(badge.isBest ? theme.accent : theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(badge.isBest ? theme.accent.opacity(0.13) : theme.secondaryBackground.opacity(0.64))
                    .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private var cleanSynopsis: String? {
        manga.cleanSynopsis
    }

    var body: some View {
        HStack(alignment: .top, spacing: isCompact ? YomuhonSpacing.medium : YomuhonSpacing.large) {
            CoverView(title: title, imageURL: manga.coverURL, cornerRadius: 12)
                .frame(width: isCompact ? 58 : 82, height: isCompact ? 82 : 116)
                .clipped()
                .shadow(color: theme.shadow.opacity(isHovering ? 0.7 : 0.4), radius: isHovering ? 10 : 6, x: 0, y: isHovering ? 6 : 3)

            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                Text(title)
                    .font(isCompact ? YomuhonTypography.calloutSemibold : YomuhonTypography.headline)
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(2)

                HStack(spacing: YomuhonSpacing.small) {
                    Text(metadata)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)

                    Text(availability)
                        .font(YomuhonTypography.captionMedium)
                        .foregroundColor(theme.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(theme.secondaryBackground.opacity(0.72))
                        .clipShape(Capsule())
                }

                if !sourceBadges.isEmpty {
                    sourceChipRow
                }

                if !isCompact, let synopsis = cleanSynopsis, !synopsis.isEmpty {
                    Text(synopsis)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                        .lineSpacing(2)
                        .lineLimit(2)
                        .frame(maxWidth: 560, alignment: .leading)
                }
            }

            Spacer(minLength: YomuhonSpacing.medium)

            Image(systemName: "chevron.right")
                .font(YomuhonTypography.captionMedium)
                .foregroundColor(theme.textSecondary.opacity(0.62))
                .padding(.top, 4)
        }
        .padding(isCompact ? YomuhonSpacing.medium : YomuhonSpacing.large)
        .contentShape(Rectangle())
        .background(isHovering ? theme.secondaryBackground.opacity(0.34) : Color.clear)
        .onHover { isHovering = $0 }
        .animation(theme.animation, value: isHovering)
    }
}
