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
    private var searchGeneration = 0
    private var discoveryGeneration = 0
    private var genreGeneration = 0
    private var activeSearchToken: RequestCancellationToken?
    private var activeDiscoveryToken: RequestCancellationToken?
    private var activeGenreToken: RequestCancellationToken?
    private var searchSourcePositions: [String: Int] = [:]
    private var popularSourcePositions: [String: Int] = [:]
    private var genreSourcePositions: [String: Int] = [:]
    private var stableSearchGroupOrder: [String] = []
    private var popularStableOrder: [String] = []
    private var genreStableOrder: [String] = []

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
        readableGroupedResults
    }

    var readableGroupedResults: [MangaSearchGroup] {
        groupedMangas(
            from: results.filter { NativeSourceCatalog.supportsReading(sourceID: $0.sourceID) }
        )
    }

    var catalogOnlyGroupedResults: [MangaSearchGroup] {
        let readableGroups = readableGroupedResults
        let catalogGroups = groupedMangas(
            from: results.filter { manga in
                !NativeSourceCatalog.supportsReading(sourceID: manga.sourceID)
            }
        )

        return catalogGroups.filter { catalogGroup in
            guard let catalogManga = catalogGroup.primaryManga else { return false }
            return !readableGroups.contains { readableGroup in
                guard let readableManga = readableGroup.primaryManga else { return false }
                return MangaIdentityResolver.sameWork(catalogManga, readableManga)
            }
        }
    }

    var hasCatalogOnlyResults: Bool {
        !catalogOnlyGroupedResults.isEmpty
    }

    var availableSearchSourceFilters: [SearchSourceFilter] {
        let sourceIDs = Set(results.map(\.sourceID))
        let filters = sourceIDs
            .sorted { NativeSourceCatalog.displayName(for: $0) < NativeSourceCatalog.displayName(for: $1) }
            .map { SearchSourceFilter(id: $0, title: NativeSourceCatalog.displayName(for: $0)) }

        return [SearchSourceFilter(id: "all", title: String(localized: "search.filter.allSources"))] + filters
    }

    var activeReadableGroups: [MangaSearchGroup] {
        let groups = onlyReadableResults ? readableGroupedResults : groupedMangas(from: results)
        guard selectedSearchSourceID != "all" else {
            return groups
        }

        return groups.filter { group in
            group.sourceIDs.contains(selectedSearchSourceID)
        }
    }

    private func groupedMangas(from mangas: [Manga]) -> [MangaSearchGroup] {
        let ranked = rankedMangaGroups(from: mangas)
        guard !stableSearchGroupOrder.isEmpty else { return ranked }

        let stablePositions = Dictionary(
            uniqueKeysWithValues: stableSearchGroupOrder.enumerated().map { ($0.element, $0.offset) }
        )
        let rankedPositions = Dictionary(
            uniqueKeysWithValues: ranked.enumerated().map { ($0.element.id, $0.offset) }
        )

        return ranked.sorted { lhs, rhs in
            let lhsPosition = stablePositions[lhs.id] ?? rankedPositions[lhs.id] ?? Int.max
            let rhsPosition = stablePositions[rhs.id] ?? rankedPositions[rhs.id] ?? Int.max
            if lhsPosition != rhsPosition { return lhsPosition < rhsPosition }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func rankedMangaGroups(from mangas: [Manga]) -> [MangaSearchGroup] {
        let groups = MangaIdentityResolver
            .clusters(from: mangas.filter { !$0.hasBadSearchTitle })
            .map { mangas in
                let ranked = mangas.sorted {
                    searchResultRank(for: $0) > searchResultRank(for: $1)
                }
                return MangaSearchGroup(
                    id: MangaIdentityResolver.clusterKey(for: ranked),
                    mangas: ranked
                )
            }

        let activeQuery = trimmedQuery
        guard !activeQuery.isEmpty else {
            return groups.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }

        return groups.sorted { lhs, rhs in
            let lhsScore = SearchResultRanker.groupScore(
                query: activeQuery,
                mangas: lhs.mangas,
                sourcePositions: searchSourcePositions
            )
            let rhsScore = SearchResultRanker.groupScore(
                query: activeQuery,
                mangas: rhs.mangas,
                sourcePositions: searchSourcePositions
            )

            if abs(lhsScore - rhsScore) > 0.0001 {
                return lhsScore > rhsScore
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func reconcileSearchOrder(query: String, settle: Bool) {
        let ranked = rankedMangaGroups(from: results)
        let scores = Dictionary(
            uniqueKeysWithValues: ranked.map { group in
                (
                    group.id,
                    SearchResultRanker.groupScore(
                        query: query,
                        mangas: group.mangas,
                        sourcePositions: searchSourcePositions
                    )
                )
            }
        )
        let dominantIDs = Set(scores.compactMap { entry in
            entry.value >= 9_000 ? entry.key : nil
        })

        stableSearchGroupOrder = StableRankingReconciler.reconcile(
            previous: stableSearchGroupOrder,
            rankedIDs: ranked.map(\.id),
            scores: scores,
            dominantIDs: dominantIDs,
            minimumPromotionDelta: 450,
            relativePromotionDelta: 0.04,
            settle: settle
        )
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

        popularSourcePositions = [:]
        popularStableOrder = []
        isLoadingDiscovery = true

        DispatchQueue.global(qos: .utility).async {
            let popularResult = Result {
                try useCase.popularManga(cancellationToken: cancellationToken) { progress in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, generation == self.discoveryGeneration else {
                            return
                        }

                        self.popularSourcePositions = Self.mergingSourcePositions(
                            current: self.popularSourcePositions,
                            mangas: progress.mangas,
                            progressSourceID: progress.sourceID
                        )
                        let merged = self.mergingSearchResults(
                            current: self.popularMangas,
                            incoming: progress.mangas
                        )
                        let stabilized = self.stabilizedDiscoveryMangas(
                            from: merged,
                            limit: 12,
                            sourcePositions: self.popularSourcePositions,
                            previousOrder: self.popularStableOrder,
                            settle: false
                        )
                        self.popularMangas = stabilized.mangas
                        self.popularStableOrder = stabilized.order
                    }
                }
            }


            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.discoveryGeneration else {
                    return
                }

                if case .success(let mangas) = popularResult {
                    let stabilized = self.stabilizedDiscoveryMangas(
                        from: mangas,
                        limit: 12,
                        sourcePositions: self.popularSourcePositions,
                        previousOrder: self.popularStableOrder,
                        settle: true
                    )
                    self.popularMangas = stabilized.mangas
                    self.popularStableOrder = stabilized.order
                    self.logDiscoveryRanking(kind: "POPULAR", mangas: self.popularMangas)
                }

                self.activeDiscoveryToken = nil
                self.isLoadingDiscovery = false
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
        popularSourcePositions = [:]
        popularStableOrder = []
        discoveryGenres = []
        selectedGenre = nil
        genreMangas = []
        genreSourcePositions = [:]
        genreStableOrder = []
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
        genreSourcePositions = [:]
        genreStableOrder = []
        isLoadingGenre = true

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try useCase.manga(
                    forGenreID: genre.id,
                    cancellationToken: cancellationToken
                ) { progress in
                    DispatchQueue.main.async { [weak self] in
                        guard let self,
                              generation == self.genreGeneration,
                              self.selectedGenre?.id == genre.id
                        else {
                            return
                        }

                        self.genreSourcePositions = Self.mergingSourcePositions(
                            current: self.genreSourcePositions,
                            mangas: progress.mangas,
                            progressSourceID: progress.sourceID
                        )
                        let merged = self.mergingSearchResults(
                            current: self.genreMangas,
                            incoming: progress.mangas
                        )
                        let stabilized = self.stabilizedDiscoveryMangas(
                            from: merged,
                            limit: 24,
                            sourcePositions: self.genreSourcePositions,
                            previousOrder: self.genreStableOrder,
                            settle: false
                        )
                        self.genreMangas = stabilized.mangas
                        self.genreStableOrder = stabilized.order
                    }
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      generation == self.genreGeneration,
                      self.selectedGenre?.id == genre.id
                else {
                    return
                }

                if case .success(let mangas) = result {
                    let stabilized = self.stabilizedDiscoveryMangas(
                        from: mangas,
                        limit: 24,
                        sourcePositions: self.genreSourcePositions,
                        previousOrder: self.genreStableOrder,
                        settle: true
                    )
                    self.genreMangas = stabilized.mangas
                    self.genreStableOrder = stabilized.order
                    self.logDiscoveryRanking(kind: "GENRE:\(genre.id)", mangas: self.genreMangas)
                }
                self.activeGenreToken = nil
                self.isLoadingGenre = false
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
        searchSourcePositions = [:]
        stableSearchGroupOrder = []
        completedSourceCount = 0
        totalSourceCount = 0
        isSearching = true
        hasSearched = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try useCase.execute(
                    query: currentQuery,
                    cancellationToken: cancellationToken
                ) { progress in
                    guard !cancellationToken.isCancelled else { return }

                    DispatchQueue.main.async { [weak self] in
                        guard let self,
                              generation == self.searchGeneration,
                              !cancellationToken.isCancelled
                        else {
                            return
                        }

                        self.searchSourcePositions = Self.mergingSourcePositions(
                            current: self.searchSourcePositions,
                            mangas: progress.mangas,
                            progressSourceID: progress.sourceID
                        )
                        self.completedSourceCount = progress.completedSourceCount
                        self.totalSourceCount = progress.totalSourceCount
                        self.results = self.mergingSearchResults(
                            current: self.results,
                            incoming: progress.mangas
                        )
                        self.reconcileSearchOrder(query: currentQuery, settle: false)
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
                    self.results = mangas
                    self.reconcileSearchOrder(query: currentQuery, settle: true)
                    self.errorMessage = nil
                    self.logSearchRanking(query: currentQuery)
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
        searchSourcePositions = [:]
        stableSearchGroupOrder = []
        completedSourceCount = 0
        totalSourceCount = 0
        errorMessage = nil
        hasSearched = false
    }

    private func mergingSearchResults(current: [Manga], incoming: [Manga]) -> [Manga] {
        var bestByKey: [String: Manga] = [:]

        for manga in current + incoming {
            let key = "\(manga.sourceID)|\(manga.id)"

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

    private func stabilizedDiscoveryMangas(
        from mangas: [Manga],
        limit: Int,
        sourcePositions: [String: Int],
        previousOrder: [String],
        settle: Bool
    ) -> (mangas: [Manga], order: [String]) {
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

        return (
            order.compactMap { representativeByID[$0] },
            order
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
        let top = groupedMangas(from: results)
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

    private static func canonicalTokens(for title: String) -> [String] {
        let normalized = title
            .removingTrailingSourceNumericIdentifier
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let rawTokens = normalized.split(separator: " ").map(String.init)
        guard rawTokens.count > 2 else { return rawTokens }
        return rawTokens.filter { !ignorableDescriptorTokens.contains($0) }
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
