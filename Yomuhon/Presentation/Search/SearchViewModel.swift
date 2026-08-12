//
//  SearchViewModel.swift
//  Yomuhon
//

import Combine
import Foundation

struct SearchSourceBadge: Identifiable, Equatable {
    let id: String
    let title: String
    let chapterCount: Int
    let isBest: Bool
    let isReadable: Bool

    var displayTitle: String {
        chapterCount > 0
            ? String.localizedStringWithFormat(NSLocalizedString("search.sourceChip.format", comment: ""), title, chapterCount)
            : title
    }
}

struct MangaSearchGroup: Identifiable, Equatable {
    let id: String
    let mangas: [Manga]

    var primaryManga: Manga? {
        bestCoverManga ?? bestManga ?? mangas.first
    }

    var title: String {
        primaryManga?.title ?? String(localized: "search.untitled")
    }

    var sourceCount: Int {
        sourceIDs.count
    }

    var sourceIDs: [String] {
        mangas.map(\.sourceID).deduplicated()
    }

    var chapterCount: Int {
        bestManga?.chapters.count ?? primaryManga?.chapters.count ?? 0
    }

    var bestCoverManga: Manga? {
        mangas
            .filter { $0.coverURL != nil }
            .max { searchResultRank(for: $0) < searchResultRank(for: $1) }
    }

    var bestManga: Manga? {
        mangas.max { searchResultRank(for: $0) < searchResultRank(for: $1) }
    }

    var bestSourceName: String {
        guard let sourceID = bestManga?.sourceID else {
            return String(localized: "detail.source")
        }

        return NativeSourceCatalog.displayName(for: sourceID)
    }

    var hasReadableSource: Bool {
        mangas.contains { NativeSourceCatalog.supportsReading(sourceID: $0.sourceID) }
    }

    var sourceBadges: [SearchSourceBadge] {
        let bestID = bestManga?.sourceID
        let bestFamily = bestID.map { NativeSourceCatalog.canonicalFamily(for: $0, name: NativeSourceCatalog.displayName(for: $0)) }
        var bestByFamily: [String: Manga] = [:]

        for manga in mangas {
            let family = NativeSourceCatalog.canonicalFamily(
                for: manga.sourceID,
                name: NativeSourceCatalog.displayName(for: manga.sourceID)
            )

            guard let current = bestByFamily[family] else {
                bestByFamily[family] = manga
                continue
            }

            if manga.chapters.count > current.chapters.count || (manga.chapters.count == current.chapters.count && manga.coverURL != nil && current.coverURL == nil) {
                bestByFamily[family] = manga
            }
        }

        return bestByFamily
            .map { family, manga in (family: family, manga: manga) }
            .sorted { lhs, rhs in
                if lhs.family == bestFamily { return true }
                if rhs.family == bestFamily { return false }
                if lhs.manga.chapters.count != rhs.manga.chapters.count {
                    return lhs.manga.chapters.count > rhs.manga.chapters.count
                }

                return NativeSourceCatalog.displayName(for: lhs.manga.sourceID)
                    .localizedCaseInsensitiveCompare(NativeSourceCatalog.displayName(for: rhs.manga.sourceID)) == .orderedAscending
            }
            .map { family, manga in
                SearchSourceBadge(
                    id: family,
                    title: NativeSourceCatalog.familyDisplayName(for: family, fallbackSourceID: manga.sourceID),
                    chapterCount: manga.chapters.count,
                    isBest: family == bestFamily,
                    isReadable: mangas.contains { candidate in
                        NativeSourceCatalog.canonicalFamily(for: candidate.sourceID, name: NativeSourceCatalog.displayName(for: candidate.sourceID)) == family
                            && NativeSourceCatalog.supportsReading(sourceID: candidate.sourceID)
                    }
                )
            }
    }

    var sourceBreakdown: String {
        sourceBadges
            .map { $0.displayTitle }
            .joined(separator: " · ")
    }
}

final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [Manga] = []
    @Published private(set) var readableGroups: [MangaSearchGroup] = []
    @Published private(set) var allGroups: [MangaSearchGroup] = []
    @Published private(set) var catalogOnlyGroups: [MangaSearchGroup] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasSearched = false
    @Published private(set) var hasEnabledSources = true
    @Published private(set) var popularMangas: [Manga] = []
    @Published private(set) var discoveryGenres: [SourceDiscoveryGenre] = []
    @Published private(set) var selectedGenre: SourceDiscoveryGenre?
    @Published private(set) var genreMangas: [Manga] = []
    @Published private(set) var isLoadingDiscovery = false
    @Published private(set) var isLoadingGenre = false
    @Published var selectedSearchSourceID: String = "all"
    @Published var onlyReadableResults = true
    @Published private(set) var completedSourceCount = 0
    @Published private(set) var totalSourceCount = 0

    private let searchMangaUseCase: SearchMangaUseCase
    private let processor = SearchProcessor()
    
    private var searchGeneration = 0
    private var discoveryGeneration = 0
    private var genreGeneration = 0
    private var activeSearchToken: RequestCancellationToken?
    private var activeDiscoveryToken: RequestCancellationToken?
    private var activeGenreToken: RequestCancellationToken?
    private var searchSourcePositions: [String: Int] = [:]
    private var stableSearchGroupOrder: [String] = []

    init(searchMangaUseCase: SearchMangaUseCase) {
        self.searchMangaUseCase = searchMangaUseCase
        refreshSourceAvailability()
    }

    deinit {
        activeSearchToken?.cancel()
        activeDiscoveryToken?.cancel()
        activeGenreToken?.cancel()
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var searchProgressMessage: String? {
        guard isSearching, totalSourceCount > 0 else { return nil }
        return String.localizedStringWithFormat(
            NSLocalizedString("search.progress.sources", comment: ""),
            completedSourceCount,
            totalSourceCount
        )
    }

    var groupedResults: [MangaSearchGroup] {
        readableGroups
    }

    var readableGroupedResults: [MangaSearchGroup] {
        readableGroups
    }

    var catalogOnlyGroupedResults: [MangaSearchGroup] {
        catalogOnlyGroups
    }

    var hasCatalogOnlyResults: Bool {
        !catalogOnlyGroups.isEmpty
    }

    var availableSearchSourceFilters: [SearchSourceFilter] {
        let sourceIDs = Set(results.map(\.sourceID))
        let filters = sourceIDs
            .sorted { NativeSourceCatalog.displayName(for: $0) < NativeSourceCatalog.displayName(for: $1) }
            .map { SearchSourceFilter(id: $0, title: NativeSourceCatalog.displayName(for: $0)) }

        return [SearchSourceFilter(id: "all", title: String(localized: "search.filter.allSources"))] + filters
    }

    var activeReadableGroups: [MangaSearchGroup] {
        let groups = onlyReadableResults ? readableGroups : allGroups
        guard selectedSearchSourceID != "all" else {
            return groups
        }

        return groups.filter { group in
            group.sourceIDs.contains(selectedSearchSourceID)
        }
    }

    func loadDiscovery() {
        refreshSourceAvailability()
        discoveryGenres = searchMangaUseCase.discoveryGenres()

        guard hasEnabledSources, popularMangas.isEmpty, !isLoadingDiscovery else {
            return
        }

        discoveryGeneration += 1
        let generation = discoveryGeneration
        let useCase = searchMangaUseCase

        activeDiscoveryToken?.cancel()
        let cancellationToken = RequestCancellationToken()
        activeDiscoveryToken = cancellationToken

        isLoadingDiscovery = true

        Task { [weak self] in
            await self?.processor.beginDiscoverySession(generation: generation)
            self?.runDiscoveryWork(
                generation: generation,
                cancellationToken: cancellationToken,
                useCase: useCase
            )
        }
    }

    private func runDiscoveryWork(
        generation: Int,
        cancellationToken: RequestCancellationToken,
        useCase: SearchMangaUseCase
    ) {
        DispatchQueue.global(qos: .utility).async {
            let popularResult = Result {
                try useCase.popularManga(cancellationToken: cancellationToken) { progress in
                    Task { [weak self] in
                        guard let self else { return }

                        // Merging and stabilizing both happen inside the
                        // actor's session state, so concurrent progress
                        // updates from different sources never race on the
                        // same underlying arrays.
                        guard let stabilized = await self.processor.ingestDiscoveryProgress(
                            generation: generation,
                            incoming: progress.mangas,
                            progressSourceID: progress.sourceID,
                            limit: 12
                        ) else {
                            return
                        }

                        await MainActor.run {
                            guard generation == self.discoveryGeneration else { return }
                            self.popularMangas = stabilized.mangas
                        }
                    }
                }
            }

            Task { [weak self] in
                guard let self else { return }

                if case .success(let mangas) = popularResult {
                    if let stabilized = await self.processor.finalizeDiscoverySession(
                        generation: generation,
                        mangas: mangas,
                        limit: 12
                    ) {
                        await MainActor.run {
                            guard generation == self.discoveryGeneration else { return }
                            self.popularMangas = stabilized.mangas
                            self.logDiscoveryRanking(kind: "POPULAR", mangas: self.popularMangas)
                        }
                    }
                }

                await MainActor.run {
                    guard generation == self.discoveryGeneration else { return }
                    self.activeDiscoveryToken = nil
                    self.isLoadingDiscovery = false
                }
            }
        }
    }

    func reloadDiscoveryForSourceCatalogChange() {
        activeDiscoveryToken?.cancel()
        activeDiscoveryToken = nil
        activeGenreToken?.cancel()
        activeGenreToken = nil
        discoveryGeneration += 1
        genreGeneration += 1
        popularMangas = []
        discoveryGenres = []
        selectedGenre = nil
        genreMangas = []
        isLoadingDiscovery = false
        isLoadingGenre = false
        refreshSourceAvailability()
        loadDiscovery()
    }

    func selectGenre(_ genre: SourceDiscoveryGenre) {
        refreshSourceAvailability()
        guard hasEnabledSources else { return }

        cancelSearch()
        if !query.isEmpty {
            query = ""
        }

        activeGenreToken?.cancel()
        let cancellationToken = RequestCancellationToken()
        activeGenreToken = cancellationToken

        genreGeneration += 1
        let generation = genreGeneration
        let useCase = searchMangaUseCase

        selectedGenre = genre
        genreMangas = []
        isLoadingGenre = true

        Task { [weak self] in
            await self?.processor.beginGenreSession(generation: generation)
            self?.runGenreWork(
                generation: generation,
                genre: genre,
                cancellationToken: cancellationToken,
                useCase: useCase
            )
        }
    }

    private func runGenreWork(
        generation: Int,
        genre: SourceDiscoveryGenre,
        cancellationToken: RequestCancellationToken,
        useCase: SearchMangaUseCase
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try useCase.manga(
                    forGenreID: genre.id,
                    cancellationToken: cancellationToken
                ) { progress in
                    Task { [weak self] in
                        guard let self else { return }

                        // Merging and stabilizing both happen inside the
                        // actor's session state, so concurrent progress
                        // updates from different sources never race on the
                        // same underlying arrays.
                        guard let stabilized = await self.processor.ingestGenreProgress(
                            generation: generation,
                            incoming: progress.mangas,
                            progressSourceID: progress.sourceID,
                            limit: 24
                        ) else {
                            return
                        }

                        await MainActor.run {
                            guard generation == self.genreGeneration,
                                  self.selectedGenre?.id == genre.id
                            else {
                                return
                            }

                            self.genreMangas = stabilized.mangas
                        }
                    }
                }
            }

            Task { [weak self] in
                guard let self else { return }

                if case .success(let mangas) = result,
                   let stabilized = await self.processor.finalizeGenreSession(
                    generation: generation,
                    mangas: mangas,
                    limit: 24
                   ) {
                    await MainActor.run {
                        guard generation == self.genreGeneration,
                              self.selectedGenre?.id == genre.id
                        else {
                            return
                        }

                        self.genreMangas = stabilized.mangas
                        self.logDiscoveryRanking(kind: "GENRE:\(genre.id)", mangas: self.genreMangas)
                    }
                }

                await MainActor.run {
                    guard generation == self.genreGeneration,
                          self.selectedGenre?.id == genre.id
                    else {
                        return
                    }

                    self.activeGenreToken = nil
                    self.isLoadingGenre = false
                }
            }
        }
    }

    func search() {
        refreshSourceAvailability()

        guard hasEnabledSources else {
            reset()
            return
        }

        let currentQuery = trimmedQuery

        guard !currentQuery.isEmpty else {
            reset()
            return
        }

        activeGenreToken?.cancel()
        activeGenreToken = nil
        genreGeneration += 1
        selectedGenre = nil
        genreMangas = []
        isLoadingGenre = false

        activeSearchToken?.cancel()
        let cancellationToken = RequestCancellationToken()
        activeSearchToken = cancellationToken

        searchGeneration += 1
        let generation = searchGeneration
        let useCase = searchMangaUseCase

        results = []
        readableGroups = []
        allGroups = []
        catalogOnlyGroups = []
        searchSourcePositions = [:]
        stableSearchGroupOrder = []
        completedSourceCount = 0
        totalSourceCount = 0
        isSearching = true
        hasSearched = true
        errorMessage = nil

        Task { [weak self] in
            await self?.processor.beginSearchSession(generation: generation)
            self?.runSearchWork(
                generation: generation,
                currentQuery: currentQuery,
                cancellationToken: cancellationToken,
                useCase: useCase
            )
        }
    }

    private func runSearchWork(
        generation: Int,
        currentQuery: String,
        cancellationToken: RequestCancellationToken,
        useCase: SearchMangaUseCase
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try useCase.execute(
                    query: currentQuery,
                    cancellationToken: cancellationToken
                ) { progress in
                    guard !cancellationToken.isCancelled else { return }

                    Task { [weak self] in
                        guard let self else { return }

                        // The actor owns the canonical merged results for this
                        // session, so every progress update — even several
                        // arriving in a tight burst as many sources finish at
                        // once — is merged one at a time, in order, with no
                        // chance of two updates racing on the same Array.
                        guard let groupsResult = await self.processor.ingestSearchProgress(
                            generation: generation,
                            incoming: progress.mangas,
                            progressSourceID: progress.sourceID,
                            query: currentQuery
                        ) else {
                            return
                        }

                        await MainActor.run {
                            guard generation == self.searchGeneration,
                                  !cancellationToken.isCancelled
                            else {
                                return
                            }

                            self.completedSourceCount = progress.completedSourceCount
                            self.totalSourceCount = progress.totalSourceCount

                            self.results = groupsResult.mangas
                            self.searchSourcePositions = groupsResult.sourcePositions
                            self.stableSearchGroupOrder = groupsResult.stableOrder
                            self.readableGroups = groupsResult.readableGroups
                            self.allGroups = groupsResult.allGroups
                            self.catalogOnlyGroups = groupsResult.catalogOnlyGroups
                        }
                    }
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      generation == self.searchGeneration,
                      !cancellationToken.isCancelled
                else {
                    return
                }

                switch result {
                case .success(let mangas):
                    self.errorMessage = nil

                    Task { [weak self] in
                        guard let self,
                              let groupsResult = await self.processor.finalizeSearchSession(
                                generation: generation,
                                mangas: mangas,
                                query: currentQuery
                              )
                        else {
                            return
                        }

                        await MainActor.run {
                            guard generation == self.searchGeneration else { return }
                            self.results = groupsResult.mangas
                            self.searchSourcePositions = groupsResult.sourcePositions
                            self.stableSearchGroupOrder = groupsResult.stableOrder
                            self.readableGroups = groupsResult.readableGroups
                            self.allGroups = groupsResult.allGroups
                            self.catalogOnlyGroups = groupsResult.catalogOnlyGroups
                            self.logSearchRanking(query: currentQuery)
                        }
                    }
                case .failure(let error):
                    if let clientError = error as? HTTPClientError, clientError.isCancellation {
                        return
                    }

                    if self.results.isEmpty {
                        self.errorMessage = String(localized: "search.error.message")
                    }
                }

                self.isSearching = false
                self.activeSearchToken = nil
            }
        }
    }

    func cancelSearch() {
        activeSearchToken?.cancel()
        activeSearchToken = nil
        searchGeneration += 1
        isSearching = false
    }

    func reset() {
        cancelSearch()
        results = []
        readableGroups = []
        allGroups = []
        catalogOnlyGroups = []
        searchSourcePositions = [:]
        stableSearchGroupOrder = []
        completedSourceCount = 0
        totalSourceCount = 0
        errorMessage = nil
        hasSearched = false
    }

    private func discoveryMangas(
        from mangas: [Manga],
        limit: Int,
        sourcePositions: [String: Int] = [:]
    ) -> [Manga] {
        DiscoveryRanker.rank(
            mangas: mangas.filter { !$0.hasBadSearchTitle },
            sourcePositions: sourcePositions,
            limit: limit
        )
    }

    private static func mergingSourcePositions(
        current: [String: Int],
        mangas: [Manga],
        progressSourceID: String
    ) -> [String: Int] {
        guard progressSourceID != "cache", progressSourceID != "all" else {
            return current
        }

        var positions = current
        for (index, manga) in mangas.enumerated() {
            let key = rankingKey(for: manga)
            let rank = index + 1
            if let existing = positions[key] {
                positions[key] = Swift.min(existing, rank)
            } else {
                positions[key] = rank
            }
        }

        return positions
    }

    private func logSearchRanking(query: String) {
        #if DEBUG
        let top = readableGroups
            .prefix(5)
            .map { group in
                let score = SearchResultRanker.groupScore(
                    query: query,
                    mangas: group.mangas,
                    sourcePositions: searchSourcePositions
                )
                return "\(group.title)=\(Int(score.rounded()))"
            }
            .joined(separator: " | ")
        print("[Yomuhon][Rank] SEARCH query=\(query) top=[\(top)]")
        #endif
    }

    private func logDiscoveryRanking(kind: String, mangas: [Manga]) {
        #if DEBUG
        let top = mangas.prefix(8).map(\.title).joined(separator: " | ")
        print("[Yomuhon][Rank] \(kind) top=[\(top)]")
        #endif
    }

    func refreshSourceAvailability() {
        hasEnabledSources = searchMangaUseCase.hasAvailableSources()
    }



}


enum MangaIdentityResolver {
    private static let ignorableDescriptorTokens: Set<String> = [
        "manga", "comic", "official", "webtoon"
    ]

    static func canonicalKey(for title: String) -> String {
        canonicalTokens(for: title).joined(separator: " ")
    }

    static func identityKey(for manga: Manga) -> String {
        let keys = manga.identityTitles
            .map(canonicalKey)
            .filter { !$0.isEmpty }

        return keys.min { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            return lhs < rhs
        } ?? canonicalKey(for: manga.title)
    }

    static func clusterKey(for mangas: [Manga]) -> String {
        mangas
            .map(identityKey)
            .filter { !$0.isEmpty }
            .min() ?? canonicalKey(for: mangas.first?.title ?? "")
    }

    static func sameWork(_ lhs: Manga, _ rhs: Manga) -> Bool {
        if let lhsYear = lhs.releaseYear,
           let rhsYear = rhs.releaseYear,
           abs(lhsYear - rhsYear) > 1 {
            return false
        }

        if let lhsAuthor = normalizedAuthor(lhs.author),
           let rhsAuthor = normalizedAuthor(rhs.author),
           !authorsAreCompatible(lhsAuthor, rhsAuthor) {
            return false
        }

        let lhsKeys = Set(lhs.identityTitles.map(canonicalKey).filter { !$0.isEmpty })
        let rhsKeys = Set(rhs.identityTitles.map(canonicalKey).filter { !$0.isEmpty })
        if !lhsKeys.intersection(rhsKeys).isEmpty {
            return true
        }

        for lhsTitle in lhs.identityTitles {
            for rhsTitle in rhs.identityTitles where sameWork(lhsTitle: lhsTitle, rhsTitle: rhsTitle) {
                return true
            }
        }

        return false
    }

    static func sameWork(lhsTitle: String, rhsTitle: String) -> Bool {
        let lhsTokens = canonicalTokens(for: lhsTitle)
        let rhsTokens = canonicalTokens(for: rhsTitle)

        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return false }
        if lhsTokens == rhsTokens { return true }

        // Fuzzy grouping is intentionally conservative. False merges can send a
        // reader from one title into another title's chapters, which is worse than
        // temporarily showing two editions of the same work.
        guard lhsTokens.count >= 4, rhsTokens.count >= 4 else { return false }

        let lhsSet = Set(lhsTokens)
        let rhsSet = Set(rhsTokens)
        let intersectionCount = lhsSet.intersection(rhsSet).count
        let unionCount = lhsSet.union(rhsSet).count
        guard intersectionCount >= 4, unionCount > 0 else { return false }

        let similarity = Double(intersectionCount) / Double(unionCount)
        return similarity >= 0.92
    }

    static func clusters(from mangas: [Manga]) -> [[Manga]] {
        let ranked = mangas.sorted {
            searchResultRank(for: $0) > searchResultRank(for: $1)
        }
        var clusters: [[Manga]] = []

        for manga in ranked {
            if let index = clusters.firstIndex(where: { cluster in
                cluster.contains { sameWork($0, manga) }
            }) {
                clusters[index].append(manga)
            } else {
                clusters.append([manga])
            }
        }

        return clusters
    }

    // canonicalTokens is a pure function of `title`, but clustering compares
    // every manga against every existing cluster (and every manga can have
    // several identityTitles), so without caching this folding+regex work
    // was being redone repeatedly for the same strings on every progressive
    // search update. Memoize per-title to turn that into a one-time cost.
    private static let tokenCacheLock = NSLock()
    private static var tokenCache: [String: [String]] = [:]

    private static func canonicalTokens(for title: String) -> [String] {
        tokenCacheLock.lock()
        if let cached = tokenCache[title] {
            tokenCacheLock.unlock()
            return cached
        }
        tokenCacheLock.unlock()

        let normalized = title
            .removingTrailingSourceNumericIdentifier
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let rawTokens = normalized.split(separator: " ").map(String.init)
        let tokens = rawTokens.count > 2
            ? rawTokens.filter { !ignorableDescriptorTokens.contains($0) }
            : rawTokens

        tokenCacheLock.lock()
        // Keep the cache from growing unbounded across a long session.
        if tokenCache.count > 4_000 {
            tokenCache.removeAll(keepingCapacity: true)
        }
        tokenCache[title] = tokens
        tokenCacheLock.unlock()

        return tokens
    }

    private static func normalizedAuthor(_ author: String?) -> Set<String>? {
        guard let author else { return nil }
        let tokens = author
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 }

        return tokens.isEmpty ? nil : Set(tokens)
    }

    private static func authorsAreCompatible(_ lhs: Set<String>, _ rhs: Set<String>) -> Bool {
        if lhs == rhs { return true }
        let intersection = lhs.intersection(rhs)
        guard !intersection.isEmpty else { return false }

        let denominator = max(lhs.count, rhs.count)
        return Double(intersection.count) / Double(max(denominator, 1)) >= 0.5
    }
}


enum SearchResultRanker {
    static func groupScore(
        query: String,
        mangas: [Manga],
        sourcePositions: [String: Int]
    ) -> Double {
        guard !mangas.isEmpty else { return 0 }

        let bestMatch = mangas
            .map { score(query: query, manga: $0, sourcePositions: sourcePositions) }
            .max() ?? 0
        let sourceFamilies = Set(mangas.map { manga in
            NativeSourceCatalog.canonicalFamily(
                for: manga.sourceID,
                name: NativeSourceCatalog.displayName(for: manga.sourceID)
            )
        })
        let agreementBonus = Double(min(sourceFamilies.count, 5)) * 12

        return bestMatch + agreementBonus
    }

    static func score(
        query: String,
        manga: Manga,
        sourcePositions: [String: Int]
    ) -> Double {
        let relevance = manga.identityTitles
            .map { titleScore(query: query, title: $0) }
            .max() ?? titleScore(query: query, title: manga.title)
        let rankBonus: Double

        if let sourcePosition = sourcePositions[rankingKey(for: manga)] {
            rankBonus = 350 / pow(Double(max(sourcePosition, 1)), 0.45)
        } else {
            rankBonus = 0
        }

        // Source quality only breaks close relevance ties. It must never let a
        // healthy provider push a loosely related title above an exact match.
        let qualityTieBreaker = searchResultRank(for: manga) * 0.005
        return relevance + rankBonus + qualityTieBreaker
    }

    static func titleScore(query: String, title: String) -> Double {
        let normalizedQuery = MangaIdentityResolver.canonicalKey(for: query)
        let normalizedTitle = MangaIdentityResolver.canonicalKey(for: title)

        guard !normalizedQuery.isEmpty, !normalizedTitle.isEmpty else { return 0 }

        let queryTokens = normalizedQuery.split(separator: " ").map(String.init)
        let titleTokens = normalizedTitle.split(separator: " ").map(String.init)

        if normalizedTitle == normalizedQuery {
            return 10_000
        }

        if normalizedTitle.hasPrefix(normalizedQuery + " ") {
            return 9_000 + brevityBonus(query: normalizedQuery, title: normalizedTitle)
        }

        let paddedTitle = " " + normalizedTitle + " "
        let paddedQuery = " " + normalizedQuery + " "
        if paddedTitle.contains(paddedQuery) {
            return 8_000 + brevityBonus(query: normalizedQuery, title: normalizedTitle)
        }

        let querySet = Set(queryTokens)
        let titleSet = Set(titleTokens)
        if querySet.isSubset(of: titleSet) {
            let compactness = Double(queryTokens.count) / Double(max(titleTokens.count, 1))
            return 7_000 + (compactness * 700)
        }

        let prefixMatchCount = queryTokens.filter { queryToken in
            titleTokens.contains { titleToken in
                titleToken.hasPrefix(queryToken) || queryToken.hasPrefix(titleToken)
            }
        }.count
        let prefixCoverage = Double(prefixMatchCount) / Double(max(queryTokens.count, 1))
        let tokenIntersection = querySet.intersection(titleSet).count
        let tokenUnion = querySet.union(titleSet).count
        let tokenSimilarity = tokenUnion > 0
            ? Double(tokenIntersection) / Double(tokenUnion)
            : 0
        let editSimilarity = normalizedEditSimilarity(normalizedQuery, normalizedTitle)
        let tokenCompactness = Double(min(queryTokens.count, titleTokens.count))
            / Double(Swift.max(Swift.max(queryTokens.count, titleTokens.count), 1))

        let prefixScore = (prefixCoverage * 5_500)
            + (editSimilarity * 1_200)
            + (tokenCompactness * 400)
        let tokenScore = tokenSimilarity * 5_000
        let editScore = editSimilarity * 5_200

        return max(prefixScore, tokenScore, editScore)
    }

    private static func brevityBonus(query: String, title: String) -> Double {
        let extraCharacters = max(title.count - query.count, 0)
        return max(0, 450 - Double(extraCharacters * 8))
    }

    private static func normalizedEditSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let lhsCharacters = Array(lhs)
        let rhsCharacters = Array(rhs)
        let maximumLength = max(lhsCharacters.count, rhsCharacters.count)
        guard maximumLength > 0 else { return 1 }

        var previous = Array(0...rhsCharacters.count)

        for (lhsIndex, lhsCharacter) in lhsCharacters.enumerated() {
            var current = [lhsIndex + 1]
            current.reserveCapacity(rhsCharacters.count + 1)

            for (rhsIndex, rhsCharacter) in rhsCharacters.enumerated() {
                let insertion = current[rhsIndex] + 1
                let deletion = previous[rhsIndex + 1] + 1
                let substitution = previous[rhsIndex] + (lhsCharacter == rhsCharacter ? 0 : 1)
                current.append(Swift.min(insertion, Swift.min(deletion, substitution)))
            }

            previous = current
        }

        let distance = previous[rhsCharacters.count]
        return max(0, 1 - (Double(distance) / Double(maximumLength)))
    }
}


enum StableRankingReconciler {
    static func reconcile(
        previous: [String],
        rankedIDs: [String],
        scores: [String: Double],
        dominantIDs: Set<String>,
        minimumPromotionDelta: Double,
        relativePromotionDelta: Double,
        settle: Bool
    ) -> [String] {
        let desired = rankedIDs.deduplicated()
        guard !desired.isEmpty else { return [] }
        guard !settle, !previous.isEmpty else { return desired }

        let desiredSet = Set(desired)
        var order = previous.filter { desiredSet.contains($0) }

        for id in desired where !order.contains(id) {
            guard let targetIndex = desired.firstIndex(of: id) else { continue }
            let insertionIndex = min(targetIndex, order.count)

            if insertionIndex >= order.count {
                order.append(id)
                continue
            }

            let displacedID = order[insertionIndex]
            if shouldPromote(
                id: id,
                over: displacedID,
                scores: scores,
                dominantIDs: dominantIDs,
                minimumPromotionDelta: minimumPromotionDelta,
                relativePromotionDelta: relativePromotionDelta
            ) {
                order.insert(id, at: insertionIndex)
            } else {
                order.append(id)
            }
        }

        for id in desired {
            guard let targetIndex = desired.firstIndex(of: id),
                  let currentIndex = order.firstIndex(of: id),
                  currentIndex > targetIndex,
                  targetIndex < order.count
            else {
                continue
            }

            let displacedID = order[targetIndex]
            guard shouldPromote(
                id: id,
                over: displacedID,
                scores: scores,
                dominantIDs: dominantIDs,
                minimumPromotionDelta: minimumPromotionDelta,
                relativePromotionDelta: relativePromotionDelta
            ) else {
                continue
            }

            order.remove(at: currentIndex)
            order.insert(id, at: targetIndex)
        }

        return order.filter { desiredSet.contains($0) }
    }

    private static func shouldPromote(
        id: String,
        over displacedID: String,
        scores: [String: Double],
        dominantIDs: Set<String>,
        minimumPromotionDelta: Double,
        relativePromotionDelta: Double
    ) -> Bool {
        let candidateIsDominant = dominantIDs.contains(id)
        let displacedIsDominant = dominantIDs.contains(displacedID)
        if candidateIsDominant != displacedIsDominant {
            return candidateIsDominant
        }

        let candidateScore = scores[id] ?? 0
        let displacedScore = scores[displacedID] ?? 0
        let requiredDelta = max(
            minimumPromotionDelta,
            abs(displacedScore) * relativePromotionDelta
        )
        return candidateScore - displacedScore >= requiredDelta
    }
}


enum DiscoveryRanker {
    private struct RankedCluster {
        let representative: Manga
        let score: Double
        let supportingSourceCount: Int
        let bestPosition: Int
        let qualityScore: Double
    }

    static func rank(
        mangas: [Manga],
        sourcePositions: [String: Int],
        limit: Int
    ) -> [Manga] {
        let rankedClusters = MangaIdentityResolver
            .clusters(from: mangas)
            .compactMap { cluster -> RankedCluster? in
                guard let representative = representative(from: cluster) else { return nil }
                let metrics = rankingMetrics(for: cluster, sourcePositions: sourcePositions)

                return RankedCluster(
                    representative: representative,
                    score: metrics.score,
                    supportingSourceCount: metrics.supportingSourceCount,
                    bestPosition: metrics.bestPosition,
                    qualityScore: metrics.qualityScore
                )
            }
            .filter { $0.representative.coverURL != nil }
            .sorted { lhs, rhs in
                if abs(lhs.score - rhs.score) > 0.000_001 {
                    return lhs.score > rhs.score
                }
                if lhs.supportingSourceCount != rhs.supportingSourceCount {
                    return lhs.supportingSourceCount > rhs.supportingSourceCount
                }
                if lhs.bestPosition != rhs.bestPosition {
                    return lhs.bestPosition < rhs.bestPosition
                }
                if abs(lhs.qualityScore - rhs.qualityScore) > 0.000_001 {
                    return lhs.qualityScore > rhs.qualityScore
                }
                return lhs.representative.title.localizedCaseInsensitiveCompare(rhs.representative.title) == .orderedAscending
            }

        return Array(rankedClusters.prefix(limit).map(\.representative))
    }

    static func score(for cluster: [Manga], sourcePositions: [String: Int]) -> Double {
        rankingMetrics(for: cluster, sourcePositions: sourcePositions).score
    }

    private static func representative(from cluster: [Manga]) -> Manga? {
        let ranked = cluster.sorted {
            searchResultRank(for: $0) > searchResultRank(for: $1)
        }

        return ranked.first(where: { $0.coverURL != nil }) ?? ranked.first
    }

    private static func rankingMetrics(
        for cluster: [Manga],
        sourcePositions: [String: Int]
    ) -> (score: Double, supportingSourceCount: Int, bestPosition: Int, qualityScore: Double) {
        var bestByFamily: [String: (position: Int, sourceID: String)] = [:]

        for manga in cluster {
            guard let position = sourcePositions[rankingKey(for: manga)] else { continue }
            let family = NativeSourceCatalog.canonicalFamily(
                for: manga.sourceID,
                name: NativeSourceCatalog.displayName(for: manga.sourceID)
            )

            if let current = bestByFamily[family], current.position <= position {
                continue
            }

            bestByFamily[family] = (position: position, sourceID: manga.sourceID)
        }

        let qualityScore = cluster
            .map { searchResultRank(for: $0) }
            .max() ?? 0

        guard !bestByFamily.isEmpty else {
            return (
                score: qualityScore * 0.001,
                supportingSourceCount: Set(cluster.map(\.sourceID)).count,
                bestPosition: Int.max,
                qualityScore: qualityScore
            )
        }

        let reciprocalRankFusionScore = bestByFamily.values.reduce(0.0) { partialResult, candidate in
            let sourcePriority = SourcePerformanceStore.shared.priorityScore(for: candidate.sourceID)
            let confidenceWeight = min(max(sourcePriority / 60, 0.85), 1.10)
            return partialResult + (confidenceWeight / Double(25 + max(candidate.position, 1)))
        }

        return (
            score: reciprocalRankFusionScore,
            supportingSourceCount: bestByFamily.count,
            bestPosition: bestByFamily.values.map(\.position).min() ?? Int.max,
            qualityScore: qualityScore
        )
    }
}


private func rankingKey(for manga: Manga) -> String {
    "\(manga.sourceID)|\(manga.id)"
}


private func searchResultRank(for manga: Manga) -> Double {
    var score = SourcePerformanceStore.shared.priorityScore(for: manga.sourceID) * 10

    if NativeSourceCatalog.supportsReading(sourceID: manga.sourceID) {
        score += 1_000
    }

    score += Double(min(manga.chapters.count, 500)) * 3
    if manga.coverURL != nil { score += 45 }
    if manga.cleanSynopsis?.isEmpty == false { score += 20 }

    return score
}

private extension Manga {
    var normalizedSearchTitle: String {
        crossSourceTitleKey
    }

    var hasBadSearchTitle: Bool {
        let cleaned = title
            .removingYomuhonSourceMarkers
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if cleaned.isEmpty {
            return true
        }

        let badTitles: Set<String> = [
            "[cover]",
            "cover",
            "image",
            "no cover",
            "read more",
            "chapter",
            "chapters"
        ]

        if badTitles.contains(cleaned) {
            return true
        }

        return cleaned.range(of: #"^chapter\s*[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil
    }
}

private extension Array where Element: Hashable {
    func deduplicated() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}



struct SearchSourceFilter: Identifiable, Equatable {
    let id: String
    let title: String
}

/// Merges progressive per-source search results off the main actor so that
/// dedup/ranking work doesn't block the UI while results stream in from
/// multiple sources concurrently.
private actor SearchProcessor {
    struct SearchGroupsResult {
        let mangas: [Manga]
        let sourcePositions: [String: Int]
        let readableGroups: [MangaSearchGroup]
        let allGroups: [MangaSearchGroup]
        let catalogOnlyGroups: [MangaSearchGroup]
        let stableOrder: [String]
    }

    struct StabilizedDiscoveryResult {
        let mangas: [Manga]
        let order: [String]
    }

    // Every field below is only ever touched from inside this actor, so the
    // actor's own serial execution is what makes read-modify-write safe.
    //
    // Previously, each progressive search/discovery update spawned its own
    // Task that read `self.results` (a plain, non-isolated property on the
    // view model) directly, did some async work, and only later wrote the
    // merged value back on the main actor. With many sources finishing in a
    // tight burst, multiple of those Tasks were in flight at once, all
    // reading/merging/writing the same Array concurrently with no
    // synchronization between them — a real data race on Swift's Array
    // storage, and a plausible cause of the crash (lost updates at best,
    // memory corruption at worst). Keeping the canonical current state here,
    // behind the actor, means every ingest is processed one at a time in
    // order, with no possibility of two updates stepping on each other.
    private var searchGeneration = 0
    private var searchMangas: [Manga] = []
    private var searchPositions: [String: Int] = [:]
    private var searchStableOrder: [String] = []

    private var discoveryGeneration = 0
    private var discoveryMangas: [Manga] = []
    private var discoveryPositions: [String: Int] = [:]
    private var discoveryStableOrder: [String] = []

    private var genreGeneration = 0
    private var genreMangas: [Manga] = []
    private var genrePositions: [String: Int] = [:]
    private var genreStableOrder: [String] = []

    // MARK: - Search

    func beginSearchSession(generation: Int) {
        searchGeneration = generation
        searchMangas = []
        searchPositions = [:]
        searchStableOrder = []
    }

    /// Merges one source's results into the session state and rebuilds the
    /// display groups. Returns nil if `generation` is no longer the active
    /// session (a newer search started, or this one was cancelled) so the
    /// caller can simply discard a stale update instead of publishing it.
    func ingestSearchProgress(
        generation: Int,
        incoming: [Manga],
        progressSourceID: String,
        query: String
    ) -> SearchGroupsResult? {
        guard generation == searchGeneration else { return nil }

        searchMangas = Self.mergingSearchResults(current: searchMangas, incoming: incoming)
        searchPositions = Self.mergingSourcePositions(
            current: searchPositions,
            mangas: incoming,
            progressSourceID: progressSourceID
        )

        let groups = Self.buildGroups(
            from: searchMangas,
            query: query,
            sourcePositions: searchPositions,
            previousOrder: searchStableOrder,
            settle: false
        )
        searchStableOrder = groups.stableOrder

        return SearchGroupsResult(
            mangas: searchMangas,
            sourcePositions: searchPositions,
            readableGroups: groups.readableGroups,
            allGroups: groups.allGroups,
            catalogOnlyGroups: groups.catalogOnlyGroups,
            stableOrder: groups.stableOrder
        )
    }

    /// Final settle pass once the whole (possibly-cached) search result is in.
    func finalizeSearchSession(
        generation: Int,
        mangas: [Manga],
        query: String
    ) -> SearchGroupsResult? {
        guard generation == searchGeneration else { return nil }

        searchMangas = mangas
        let groups = Self.buildGroups(
            from: searchMangas,
            query: query,
            sourcePositions: searchPositions,
            previousOrder: searchStableOrder,
            settle: true
        )
        searchStableOrder = groups.stableOrder

        return SearchGroupsResult(
            mangas: searchMangas,
            sourcePositions: searchPositions,
            readableGroups: groups.readableGroups,
            allGroups: groups.allGroups,
            catalogOnlyGroups: groups.catalogOnlyGroups,
            stableOrder: groups.stableOrder
        )
    }

    // MARK: - Discovery (Popular)

    func beginDiscoverySession(generation: Int) {
        discoveryGeneration = generation
        discoveryMangas = []
        discoveryPositions = [:]
        discoveryStableOrder = []
    }

    func ingestDiscoveryProgress(
        generation: Int,
        incoming: [Manga],
        progressSourceID: String,
        limit: Int
    ) -> StabilizedDiscoveryResult? {
        guard generation == discoveryGeneration else { return nil }

        discoveryMangas = Self.mergingSearchResults(current: discoveryMangas, incoming: incoming)
        discoveryPositions = Self.mergingSourcePositions(
            current: discoveryPositions,
            mangas: incoming,
            progressSourceID: progressSourceID
        )

        let stabilized = Self.stabilizedDiscovery(
            from: discoveryMangas,
            limit: limit,
            sourcePositions: discoveryPositions,
            previousOrder: discoveryStableOrder,
            settle: false
        )
        discoveryStableOrder = stabilized.order
        return stabilized
    }

    func finalizeDiscoverySession(
        generation: Int,
        mangas: [Manga],
        limit: Int
    ) -> StabilizedDiscoveryResult? {
        guard generation == discoveryGeneration else { return nil }

        let stabilized = Self.stabilizedDiscovery(
            from: mangas,
            limit: limit,
            sourcePositions: discoveryPositions,
            previousOrder: discoveryStableOrder,
            settle: true
        )
        discoveryStableOrder = stabilized.order
        return stabilized
    }

    // MARK: - Genre

    func beginGenreSession(generation: Int) {
        genreGeneration = generation
        genreMangas = []
        genrePositions = [:]
        genreStableOrder = []
    }

    func ingestGenreProgress(
        generation: Int,
        incoming: [Manga],
        progressSourceID: String,
        limit: Int
    ) -> StabilizedDiscoveryResult? {
        guard generation == genreGeneration else { return nil }

        genreMangas = Self.mergingSearchResults(current: genreMangas, incoming: incoming)
        genrePositions = Self.mergingSourcePositions(
            current: genrePositions,
            mangas: incoming,
            progressSourceID: progressSourceID
        )

        let stabilized = Self.stabilizedDiscovery(
            from: genreMangas,
            limit: limit,
            sourcePositions: genrePositions,
            previousOrder: genreStableOrder,
            settle: false
        )
        genreStableOrder = stabilized.order
        return stabilized
    }

    func finalizeGenreSession(
        generation: Int,
        mangas: [Manga],
        limit: Int
    ) -> StabilizedDiscoveryResult? {
        guard generation == genreGeneration else { return nil }

        let stabilized = Self.stabilizedDiscovery(
            from: mangas,
            limit: limit,
            sourcePositions: genrePositions,
            previousOrder: genreStableOrder,
            settle: true
        )
        genreStableOrder = stabilized.order
        return stabilized
    }

    // MARK: - Pure helpers (no actor state; safe to call from anywhere in the file)

    // Clustering identical titles across sources (MangaIdentityResolver.clusters)
    // compares every result against every existing cluster, so its cost grows
    // with the size of `results`. This used to run — more than once, for the
    // readable list, the catalog-only list, and again just to compute a
    // stable order — synchronously on the main thread every time a source
    // finished responding *and* every time SwiftUI re-rendered the search
    // screen. As more sources returned results the app spent increasing
    // amounts of main-thread time reclustering the same ever-growing list
    // from scratch — feeling like the whole screen froze while "loading
    // other sources". Clustering once here, off the main actor, and handing
    // the view pre-built group lists means the main thread never reclusters.
    private static func buildGroups(
        from mangas: [Manga],
        query: String,
        sourcePositions: [String: Int],
        previousOrder: [String],
        settle: Bool
    ) -> (readableGroups: [MangaSearchGroup], allGroups: [MangaSearchGroup], catalogOnlyGroups: [MangaSearchGroup], stableOrder: [String]) {
        let clusters = MangaIdentityResolver.clusters(from: mangas.filter { !$0.hasBadSearchTitle })

        var readableGroups: [MangaSearchGroup] = []
        var allGroups: [MangaSearchGroup] = []
        var catalogOnlyGroups: [MangaSearchGroup] = []

        for cluster in clusters {
            let ranked = cluster.sorted { searchResultRank(for: $0) > searchResultRank(for: $1) }
            let key = MangaIdentityResolver.clusterKey(for: ranked)
            allGroups.append(MangaSearchGroup(id: key, mangas: ranked))

            let readableMembers = ranked.filter { NativeSourceCatalog.supportsReading(sourceID: $0.sourceID) }
            if readableMembers.isEmpty {
                catalogOnlyGroups.append(MangaSearchGroup(id: key, mangas: ranked))
            } else {
                readableGroups.append(MangaSearchGroup(id: key, mangas: readableMembers))
            }
        }

        let activeQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        func queryOrdered(_ groups: [MangaSearchGroup]) -> [MangaSearchGroup] {
            guard !activeQuery.isEmpty else {
                return groups.sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            }

            return groups.sorted { lhs, rhs in
                let lhsScore = SearchResultRanker.groupScore(query: activeQuery, mangas: lhs.mangas, sourcePositions: sourcePositions)
                let rhsScore = SearchResultRanker.groupScore(query: activeQuery, mangas: rhs.mangas, sourcePositions: sourcePositions)
                if abs(lhsScore - rhsScore) > 0.0001 { return lhsScore > rhsScore }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }

        let orderedReadable = queryOrdered(readableGroups)
        let orderedAll = queryOrdered(allGroups)
        let orderedCatalog = queryOrdered(catalogOnlyGroups)

        let scores = Dictionary(
            uniqueKeysWithValues: orderedReadable.map { group in
                (group.id, SearchResultRanker.groupScore(query: activeQuery, mangas: group.mangas, sourcePositions: sourcePositions))
            }
        )
        let dominantIDs = Set(scores.compactMap { entry in entry.value >= 9_000 ? entry.key : nil })

        let stableOrder = StableRankingReconciler.reconcile(
            previous: previousOrder,
            rankedIDs: orderedReadable.map(\.id),
            scores: scores,
            dominantIDs: dominantIDs,
            minimumPromotionDelta: 450,
            relativePromotionDelta: 0.04,
            settle: settle
        )

        func stableOrdered(_ groups: [MangaSearchGroup]) -> [MangaSearchGroup] {
            guard !stableOrder.isEmpty else { return groups }
            let stablePositions = Dictionary(uniqueKeysWithValues: stableOrder.enumerated().map { ($0.element, $0.offset) })
            let rankedPositions = Dictionary(uniqueKeysWithValues: groups.enumerated().map { ($0.element.id, $0.offset) })

            return groups.sorted { lhs, rhs in
                let lhsPosition = stablePositions[lhs.id] ?? rankedPositions[lhs.id] ?? Int.max
                let rhsPosition = stablePositions[rhs.id] ?? rankedPositions[rhs.id] ?? Int.max
                if lhsPosition != rhsPosition { return lhsPosition < rhsPosition }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }

        return (
            readableGroups: stableOrdered(orderedReadable),
            allGroups: stableOrdered(orderedAll),
            catalogOnlyGroups: stableOrdered(orderedCatalog),
            stableOrder: stableOrder
        )
    }

    private static func stabilizedDiscovery(
        from mangas: [Manga],
        limit: Int,
        sourcePositions: [String: Int],
        previousOrder: [String],
        settle: Bool
    ) -> StabilizedDiscoveryResult {
        let filtered = mangas.filter { !$0.hasBadSearchTitle }
        let clusters = MangaIdentityResolver.clusters(from: filtered)
        let ranked = DiscoveryRanker.rank(
            mangas: filtered,
            sourcePositions: sourcePositions,
            limit: limit
        )

        var representativeByID: [String: Manga] = [:]
        var scores: [String: Double] = [:]

        for cluster in clusters {
            guard let representative = DiscoveryRanker.rank(
                mangas: cluster,
                sourcePositions: sourcePositions,
                limit: 1
            ).first else {
                continue
            }

            let key = MangaIdentityResolver.clusterKey(for: cluster)
            representativeByID[key] = representative
            scores[key] = DiscoveryRanker.score(
                for: cluster,
                sourcePositions: sourcePositions
            )
        }

        let rankedIDs = ranked.map { manga -> String in
            let cluster = clusters.first { $0.contains { MangaIdentityResolver.sameWork($0, manga) } } ?? [manga]
            let key = MangaIdentityResolver.clusterKey(for: cluster)
            representativeByID[key] = manga
            return key
        }

        let order = StableRankingReconciler.reconcile(
            previous: previousOrder,
            rankedIDs: rankedIDs,
            scores: scores,
            dominantIDs: [],
            minimumPromotionDelta: 0.004,
            relativePromotionDelta: 0.18,
            settle: settle
        )

        return StabilizedDiscoveryResult(
            mangas: order.compactMap { representativeByID[$0] },
            order: order
        )
    }

    private static func mergingSearchResults(current: [Manga], incoming: [Manga]) -> [Manga] {
        var bestByKey: [String: Manga] = [:]

        for manga in current + incoming {
            let key = rankingKey(for: manga)

            guard let existing = bestByKey[key] else {
                bestByKey[key] = manga
                continue
            }

            if searchResultRank(for: manga) > searchResultRank(for: existing) {
                bestByKey[key] = manga
            }
        }

        return bestByKey.values.sorted {
            if $0.crossSourceTitleKey != $1.crossSourceTitleKey {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }

            return searchResultRank(for: $0) > searchResultRank(for: $1)
        }
    }

    private static func mergingSourcePositions(
        current: [String: Int],
        mangas: [Manga],
        progressSourceID: String
    ) -> [String: Int] {
        guard progressSourceID != "cache", progressSourceID != "all" else {
            return current
        }

        var positions = current
        for (index, manga) in mangas.enumerated() {
            let key = rankingKey(for: manga)
            let rank = index + 1
            if let existing = positions[key] {
                positions[key] = Swift.min(existing, rank)
            } else {
                positions[key] = rank
            }
        }

        return positions
    }
}
