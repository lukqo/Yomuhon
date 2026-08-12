//
//  SourceCatalogViewModel.swift
//  Yomuhon
//

import Combine
import Foundation

final class SourceCatalogViewModel: ObservableObject {
    let sourceID: String
    let fallbackName: String

    @Published private(set) var displayName: String = ""
    @Published private(set) var supportsPopular = false
    @Published private(set) var supportsGenres = false
    @Published private(set) var genres: [SourceDiscoveryGenre] = []
    @Published var selectedGenreIDs: Set<String> = []
    @Published private(set) var supportsTypes = false
    @Published private(set) var types: [SourceDiscoveryType] = []
    @Published var selectedTypeIDs: Set<String> = []

    @Published private(set) var popularMangas: [Manga] = []
    @Published private(set) var browseMangas: [Manga] = []
    @Published private(set) var isLoadingInfo = false
    @Published private(set) var isLoadingBrowse = false
    @Published private(set) var infoLoadFailed = false
    /// Whether another popular page is being fetched in the background
    /// after the person scrolled near the end of the grid.
    @Published private(set) var isLoadingMorePopular = false
    /// False once the source ran out of popular pages (or declares fewer
    /// than we've already fetched) — the view swaps the "load more" trigger
    /// for an "end of results" message.
    @Published private(set) var hasMorePopularPages = true
    /// True only when the popular/catalog fetch actually threw (network error,
    /// broken selector, etc). Kept distinct from "no results" so the view can
    /// tell "this source is genuinely empty" apart from "we couldn't reach it"
    /// and offer a retry instead of a flat empty state for the latter.
    @Published private(set) var popularLoadFailed = false
    /// Same idea as popularLoadFailed, but for the genre/type browse grid.
    @Published private(set) var browseLoadFailed = false

    @Published var query = ""
    @Published private(set) var searchResults: [Manga] = []
    @Published private(set) var isSearching = false
    @Published private(set) var hasSearched = false
    @Published private(set) var searchErrorMessage: String?

    private let useCase: SourceCatalogUseCase
    private var infoGeneration = 0
    private var browseGeneration = 0
    private var searchGeneration = 0
    private var popularPage = 1
    private var seenPopularMangaIDs: Set<String> = []

    init(sourceID: String, fallbackName: String, useCase: SourceCatalogUseCase) {
        self.sourceID = sourceID
        self.fallbackName = fallbackName
        self.displayName = fallbackName
        self.useCase = useCase
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isBrowsingCatalog: Bool {
        trimmedQuery.isEmpty
    }

    func loadIfNeeded() {
        guard genres.isEmpty, popularMangas.isEmpty, !isLoadingInfo, !infoLoadFailed else { return }
        loadInfo()
    }

    func loadInfo() {
        infoGeneration += 1
        let generation = infoGeneration
        isLoadingInfo = true
        infoLoadFailed = false
        popularLoadFailed = false

        let useCase = self.useCase
        let sourceID = self.sourceID
        let fallbackName = self.fallbackName

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let info = useCase.info(forSourceID: sourceID, fallbackName: fallbackName)

            // Distinguish "the source genuinely has nothing to show" from
            // "we couldn't reach/parse it this time" instead of collapsing
            // both into an empty array. A transient network error or a
            // selector that no longer matches the live site shouldn't look
            // identical to a source that truly has no catalog page.
            var popular: [Manga] = []
            var popularFailed = false
            if info?.supportsPopular == true {
                do {
                    popular = try useCase.popularManga(sourceID: sourceID, page: 1)
                } catch {
                    popularFailed = true
                }
            }

            DispatchQueue.main.async {
                guard let self, self.infoGeneration == generation else { return }
                self.isLoadingInfo = false

                guard let info else {
                    self.infoLoadFailed = true
                    return
                }

                self.displayName = info.name
                self.supportsPopular = info.supportsPopular
                self.supportsGenres = info.supportsGenres
                self.genres = info.genres
                self.supportsTypes = info.supportsTypes
                self.types = info.types
                self.popularMangas = popular
                self.popularLoadFailed = popularFailed
                self.popularPage = 1
                self.seenPopularMangaIDs = Set(popular.map { $0.id })
                self.hasMorePopularPages = !popular.isEmpty && !popularFailed

                // If the source declares its own content-type taxonomy
                // (manga/manhwa/novela ligera/etc.), show the full combined
                // catalog right away instead of making the person tap a
                // filter chip before anything appears. Genres are left
                // unselected by default since a source can expose dozens of
                // them and auto-loading all of them would mean firing off
                // that many network requests just to open the screen.
                if info.supportsTypes, !info.types.isEmpty {
                    self.selectedTypeIDs = Set(info.types.map { $0.id })
                    self.loadBrowseResults()
                }
            }
        }
    }

    /// Restores the default "show everything" state after the person has
    /// narrowed the type filter down and wants the full catalog back.
    func selectAllTypes() {
        guard !types.isEmpty else { return }
        selectedTypeIDs = Set(types.map { $0.id })
        loadBrowseResults()
    }

    var isShowingFullTypeCatalog: Bool {
        supportsTypes && !types.isEmpty && selectedGenreIDs.isEmpty && selectedTypeIDs.count == types.count
    }

    func retryBrowse() {
        loadBrowseResults()
    }

    /// Called from the grid's `.onAppear` as each poster renders. Fires the
    /// next page fetch once the person scrolls within a few rows of the end,
    /// so the next page is usually ready before they reach it. Cheap no-ops
    /// otherwise — safe to call on every appearance.
    func loadMorePopularIfNeeded(currentItem: Manga) {
        guard isBrowsingCatalog, selectedGenreIDs.isEmpty, selectedTypeIDs.isEmpty else { return }
        guard supportsPopular, hasMorePopularPages, !isLoadingMorePopular, !isLoadingInfo else { return }
        guard let index = popularMangas.firstIndex(where: { $0.id == currentItem.id }) else { return }

        let prefetchThreshold = max(popularMangas.count - 6, 0)
        guard index >= prefetchThreshold else { return }

        loadMorePopular()
    }

    private func loadMorePopular() {
        isLoadingMorePopular = true
        let nextPage = popularPage + 1
        let generation = infoGeneration
        let useCase = self.useCase
        let sourceID = self.sourceID

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var page: [Manga] = []
            var failed = false
            do {
                page = try useCase.popularManga(sourceID: sourceID, page: nextPage)
            } catch {
                failed = true
            }

            DispatchQueue.main.async {
                guard let self, self.infoGeneration == generation else { return }
                self.isLoadingMorePopular = false

                guard !failed, !page.isEmpty else {
                    // Either the source threw, or it has nothing left for
                    // this page — either way, stop asking for more.
                    self.hasMorePopularPages = false
                    return
                }

                self.popularPage = nextPage
                var appended: [Manga] = []
                for manga in page where self.seenPopularMangaIDs.insert(manga.id).inserted {
                    appended.append(manga)
                }
                self.popularMangas.append(contentsOf: appended)

                // A page that came back non-empty but entirely duplicates
                // of what we already have means we've looped back to the
                // start — treat that as the end too.
                if appended.isEmpty {
                    self.hasMorePopularPages = false
                }
            }
        }
    }

    func toggleGenre(_ genre: SourceDiscoveryGenre) {
        if selectedGenreIDs.contains(genre.id) {
            selectedGenreIDs.remove(genre.id)
        } else {
            selectedGenreIDs.insert(genre.id)
        }
        loadBrowseResults()
    }

    func toggleType(_ type: SourceDiscoveryType) {
        if selectedTypeIDs.contains(type.id) {
            selectedTypeIDs.remove(type.id)
        } else {
            selectedTypeIDs.insert(type.id)
        }
        loadBrowseResults()
    }

    private func loadBrowseResults() {
        browseGeneration += 1
        let generation = browseGeneration

        guard !selectedGenreIDs.isEmpty || !selectedTypeIDs.isEmpty else {
            browseMangas = []
            browseLoadFailed = false
            isLoadingBrowse = false
            return
        }

        isLoadingBrowse = true
        browseLoadFailed = false
        let genreIDs = selectedGenreIDs
        let typeIDs = selectedTypeIDs
        let useCase = self.useCase
        let sourceID = self.sourceID

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var seen = Set<String>()
            var merged: [Manga] = []
            // A single filter failing shouldn't hide results from the others
            // the user also selected, but if *every* selected filter throws,
            // that's a real failure, not "this combination has zero titles".
            var attemptCount = 0
            var failureCount = 0

            for genreID in genreIDs {
                attemptCount += 1
                do {
                    let mangas = try useCase.manga(sourceID: sourceID, genreID: genreID)
                    for manga in mangas where seen.insert(manga.id).inserted {
                        merged.append(manga)
                    }
                } catch {
                    failureCount += 1
                }
            }

            for typeID in typeIDs {
                attemptCount += 1
                do {
                    let mangas = try useCase.manga(sourceID: sourceID, typeID: typeID)
                    for manga in mangas where seen.insert(manga.id).inserted {
                        merged.append(manga)
                    }
                } catch {
                    failureCount += 1
                }
            }

            merged.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            let allFailed = attemptCount > 0 && failureCount == attemptCount

            DispatchQueue.main.async {
                guard let self, self.browseGeneration == generation else { return }
                self.browseMangas = merged
                self.browseLoadFailed = allFailed
                self.isLoadingBrowse = false
            }
        }
    }

    func search() {
        let trimmed = trimmedQuery
        searchGeneration += 1
        let generation = searchGeneration

        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            hasSearched = false
            searchErrorMessage = nil
            return
        }

        isSearching = true
        hasSearched = true
        searchErrorMessage = nil

        let useCase = self.useCase
        let sourceID = self.sourceID

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let results = try useCase.search(sourceID: sourceID, query: trimmed)
                DispatchQueue.main.async {
                    guard let self, self.searchGeneration == generation else { return }
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.searchGeneration == generation else { return }
                    self.searchResults = []
                    self.isSearching = false
                    self.searchErrorMessage = String(localized: "sourceCatalog.search.error")
                }
            }
        }
    }

    func clearSearch() {
        searchGeneration += 1
        query = ""
        searchResults = []
        isSearching = false
        hasSearched = false
        searchErrorMessage = nil
    }
}
