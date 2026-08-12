//
//  SourceCatalogView.swift
//  Yomuhon
//
//  Reachable by tapping a source in Sources. Shows what a single source
//  offers on its own — its own genres and its own popular shelf — plus a
//  search field scoped to just that source, instead of the aggregated
//  cross-source view that Search provides.
//

import SwiftUI

struct SourceCatalogView: View {
    @StateObject private var viewModel: SourceCatalogViewModel
    private let compositionRoot: PresentationCompositionRoot
    private let onOpenMangaDetail: ((MangaDetailViewModel) -> Void)?

    @Environment(\.yomuhonTheme) private var theme
    @State private var pendingSearch: DispatchWorkItem?

    init(
        viewModel: SourceCatalogViewModel,
        compositionRoot: PresentationCompositionRoot = .live,
        onOpenMangaDetail: ((MangaDetailViewModel) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.compositionRoot = compositionRoot
        self.onOpenMangaDetail = onOpenMangaDetail
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: YomuhonSpacing.extraLarge) {
                    header
                    YomuhonNativeSearchField(
                        text: $viewModel.query,
                        placeholder: "sourceCatalog.search.placeholder",
                        maxWidth: nil
                    )
                    content(width: proxy.size.width)
                }
                .padding(.horizontal, contentPadding(for: proxy.size.width))
                .padding(.top, YomuhonSpacing.extraLarge)
                .padding(.bottom, YomuhonSpacing.grand)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(theme.background)
        .navigationTitle(viewModel.displayName)
        .onChange(of: viewModel.query) { _ in scheduleSearch() }
        .onAppear { viewModel.loadIfNeeded() }
        .animation(theme.animation, value: viewModel.isSearching)
        .animation(theme.animation, value: viewModel.selectedGenreIDs)
        .animation(theme.animation, value: viewModel.selectedTypeIDs)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
            Text(viewModel.displayName)
                .font(YomuhonTypography.largeTitle)
                .foregroundColor(theme.textPrimary)

            Text("sourceCatalog.subtitle")
                .font(YomuhonTypography.body)
                .foregroundColor(theme.textSecondary)
        }
    }

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        if !viewModel.isBrowsingCatalog {
            searchResultsSection(width: width)
        } else if viewModel.isLoadingInfo {
            loadingState
        } else if viewModel.infoLoadFailed {
            YomuhonEmptyState(
                systemImage: "exclamationmark.triangle",
                title: "sourceCatalog.unavailable.title",
                message: "sourceCatalog.unavailable.message"
            )
            .frame(minHeight: 220)
        } else {
            catalogSection(width: width)
        }
    }

    private var loadingState: some View {
        HStack(spacing: YomuhonSpacing.small) {
            ProgressView().controlSize(.small)
            Text("sourceCatalog.loading")
                .font(YomuhonTypography.caption)
                .foregroundColor(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
    }

    @ViewBuilder
    private func catalogSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.extraLarge) {
            if viewModel.supportsTypes, !viewModel.types.isEmpty {
                typeFilterSection(width: width)
            }

            if viewModel.supportsGenres, !viewModel.genres.isEmpty {
                genreFilterSection(width: width)
            }

            if !viewModel.selectedGenreIDs.isEmpty || !viewModel.selectedTypeIDs.isEmpty {
                browseResultsSection(width: width)
            }

            if viewModel.supportsPopular, viewModel.selectedGenreIDs.isEmpty, viewModel.selectedTypeIDs.isEmpty {
                // Most sources today only map a "popular" shelf and never
                // declare genres/types, so that shelf is effectively the
                // only way to browse this source at all. Label it as the
                // catalog in that case instead of implying it's merely a
                // curated trending subset of a larger browsable library
                // that doesn't actually exist for this source.
                let isOnlyBrowseSurface = !viewModel.supportsGenres && !viewModel.supportsTypes
                let sectionTitle: LocalizedStringKey = isOnlyBrowseSurface
                    ? "sourceCatalog.catalog.title"
                    : "sourceCatalog.popular.title"

                if !viewModel.popularMangas.isEmpty {
                    mangaGridSection(
                        title: sectionTitle,
                        mangas: viewModel.popularMangas,
                        width: width,
                        onAppearItem: { manga in viewModel.loadMorePopularIfNeeded(currentItem: manga) },
                        isLoadingMore: viewModel.isLoadingMorePopular,
                        showEndOfResults: !viewModel.hasMorePopularPages
                    )
                } else if viewModel.popularLoadFailed {
                    YomuhonEmptyState(
                        systemImage: "wifi.exclamationmark",
                        title: "sourceCatalog.popular.failed.title",
                        message: "sourceCatalog.popular.failed.message"
                    )
                    retryButton { viewModel.loadInfo() }
                } else if !viewModel.isLoadingInfo {
                    YomuhonEmptyState(
                        systemImage: "photo.on.rectangle.angled",
                        title: "sourceCatalog.popular.empty.title",
                        message: "sourceCatalog.popular.empty.message"
                    )
                }
            }

            if !viewModel.supportsGenres, !viewModel.supportsTypes, !viewModel.supportsPopular {
                YomuhonEmptyState(
                    systemImage: "magnifyingglass",
                    title: "sourceCatalog.searchOnly.title",
                    message: "sourceCatalog.searchOnly.message"
                )
                .frame(minHeight: 200)
            }
        }
    }

    private func retryButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("sourceCatalog.retry")
                .font(YomuhonTypography.captionMedium)
                .foregroundColor(theme.accent)
                .padding(.horizontal, YomuhonSpacing.medium)
                .padding(.vertical, 9)
                .background(theme.accent.opacity(0.16))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func genreFilterSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            VStack(alignment: .leading, spacing: 4) {
                Text("sourceCatalog.genres.title")
                    .font(YomuhonTypography.headline)
                    .foregroundColor(theme.textPrimary)

                Text("sourceCatalog.genres.subtitle")
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
            }

            LazyVGrid(columns: genreColumns(for: width), alignment: .leading, spacing: YomuhonSpacing.small) {
                ForEach(viewModel.genres) { genre in
                    let isSelected = viewModel.selectedGenreIDs.contains(genre.id)
                    Button {
                        viewModel.toggleGenre(genre)
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
    }

    private func typeFilterSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            VStack(alignment: .leading, spacing: 4) {
                Text("sourceCatalog.types.title")
                    .font(YomuhonTypography.headline)
                    .foregroundColor(theme.textPrimary)

                Text("sourceCatalog.types.subtitle")
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
            }

            LazyVGrid(columns: genreColumns(for: width), alignment: .leading, spacing: YomuhonSpacing.small) {
                let allSelected = viewModel.isShowingFullTypeCatalog
                Button {
                    viewModel.selectAllTypes()
                } label: {
                    Text("sourceCatalog.types.all")
                        .font(YomuhonTypography.captionMedium)
                        .foregroundColor(allSelected ? theme.accent : theme.textPrimary)
                        .padding(.horizontal, YomuhonSpacing.medium)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(
                            allSelected
                                ? theme.accent.opacity(0.16)
                                : theme.secondaryBackground.opacity(0.72)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                ForEach(viewModel.types) { type in
                    let isSelected = viewModel.selectedTypeIDs.contains(type.id)
                    Button {
                        viewModel.toggleType(type)
                    } label: {
                        Text(type.title)
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
    }

    @ViewBuilder
    private func browseResultsSection(width: CGFloat) -> some View {
        if !viewModel.browseMangas.isEmpty {
            mangaGridSection(
                title: viewModel.isShowingFullTypeCatalog
                    ? "sourceCatalog.fullCatalog.title"
                    : "sourceCatalog.filterResults.title",
                mangas: viewModel.browseMangas,
                width: width
            )
        } else if viewModel.isLoadingBrowse {
            loadingState
        } else if viewModel.browseLoadFailed {
            YomuhonEmptyState(
                systemImage: "wifi.exclamationmark",
                title: "sourceCatalog.popular.failed.title",
                message: "sourceCatalog.popular.failed.message"
            )
            retryButton { viewModel.retryBrowse() }
        } else {
            YomuhonEmptyState(
                systemImage: "doc.text.magnifyingglass",
                title: "sourceCatalog.filterResults.empty.title",
                message: "sourceCatalog.filterResults.empty.message"
            )
        }
    }

    @ViewBuilder
    private func searchResultsSection(width: CGFloat) -> some View {
        if viewModel.isSearching, viewModel.searchResults.isEmpty {
            loadingState
        } else if let errorMessage = viewModel.searchErrorMessage {
            YomuhonEmptyState(
                systemImage: "exclamationmark.triangle",
                title: "sourceCatalog.search.error.title",
                message: LocalizedStringKey(errorMessage)
            )
        } else if viewModel.hasSearched, viewModel.searchResults.isEmpty {
            YomuhonEmptyState(
                systemImage: "doc.text.magnifyingglass",
                title: "search.noResults.title",
                message: "search.noResults.message"
            )
        } else {
            mangaGridSection(
                title: "sourceCatalog.searchResults.title",
                mangas: viewModel.searchResults,
                width: width
            )
        }
    }

    private func mangaGridSection(
        title: LocalizedStringKey,
        mangas: [Manga],
        width: CGFloat,
        onAppearItem: ((Manga) -> Void)? = nil,
        isLoadingMore: Bool = false,
        showEndOfResults: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            Text(title)
                .font(YomuhonTypography.headline)
                .foregroundColor(theme.textPrimary)

            LazyVGrid(columns: posterColumns(for: width), alignment: .leading, spacing: YomuhonSpacing.medium) {
                ForEach(mangas, id: \.self) { manga in
                    mangaTrigger(for: manga) {
                        SourceCatalogMangaPoster(manga: manga)
                    }
                    .onAppear { onAppearItem?(manga) }
                }
            }

            if isLoadingMore {
                HStack(spacing: YomuhonSpacing.small) {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                .padding(.top, YomuhonSpacing.small)
            } else if showEndOfResults {
                Text("sourceCatalog.popular.endOfResults")
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, YomuhonSpacing.small)
            }
        }
    }

    @ViewBuilder
    private func mangaTrigger<Content: View>(
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

    private func contentPadding(for width: CGFloat) -> CGFloat {
        if width < 560 { return YomuhonSpacing.medium }
        if width < 900 { return YomuhonSpacing.extraLarge }
        return YomuhonSpacing.grand
    }

    private func genreColumns(for width: CGFloat) -> [GridItem] {
        let minimum: CGFloat = width > 900 ? 120 : 96
        return [GridItem(.adaptive(minimum: minimum, maximum: minimum + 54), spacing: YomuhonSpacing.small)]
    }

    private func posterColumns(for width: CGFloat) -> [GridItem] {
        let minimum: CGFloat = width > 900 ? 140 : 112
        return [GridItem(.adaptive(minimum: minimum, maximum: minimum + 60), spacing: YomuhonSpacing.medium)]
    }

    private func scheduleSearch() {
        pendingSearch?.cancel()

        guard !viewModel.trimmedQuery.isEmpty else {
            viewModel.clearSearch()
            return
        }

        let workItem = DispatchWorkItem {
            viewModel.search()
        }

        pendingSearch = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: workItem)
    }
}

private struct SourceCatalogMangaPoster: View {
    let manga: Manga

    @Environment(\.yomuhonTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
            CoverView(title: manga.title, imageURL: manga.coverURL, cornerRadius: 16)
                .aspectRatio(118.0 / 172.0, contentMode: .fit)
                .shadow(color: theme.shadow.opacity(isHovering ? 0.72 : 0.42), radius: isHovering ? 12 : 7, x: 0, y: isHovering ? 7 : 4)
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
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .scaleEffect(isHovering ? 1.018 : 1)
        .onHover { isHovering = $0 }
        .animation(theme.animation, value: isHovering)
    }
}
