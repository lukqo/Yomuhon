import Foundation

//
//  SourceRepositoryImpl.swift
//  Yomuhon
//

struct SourceRepositoryImpl: ProgressiveSourceRepository, ProgressiveDiscoveryRepository {
    private let nativeSources: [Source]
    private let settingsStore: SourceSettingsStore
    private let metadataEnrichmentService: MangaMetadataEnrichmentService
    private let includesRemoteDeclarativeSources: Bool
    private let intakePipeline = MangaIntakePipeline()
    private let searchCache = SourceSearchCache.shared
    private let contentCache = SourceContentCache.shared
    private let performanceStore = SourcePerformanceStore.shared
    private let metricsStore = SourceMetricsStore.shared
    private let queryScheduler = SourceQueryScheduler.shared

    static var defaultSources: [Source] {
        // Production sources are discovered exclusively from Yomuhon-Sources.
        // The app ships runtimes, never provider adapters.
        []
    }


    init(
        sources: [Source]? = nil,
        settingsStore: SourceSettingsStore = .shared,
        metadataEnrichmentService: MangaMetadataEnrichmentService = MangaMetadataEnrichmentService()
    ) {
        if let sources {
            self.nativeSources = sources
            self.includesRemoteDeclarativeSources = false
        } else {
            self.nativeSources = Self.defaultSources
            self.includesRemoteDeclarativeSources = true
        }
        self.settingsStore = settingsStore
        self.metadataEnrichmentService = metadataEnrichmentService
    }

    func availableSources() -> [Source] {
        // The GitHub index is the source of truth for discovery. A published
        // stable/testing definition is immediately usable; diagnostics are debug
        // observations and never gate Search. Repeated real runtime failures are
        // isolated temporarily by the circuit breaker.
        var seen = Set<String>()
        let dynamicSources = nativeSources + discoverableDeclarativeSources()

        return dynamicSources
            .filter { !SourceRuntimeCircuitBreaker.shared.shouldSkip(sourceID: $0.id) }
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                let lhsTrust = NativeSourceCatalog.automaticSelectionTrustRank(for: lhs.id)
                let rhsTrust = NativeSourceCatalog.automaticSelectionTrustRank(for: rhs.id)
                if lhsTrust != rhsTrust { return lhsTrust > rhsTrust }

                let lhsScore = queryScheduler.priorityScore(for: lhs.id, operation: .search)
                let rhsScore = queryScheduler.priorityScore(for: rhs.id, operation: .search)
                if abs(lhsScore - rhsScore) > 0.000_001 { return lhsScore > rhsScore }

                return performanceStore.priorityScore(for: lhs.id) > performanceStore.priorityScore(for: rhs.id)
            }
    }

    private func allResolvableSources() -> [Source] {
        // Detail/reader resolution intentionally ignores temporary health state.
        // A Manga obtained from Search must keep resolving to the exact source
        // config that produced its canonical URL.
        var seen = Set<String>()
        let dynamicSources = nativeSources + discoverableDeclarativeSources()
        return dynamicSources.filter { seen.insert($0.id).inserted }
    }

    private func discoverableDeclarativeSources() -> [Source] {
        guard includesRemoteDeclarativeSources else { return [] }
        return DeclarativeRemoteConfigLoader.availableConfigs()
            .map { DeclarativeSourceRuntime(config: $0) }
    }

    func availableDiscoveryGenres() -> [SourceDiscoveryGenre] {
        let compatibleSources = availableSources().filter { $0.supportsGenreDiscovery }
        var bestByID: [String: SourceDiscoveryGenre] = [:]

        for genre in compatibleSources.flatMap(\.discoveryGenres) {
            let normalizedID = genre.id
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalizedID.isEmpty else { continue }

            if bestByID[normalizedID] == nil {
                bestByID[normalizedID] = SourceDiscoveryGenre(
                    id: normalizedID,
                    title: genre.title
                )
            }
        }

        return bestByID.values.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    func popularManga() throws -> [Manga] {
        try popularManga(
            cancellationToken: RequestCancellationToken(),
            progress: { _ in }
        )
    }

    func popularManga(
        progress: @escaping (SourceDiscoveryProgress) -> Void
    ) throws -> [Manga] {
        try popularManga(
            cancellationToken: RequestCancellationToken(),
            progress: progress
        )
    }

    func popularManga(
        cancellationToken: RequestCancellationToken,
        progress: @escaping (SourceDiscoveryProgress) -> Void
    ) throws -> [Manga] {
        let sources = availableSources().filter { $0.supportsPopularDiscovery }
        guard !sources.isEmpty else { return [] }

        return try executeDiscovery(
            sources: sources,
            cancellationToken: cancellationToken,
            progress: progress
        ) { source in
            try source.popularManga()
        }
    }

    func manga(forGenreID genreID: String) throws -> [Manga] {
        try manga(
            forGenreID: genreID,
            cancellationToken: RequestCancellationToken(),
            progress: { _ in }
        )
    }

    func manga(
        forGenreID genreID: String,
        progress: @escaping (SourceDiscoveryProgress) -> Void
    ) throws -> [Manga] {
        try manga(
            forGenreID: genreID,
            cancellationToken: RequestCancellationToken(),
            progress: progress
        )
    }

    func manga(
        forGenreID genreID: String,
        cancellationToken: RequestCancellationToken,
        progress: @escaping (SourceDiscoveryProgress) -> Void
    ) throws -> [Manga] {
        let sources = availableSources().filter { source in
            source.supportsGenreDiscovery
                && source.discoveryGenres.contains(where: { $0.id == genreID })
        }
        guard !sources.isEmpty else { return [] }

        return try executeDiscovery(
            sources: sources,
            cancellationToken: cancellationToken,
            progress: progress
        ) { source in
            try source.manga(forGenreID: genreID)
        }
    }

    private func executeDiscovery(
        sources: [Source],
        cancellationToken: RequestCancellationToken,
        progress: @escaping (SourceDiscoveryProgress) -> Void,
        operation: @escaping (Source) throws -> [Manga]
    ) throws -> [Manga] {
        guard !cancellationToken.isCancelled else {
            throw HTTPClientError.cancelled
        }

        let scheduledSources = queryScheduler.orderedSources(sources, operation: .discovery)
        let queue = queryScheduler.makeQueue(
            qualityOfService: .utility,
            sourceCount: scheduledSources.count
        )
        SourceDebugTrace.log(
            "Scheduler",
            "operation=discovery maxConcurrent=\(queue.maxConcurrentOperationCount) order=\(scheduledSources.map { $0.id })"
        )

        let accumulator = SourceOperationAccumulator()
        let completionGroup = DispatchGroup()

        for (index, source) in scheduledSources.enumerated() {
            completionGroup.enter()

            let sourceOperation = BlockOperation {
                defer { completionGroup.leave() }
                guard !cancellationToken.isCancelled else { return }

                let startedAt = Date()

                do {
                    let mangas = try queryScheduler.withExecutionSlot(
                        priority: .background,
                        cancellationToken: cancellationToken
                    ) {
                        try SourceRuntimeActivityCenter.shared.withInteractiveActivity {
                            try SourceRequestPriorityContext.withPriority(.interactive) {
                                try HTTPRequestCancellationContext.withToken(cancellationToken) {
                                    try operation(source)
                                }
                            }
                        }
                    }

                    guard !cancellationToken.isCancelled else { return }

                    let normalized = intakePipeline.normalizeSearchResults(mangas)
                    let completed = accumulator.appendAndComplete(normalized)

                    let latency = Date().timeIntervalSince(startedAt)
                    performanceStore.recordSuccess(
                        sourceID: source.id,
                        latency: latency
                    )
                    metricsStore.recordSuccess(
                        sourceID: source.id,
                        operation: .discovery,
                        latency: latency
                    )
                    SourceRuntimeCircuitBreaker.shared.recordSuccess(sourceID: source.id)

                    progress(
                        SourceDiscoveryProgress(
                            sourceID: source.id,
                            mangas: normalized,
                            completedSourceCount: completed,
                            totalSourceCount: scheduledSources.count
                        )
                    )
                } catch {
                    let completed = accumulator.recordAndComplete(error: error)

                    guard !cancellationToken.isCancelled else { return }

                    if Self.shouldRecordSourceFailure(error) {
                        performanceStore.recordFailure(sourceID: source.id)
                        metricsStore.recordFailure(sourceID: source.id, operation: .discovery)
                        SourceRuntimeCircuitBreaker.shared.recordFailure(sourceID: source.id)
                    }

                    progress(
                        SourceDiscoveryProgress(
                            sourceID: source.id,
                            mangas: [],
                            completedSourceCount: completed,
                            totalSourceCount: scheduledSources.count
                        )
                    )
                }
            }
            sourceOperation.queuePriority = queryScheduler.queuePriority(for: index)
            queue.addOperation(sourceOperation)
        }

        while completionGroup.wait(timeout: .now() + 0.08) != .success {
            if cancellationToken.isCancelled {
                queue.cancelAllOperations()
                throw HTTPClientError.cancelled
            }
        }

        if cancellationToken.isCancelled {
            queue.cancelAllOperations()
            throw HTTPClientError.cancelled
        }

        let snapshot = accumulator.snapshot()
        let results = intakePipeline.normalizeSearchResults(snapshot.mangas)

        if results.isEmpty, let firstError = snapshot.firstError {
            throw firstError
        }

        return results
    }

    func searchManga(query: String) throws -> [Manga] {
        let token = RequestCancellationToken()
        return try searchManga(query: query, cancellationToken: token) { _ in }
    }

    func searchManga(
        query: String,
        cancellationToken: RequestCancellationToken,
        progress: @escaping (SourceSearchProgress) -> Void
    ) throws -> [Manga] {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        guard !normalizedQuery.isEmpty else { return [] }

        let sources = queryScheduler.orderedSources(availableSources(), operation: .search)
        guard !sources.isEmpty else { return [] }

        if let cached = searchCache.value(for: normalizedQuery) {
            let availableSourceIDs = Set(sources.map(\.id))
            let filteredCache = cached.filter { availableSourceIDs.contains($0.sourceID) }

            if !filteredCache.isEmpty {
                for (index, source) in sources.enumerated() {
                    progress(
                        SourceSearchProgress(
                            sourceID: source.id,
                            mangas: filteredCache.filter { $0.sourceID == source.id },
                            completedSourceCount: index + 1,
                            totalSourceCount: sources.count
                        )
                    )
                }
                return filteredCache
            }
        }

        let operationQueue = queryScheduler.makeQueue(
            qualityOfService: .userInitiated,
            sourceCount: sources.count
        )
        SourceDebugTrace.log(
            "Scheduler",
            "operation=search maxConcurrent=\(operationQueue.maxConcurrentOperationCount) order=\(sources.map { $0.id })"
        )

        let accumulator = SourceOperationAccumulator()
        let completionGroup = DispatchGroup()

        for (index, source) in sources.enumerated() {
            completionGroup.enter()

            let sourceOperation = BlockOperation {
                defer { completionGroup.leave() }

                guard !cancellationToken.isCancelled else { return }
                let startedAt = Date()

                do {
                    let sourceResults = try queryScheduler.withExecutionSlot(
                        priority: .interactive,
                        cancellationToken: cancellationToken
                    ) {
                        try SourceRuntimeActivityCenter.shared.withInteractiveActivity {
                            try SourceRequestPriorityContext.withPriority(.interactive) {
                                try HTTPRequestCancellationContext.withToken(cancellationToken) {
                                    try source.searchManga(query: query)
                                }
                            }
                        }
                    }

                    guard !cancellationToken.isCancelled else { return }
                    let normalized = intakePipeline.normalizeSearchResults(sourceResults)

                    let completedSnapshot = accumulator.appendAndComplete(normalized)

                    let latency = Date().timeIntervalSince(startedAt)
                    performanceStore.recordSuccess(
                        sourceID: source.id,
                        latency: latency
                    )
                    metricsStore.recordSuccess(
                        sourceID: source.id,
                        operation: .search,
                        latency: latency
                    )
                    SourceRuntimeCircuitBreaker.shared.recordSuccess(sourceID: source.id)

                    progress(
                        SourceSearchProgress(
                            sourceID: source.id,
                            mangas: normalized,
                            completedSourceCount: completedSnapshot,
                            totalSourceCount: sources.count
                        )
                    )
                } catch {
                    let completedSnapshot = accumulator.recordAndComplete(error: error)

                    if !cancellationToken.isCancelled {
                        if Self.shouldRecordSourceFailure(error) {
                            performanceStore.recordFailure(sourceID: source.id)
                            metricsStore.recordFailure(sourceID: source.id, operation: .search)
                            SourceRuntimeCircuitBreaker.shared.recordFailure(sourceID: source.id)
                        }

                        progress(
                            SourceSearchProgress(
                                sourceID: source.id,
                                mangas: [],
                                completedSourceCount: completedSnapshot,
                                totalSourceCount: sources.count
                            )
                        )
                    }
                }
            }
            sourceOperation.queuePriority = queryScheduler.queuePriority(for: index)
            operationQueue.addOperation(sourceOperation)
        }

        while completionGroup.wait(timeout: .now() + 0.08) != .success {
            if cancellationToken.isCancelled {
                operationQueue.cancelAllOperations()
                throw HTTPClientError.cancelled
            }
        }

        if cancellationToken.isCancelled {
            operationQueue.cancelAllOperations()
            throw HTTPClientError.cancelled
        }

        let snapshot = accumulator.snapshot()
        let finalResults = intakePipeline.normalizeSearchResults(snapshot.mangas)

        if finalResults.isEmpty, let firstError = snapshot.firstError {
            throw firstError
        }

        searchCache.set(finalResults, for: normalizedQuery)
        return finalResults
    }

    func fetchDetails(for manga: Manga) throws -> Manga {
        if let cached = contentCache.detail(for: manga) {
            SourceDebugTrace.log("Repository", "DETAIL cache hit source=\(manga.sourceID) chapters=\(cached.chapters.count)")
            return cached
        }

        SourceDebugTrace.log(
            "Repository",
            "DETAIL resolve sourceID=\(manga.sourceID) mangaID=\(manga.id) marker=\(manga.declarativeSourceURL?.absoluteString ?? "nil") available=\(allResolvableSources().map { $0.id })"
        )
        guard let source = source(for: manga) else {
            throw SourceRepositoryError.sourceUnavailable(manga.sourceID)
        }

        let startedAt = Date()
        let candidate = repairLegacyMangaIfNeeded(manga, using: source)

        do {
            SourceDebugTrace.log("Repository", "DETAIL using source=\(source.id) candidateMarker=\(candidate.declarativeSourceURL?.absoluteString ?? "nil")")
            let detailed = try SourceRuntimeActivityCenter.shared.withInteractiveActivity {
                try SourceRequestPriorityContext.withPriority(.interactive) {
                    try source.fetchDetails(for: candidate)
                }
            }

            guard !detailed.chapters.isEmpty else {
                throw SourceRepositoryError.noChapters
            }

            let latency = Date().timeIntervalSince(startedAt)
            performanceStore.recordSuccess(
                sourceID: source.id,
                latency: latency
            )
            metricsStore.recordSuccess(
                sourceID: source.id,
                operation: .detail,
                latency: latency
            )
            SourceRuntimeCircuitBreaker.shared.recordSuccess(sourceID: source.id)
            let normalizedDetail = intakePipeline.normalizeDetail(detailed)
            contentCache.setDetail(normalizedDetail, for: manga)
            SourceDebugTrace.log("Repository", "DETAIL success source=\(source.id) chapters=\(normalizedDetail.chapters.count)")
            return normalizedDetail
        } catch {
            if Self.shouldRecordSourceFailure(error) {
                performanceStore.recordFailure(sourceID: source.id)
                metricsStore.recordFailure(sourceID: source.id, operation: .detail)
                SourceRuntimeCircuitBreaker.shared.recordFailure(sourceID: source.id)
            }
            SourceDebugTrace.log("Repository", "DETAIL failure source=\(source.id) error=\(String(describing: error))")
            throw error
        }
    }

    func fetchChapters(for manga: Manga) throws -> [Chapter] {
        if let cached = contentCache.detail(for: manga), !cached.chapters.isEmpty {
            return cached.chapters
        }

        guard let source = source(for: manga) else {
            throw SourceRepositoryError.sourceUnavailable(manga.sourceID)
        }

        let startedAt = Date()
        do {
            let chapters = try SourceRuntimeActivityCenter.shared.withInteractiveActivity {
                try SourceRequestPriorityContext.withPriority(.interactive) {
                    try source.fetchChapters(for: manga)
                }
            }

            metricsStore.recordSuccess(
                sourceID: source.id,
                operation: .chapters,
                latency: Date().timeIntervalSince(startedAt)
            )

            if !chapters.isEmpty {
                var detailed = manga
                detailed.chapters = chapters
                contentCache.setDetail(intakePipeline.normalizeDetail(detailed), for: manga)
            }
            return chapters
        } catch {
            if Self.shouldRecordSourceFailure(error) {
                metricsStore.recordFailure(sourceID: source.id, operation: .chapters)
            }
            throw error
        }
    }

    func fetchPages(for chapter: Chapter, manga: Manga) throws -> [Page] {
        if let cached = contentCache.pages(for: chapter, manga: manga) {
            SourceDebugTrace.log(
                "Pages",
                "repository cacheHit source=\(manga.sourceID) manga=\(manga.id) chapter=\(chapter.id) count=\(cached.count)"
            )
            return cached
        }

        guard let source = source(for: manga) else {
            SourceDebugTrace.log(
                "Pages",
                "repository sourceUnavailable source=\(manga.sourceID) manga=\(manga.id) chapter=\(chapter.id)"
            )
            throw SourceRepositoryError.sourceUnavailable(manga.sourceID)
        }

        let chapterURL = chapter.declarativeSourceURL?.absoluteString ?? "nil"
        SourceDebugTrace.log(
            "Pages",
            "repository START source=\(source.id) manga=\(manga.id) chapter=\(chapter.id) number=\(chapter.number) chapterURL=\(chapterURL)"
        )

        let startedAt = Date()
        do {
            let pages = try SourceRuntimeActivityCenter.shared.withInteractiveActivity {
                try SourceRequestPriorityContext.withPriority(.interactive) {
                    try source.fetchPages(for: chapter, manga: manga)
                }
            }

            metricsStore.recordSuccess(
                sourceID: source.id,
                operation: .pages,
                latency: Date().timeIntervalSince(startedAt)
            )
            contentCache.setPages(pages, for: chapter, manga: manga)
            SourceDebugTrace.log(
                "Pages",
                "repository SUCCESS source=\(source.id) manga=\(manga.id) chapter=\(chapter.id) count=\(pages.count) elapsed=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))s"
            )
            return pages
        } catch {
            if Self.shouldRecordSourceFailure(error) {
                metricsStore.recordFailure(sourceID: source.id, operation: .pages)
            }
            SourceDebugTrace.log(
                "Pages",
                "repository FAILURE source=\(source.id) manga=\(manga.id) chapter=\(chapter.id) chapterURL=\(chapterURL) error=\(String(describing: error)) elapsed=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))s"
            )
            throw error
        }
    }

    private func repairLegacyMangaIfNeeded(_ manga: Manga, using source: Source) -> Manga {
        let legacySourceIDs: Set<String> = ["mangapill", "mangakatana"]

        guard legacySourceIDs.contains(manga.sourceID),
              manga.hasYomuhonSourceURLMarker == false,
              let repaired = repairMangaFromSearch(manga, using: source)
        else {
            return manga
        }

        return repaired
    }

    private func repairMangaFromSearch(_ manga: Manga, using source: Source) -> Manga? {
        let candidates = (try? source.searchManga(query: manga.title)) ?? []

        guard let candidate = candidates.bestRepairCandidate(for: manga) else {
            return nil
        }

        return candidate.mergingRepairData(from: manga)
    }

    private static func shouldRecordSourceFailure(_ error: Error) -> Bool {
        guard let clientError = error as? HTTPClientError else {
            return true
        }
        return !clientError.isCancellation
    }

    private func source(for manga: Manga) -> Source? {
        let sources = allResolvableSources()

        if let exact = sources.first(where: { $0.id == manga.sourceID }) {
            return exact
        }

        let repositorySourceID: String?
        switch manga.sourceID.lowercased() {
        case "mangapill":
            repositorySourceID = "mangapill_json"
        case "mangakatana":
            repositorySourceID = "mangakatana_json"
        default:
            repositorySourceID = nil
        }

        guard let repositorySourceID else { return nil }
        return sources.first(where: { $0.id == repositorySourceID })
    }
}


private enum SourceRepositoryError: LocalizedError {
    case noChapters
    case sourceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noChapters:
            return "The selected source returned no chapters."
        case .sourceUnavailable(let sourceID):
            return "The source \(sourceID) is not available in the current source catalog."
        }
    }
}

final class SourceRuntimeCircuitBreaker {
    static let shared = SourceRuntimeCircuitBreaker()

    private struct FailureState {
        var count: Int
        var lastFailure: Date?
        var blockedUntil: Date?
    }

    private let lock = NSLock()
    private let defaults = UserDefaults.standard
    private let persistenceKey = "yomuhon.sourceRuntimeCircuitBreaker.v1"
    private var failures: [String: FailureState]
    private let failureThreshold = 2
    private let failureWindow: TimeInterval = 10 * 60
    private let cooldown: TimeInterval = 5 * 60

    private init() {
        let persisted = defaults.dictionary(forKey: persistenceKey) ?? [:]
        var restored: [String: FailureState] = [:]

        for (sourceID, rawValue) in persisted {
            guard let dictionary = rawValue as? [String: Any] else { continue }
            let count = (dictionary["count"] as? NSNumber)?.intValue ?? 0
            let lastFailureTimestamp = (dictionary["lastFailure"] as? NSNumber)?.doubleValue ?? 0
            let lastFailure = lastFailureTimestamp > 0 ? Date(timeIntervalSince1970: lastFailureTimestamp) : nil
            let blockedTimestamp = (dictionary["blockedUntil"] as? NSNumber)?.doubleValue ?? 0
            let blockedUntil = blockedTimestamp > 0 ? Date(timeIntervalSince1970: blockedTimestamp) : nil

            if let blockedUntil, blockedUntil > Date() {
                restored[sourceID] = FailureState(count: count, lastFailure: lastFailure, blockedUntil: blockedUntil)
            } else if let lastFailure, Date().timeIntervalSince(lastFailure) <= failureWindow {
                restored[sourceID] = FailureState(count: count, lastFailure: lastFailure, blockedUntil: nil)
            }
        }

        failures = restored
    }

    func shouldSkip(sourceID: String) -> Bool {
        lock.lock()
        guard let state = failures[sourceID], let blockedUntil = state.blockedUntil else {
            lock.unlock()
            return false
        }

        if blockedUntil <= Date() {
            failures.removeValue(forKey: sourceID)
            persistLocked()
            lock.unlock()
            SourceDebugTrace.log("Circuit", "source=\(sourceID) cooldown expired")
            notifyAvailabilityChanged()
            return false
        }

        lock.unlock()
        return true
    }

    func recordSuccess(sourceID: String) {
        lock.lock()
        let changed = failures.removeValue(forKey: sourceID) != nil
        if changed {
            persistLocked()
        }
        lock.unlock()

        if changed {
            SourceDebugTrace.log("Circuit", "source=\(sourceID) recovered")
            notifyAvailabilityChanged()
        }
    }

    func recordFailure(sourceID: String) {
        lock.lock()
        let now = Date()
        let wasBlocked = failures[sourceID]?.blockedUntil.map { $0 > now } ?? false
        var state = failures[sourceID] ?? FailureState(count: 0, lastFailure: nil, blockedUntil: nil)

        if let lastFailure = state.lastFailure,
           now.timeIntervalSince(lastFailure) > failureWindow {
            state.count = 0
            state.blockedUntil = nil
        }

        state.count += 1
        state.lastFailure = now
        if state.count >= failureThreshold {
            state.blockedUntil = now.addingTimeInterval(cooldown)
        }
        failures[sourceID] = state
        persistLocked()
        let isBlocked = state.blockedUntil.map { $0 > Date() } ?? false
        lock.unlock()

        if !wasBlocked && isBlocked {
            SourceDebugTrace.log("Circuit", "source=\(sourceID) blocked for \(Int(cooldown))s after \(state.count) failures")
        }

        if wasBlocked != isBlocked {
            notifyAvailabilityChanged()
        }
    }

    private func persistLocked() {
        var payload: [String: [String: Any]] = [:]
        for (sourceID, state) in failures {
            payload[sourceID] = [
                "count": state.count,
                "lastFailure": state.lastFailure?.timeIntervalSince1970 ?? 0,
                "blockedUntil": state.blockedUntil?.timeIntervalSince1970 ?? 0
            ]
        }
        defaults.set(payload, forKey: persistenceKey)
    }

    private func notifyAvailabilityChanged() {
        NotificationCenter.default.post(
            name: .yomuhonSourceAvailabilityDidChange,
            object: self
        )
    }
}


// MARK: - Search Cache and Source Ranking

private final class SourceOperationAccumulator {
    struct Snapshot {
        let mangas: [Manga]
        let firstError: Error?
    }

    private let lock = NSLock()
    private var mangas: [Manga] = []
    private var firstError: Error?
    private var completedCount = 0

    func append(_ newMangas: [Manga]) {
        lock.lock()
        mangas.append(contentsOf: newMangas)
        lock.unlock()
    }

    @discardableResult
    func appendAndComplete(_ newMangas: [Manga]) -> Int {
        lock.lock()
        mangas.append(contentsOf: newMangas)
        completedCount += 1
        let count = completedCount
        lock.unlock()
        return count
    }

    func record(error: Error) {
        lock.lock()
        if firstError == nil {
            firstError = error
        }
        lock.unlock()
    }

    @discardableResult
    func recordAndComplete(error: Error) -> Int {
        lock.lock()
        if firstError == nil {
            firstError = error
        }
        completedCount += 1
        let count = completedCount
        lock.unlock()
        return count
    }

    func snapshot() -> Snapshot {
        lock.lock()
        let snapshot = Snapshot(mangas: mangas, firstError: firstError)
        lock.unlock()
        return snapshot
    }
}

private struct SourceSearchCacheEntry: Codable {
    let createdAt: Date
    let catalogFingerprint: String?
    let mangas: [Manga]
}

final class SourceSearchCache {
    static let shared = SourceSearchCache()

    private let lock = NSLock()
    private let userDefaults: UserDefaults
    private let key = "yomuhon.search.cache.v7"
    private let lifetime: TimeInterval = 60 * 8
    private let maximumEntries = 24
    private var storage: [String: SourceSearchCacheEntry]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: SourceSearchCacheEntry].self, from: data) {
            storage = decoded
        } else {
            storage = [:]
        }
    }

    func value(for query: String) -> [Manga]? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = storage[query] else { return nil }

        let currentFingerprint = DeclarativeRemoteConfigLoader.catalogFingerprint
        guard Date().timeIntervalSince(entry.createdAt) <= lifetime,
              entry.catalogFingerprint == currentFingerprint
        else {
            storage.removeValue(forKey: query)
            persistLocked()
            return nil
        }

        return entry.mangas
    }

    func set(_ mangas: [Manga], for query: String) {
        guard !mangas.isEmpty else { return }

        lock.lock()
        storage[query] = SourceSearchCacheEntry(
            createdAt: Date(),
            catalogFingerprint: DeclarativeRemoteConfigLoader.catalogFingerprint,
            mangas: mangas
        )

        if storage.count > maximumEntries {
            let keysToRemove = storage
                .sorted { $0.value.createdAt < $1.value.createdAt }
                .prefix(storage.count - maximumEntries)
                .map(\.key)

            keysToRemove.forEach { storage.removeValue(forKey: $0) }
        }

        persistLocked()
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        storage.removeAll()
        userDefaults.removeObject(forKey: key)
        lock.unlock()
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(storage) else { return }
        userDefaults.set(data, forKey: key)
    }
}

private struct SourceTimedCacheRecord<Value: Codable>: Codable {
    let createdAt: Date
    let catalogFingerprint: String
    let value: Value
}

final class SourceContentCache {
    static let shared = SourceContentCache()

    private let lock = NSLock()
    private let fileManager: FileManager
    private let directoryURL: URL?
    private let detailLifetime: TimeInterval = 60 * 60 * 6
    private let pagesLifetime: TimeInterval = 60 * 30

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = try? fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Yomuhon", isDirectory: true)
        .appendingPathComponent("SourceContentCache-v1", isDirectory: true)

        if let directoryURL {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    func detail(for manga: Manga) -> Manga? {
        read(
            Manga.self,
            category: "detail",
            key: "\(manga.sourceID)|\(manga.id)",
            lifetime: detailLifetime
        )
    }

    func setDetail(_ manga: Manga, for originalManga: Manga) {
        guard !manga.chapters.isEmpty else { return }
        write(
            manga,
            category: "detail",
            key: "\(originalManga.sourceID)|\(originalManga.id)",
            maximumEntries: 80
        )
    }

    func pages(for chapter: Chapter, manga: Manga) -> [Page]? {
        let pages = read(
            [Page].self,
            category: "pages",
            key: "\(manga.sourceID)|\(manga.id)|\(chapter.id)",
            lifetime: pagesLifetime
        )
        return pages?.isEmpty == false ? pages : nil
    }

    func setPages(_ pages: [Page], for chapter: Chapter, manga: Manga) {
        guard !pages.isEmpty else { return }
        write(
            pages,
            category: "pages",
            key: "\(manga.sourceID)|\(manga.id)|\(chapter.id)",
            maximumEntries: 180
        )
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        guard let directoryURL else { return }
        try? fileManager.removeItem(at: directoryURL)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func read<Value: Codable>(
        _ type: Value.Type,
        category: String,
        key: String,
        lifetime: TimeInterval
    ) -> Value? {
        lock.lock()
        defer { lock.unlock() }

        guard let fileURL = fileURL(category: category, key: key),
              let data = try? Data(contentsOf: fileURL),
              let record = try? JSONDecoder().decode(SourceTimedCacheRecord<Value>.self, from: data)
        else {
            return nil
        }

        guard record.catalogFingerprint == DeclarativeRemoteConfigLoader.catalogFingerprint,
              Date().timeIntervalSince(record.createdAt) <= lifetime
        else {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }

        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        return record.value
    }

    private func write<Value: Codable>(
        _ value: Value,
        category: String,
        key: String,
        maximumEntries: Int
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard let fileURL = fileURL(category: category, key: key) else { return }
        let record = SourceTimedCacheRecord(
            createdAt: Date(),
            catalogFingerprint: DeclarativeRemoteConfigLoader.catalogFingerprint,
            value: value
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: fileURL, options: .atomic)
        trim(category: category, maximumEntries: maximumEntries)
    }

    private func fileURL(category: String, key: String) -> URL? {
        guard let directoryURL else { return nil }
        let categoryURL = directoryURL.appendingPathComponent(category, isDirectory: true)
        try? fileManager.createDirectory(at: categoryURL, withIntermediateDirectories: true)
        return categoryURL.appendingPathComponent(stableFileName(for: key) + ".json")
    }

    private func trim(category: String, maximumEntries: Int) {
        guard let directoryURL else { return }
        let categoryURL = directoryURL.appendingPathComponent(category, isDirectory: true)
        guard let files = try? fileManager.contentsOfDirectory(
            at: categoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ), files.count > maximumEntries
        else {
            return
        }

        let sorted = files.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }

        for file in sorted.prefix(files.count - maximumEntries) {
            try? fileManager.removeItem(at: file)
        }
    }

    private func stableFileName(for value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

private struct SourcePerformanceRecord: Codable {
    var averageLatency: TimeInterval
    var successCount: Int
    var failureCount: Int
    var lastSuccessAt: Date?
}

final class SourcePerformanceStore {
    static let shared = SourcePerformanceStore()

    private let lock = NSLock()
    private let userDefaults: UserDefaults
    private let key = "yomuhon.sources.performance.v2"
    private var records: [String: SourcePerformanceRecord]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: SourcePerformanceRecord].self, from: data) {
            records = decoded
        } else {
            records = [:]
        }
    }

    func recordSuccess(sourceID: String, latency: TimeInterval) {
        lock.lock()
        var record = records[sourceID] ?? SourcePerformanceRecord(
            averageLatency: latency,
            successCount: 0,
            failureCount: 0,
            lastSuccessAt: nil
        )

        let boundedLatency = min(max(latency, 0.01), 60)
        record.averageLatency = record.successCount == 0
            ? boundedLatency
            : (record.averageLatency * 0.72) + (boundedLatency * 0.28)
        record.successCount += 1
        record.failureCount = max(0, record.failureCount - 1)
        record.lastSuccessAt = Date()
        records[sourceID] = record
        persistLocked()
        lock.unlock()
    }

    func recordFailure(sourceID: String) {
        lock.lock()
        var record = records[sourceID] ?? SourcePerformanceRecord(
            averageLatency: 8,
            successCount: 0,
            failureCount: 0,
            lastSuccessAt: nil
        )
        record.failureCount = min(record.failureCount + 1, 12)
        records[sourceID] = record
        persistLocked()
        lock.unlock()
    }

    func priorityScore(for sourceID: String) -> Double {
        lock.lock()
        let record = records[sourceID]
        lock.unlock()

        guard let record else {
            return 60
        }

        let successBonus = min(Double(record.successCount), 10) * 2
        let failurePenalty = Double(record.failureCount) * 12
        let latencyPenalty = min(record.averageLatency, 20) * 2.4
        let recencyBonus: Double

        if let lastSuccessAt = record.lastSuccessAt,
           Date().timeIntervalSince(lastSuccessAt) < 60 * 60 * 24 {
            recencyBonus = 8
        } else {
            recencyBonus = 0
        }

        return 65 + successBonus + recencyBonus - failurePenalty - latencyPenalty
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        userDefaults.set(data, forKey: key)
    }
}



enum SourceMetricOperation: String, Codable, CaseIterable {
    case search
    case discovery
    case detail
    case chapters
    case pages
    case image
}

struct SourceMetricsSnapshot: Equatable {
    let successCount: Int
    let failureCount: Int
    let successRate: Double
    let p50Latency: TimeInterval
    let p95Latency: TimeInterval
    let lastSuccessAt: Date?
    let lastFailureAt: Date?
}

private struct SourceOperationMetricsRecord: Codable {
    var successCount: Int
    var failureCount: Int
    var latencySamples: [TimeInterval]
    var recentOutcomes: [Bool]?
    var lastSuccessAt: Date?
    var lastFailureAt: Date?
}

final class SourceMetricsStore {
    static let shared = SourceMetricsStore()

    private let lock = NSLock()
    private let userDefaults: UserDefaults
    private let key = "yomuhon.sources.metrics.v1"
    private let maximumLatencySamples = 40
    private let maximumOutcomeSamples = 40
    private var records: [String: [String: SourceOperationMetricsRecord]]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(
                [String: [String: SourceOperationMetricsRecord]].self,
                from: data
           ) {
            records = decoded
        } else {
            records = [:]
        }
    }

    func recordSuccess(
        sourceID: String,
        operation: SourceMetricOperation,
        latency: TimeInterval
    ) {
        lock.lock()
        var sourceRecords = records[sourceID] ?? [:]
        var record = sourceRecords[operation.rawValue] ?? Self.emptyRecord
        record.successCount = min(record.successCount + 1, 10_000)
        record.recentOutcomes = appendingOutcome(true, to: record.recentOutcomes)
        record.latencySamples.append(min(max(latency, 0.001), 120))
        if record.latencySamples.count > maximumLatencySamples {
            record.latencySamples.removeFirst(record.latencySamples.count - maximumLatencySamples)
        }
        record.lastSuccessAt = Date()
        sourceRecords[operation.rawValue] = record
        records[sourceID] = sourceRecords
        persistLocked()
        lock.unlock()
    }

    func recordFailure(sourceID: String, operation: SourceMetricOperation) {
        lock.lock()
        var sourceRecords = records[sourceID] ?? [:]
        var record = sourceRecords[operation.rawValue] ?? Self.emptyRecord
        record.failureCount = min(record.failureCount + 1, 10_000)
        record.recentOutcomes = appendingOutcome(false, to: record.recentOutcomes)
        record.lastFailureAt = Date()
        sourceRecords[operation.rawValue] = record
        records[sourceID] = sourceRecords
        persistLocked()
        lock.unlock()
    }

    func snapshot(
        sourceID: String,
        operation: SourceMetricOperation
    ) -> SourceMetricsSnapshot {
        lock.lock()
        let record = records[sourceID]?[operation.rawValue]
        lock.unlock()
        return Self.snapshot(from: record)
    }

    func aggregateSnapshot(sourceID: String) -> SourceMetricsSnapshot {
        lock.lock()
        let sourceRecords = records[sourceID]?.values.map { $0 } ?? []
        lock.unlock()

        guard !sourceRecords.isEmpty else {
            return Self.snapshot(from: nil)
        }

        let merged = SourceOperationMetricsRecord(
            successCount: sourceRecords.reduce(0) { $0 + $1.successCount },
            failureCount: sourceRecords.reduce(0) { $0 + $1.failureCount },
            latencySamples: sourceRecords.flatMap(\.latencySamples),
            recentOutcomes: sourceRecords.flatMap { $0.recentOutcomes ?? [] },
            lastSuccessAt: sourceRecords.compactMap(\.lastSuccessAt).max(),
            lastFailureAt: sourceRecords.compactMap(\.lastFailureAt).max()
        )
        return Self.snapshot(from: merged)
    }

    func schedulerScore(
        sourceID: String,
        operation: SourceMetricOperation
    ) -> Double {
        let operationSnapshot = snapshot(sourceID: sourceID, operation: operation)
        let aggregate = aggregateSnapshot(sourceID: sourceID)
        let selected = operationSnapshot.successCount + operationSnapshot.failureCount > 0
            ? operationSnapshot
            : aggregate

        guard selected.successCount + selected.failureCount > 0 else {
            return 50
        }

        let recencyBonus: Double
        if let lastSuccess = selected.lastSuccessAt,
           Date().timeIntervalSince(lastSuccess) < 60 * 60 * 24 {
            recencyBonus = 8
        } else {
            recencyBonus = 0
        }

        let recentFailurePenalty: Double
        if let lastFailure = selected.lastFailureAt,
           Date().timeIntervalSince(lastFailure) < 60 * 30 {
            recentFailurePenalty = 12
        } else {
            recentFailurePenalty = 0
        }

        return (selected.successRate * 70)
            + recencyBonus
            - recentFailurePenalty
            - min(selected.p50Latency, 20) * 1.8
            - min(selected.p95Latency, 30) * 0.55
    }

    private static let emptyRecord = SourceOperationMetricsRecord(
        successCount: 0,
        failureCount: 0,
        latencySamples: [],
        recentOutcomes: [],
        lastSuccessAt: nil,
        lastFailureAt: nil
    )

    private static func snapshot(
        from record: SourceOperationMetricsRecord?
    ) -> SourceMetricsSnapshot {
        guard let record else {
            return SourceMetricsSnapshot(
                successCount: 0,
                failureCount: 0,
                successRate: 1,
                p50Latency: 0,
                p95Latency: 0,
                lastSuccessAt: nil,
                lastFailureAt: nil
            )
        }

        let total = record.successCount + record.failureCount
        let recentOutcomes = record.recentOutcomes ?? []
        let successRate: Double
        if !recentOutcomes.isEmpty {
            successRate = Double(recentOutcomes.filter { $0 }.count) / Double(recentOutcomes.count)
        } else {
            successRate = total > 0
                ? Double(record.successCount) / Double(total)
                : 1
        }
        let sorted = record.latencySamples.sorted()

        return SourceMetricsSnapshot(
            successCount: record.successCount,
            failureCount: record.failureCount,
            successRate: successRate,
            p50Latency: percentile(0.50, in: sorted),
            p95Latency: percentile(0.95, in: sorted),
            lastSuccessAt: record.lastSuccessAt,
            lastFailureAt: record.lastFailureAt
        )
    }

    private static func percentile(
        _ percentile: Double,
        in sortedValues: [TimeInterval]
    ) -> TimeInterval {
        guard !sortedValues.isEmpty else { return 0 }
        let position = Int(
            (Double(sortedValues.count - 1) * percentile).rounded(.up)
        )
        return sortedValues[min(max(position, 0), sortedValues.count - 1)]
    }

    private func appendingOutcome(_ outcome: Bool, to existing: [Bool]?) -> [Bool] {
        var outcomes = existing ?? []
        outcomes.append(outcome)
        if outcomes.count > maximumOutcomeSamples {
            outcomes.removeFirst(outcomes.count - maximumOutcomeSamples)
        }
        return outcomes
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        userDefaults.set(data, forKey: key)
    }
}

struct SourceQueryScheduler {
    static let shared = SourceQueryScheduler()

    let maximumConcurrentSources = 5
    private let executionGate = SourceQueryExecutionGate.shared

    func priorityScore(
        for sourceID: String,
        operation: SourceMetricOperation
    ) -> Double {
        SourceMetricsStore.shared.schedulerScore(
            sourceID: sourceID,
            operation: operation
        )
    }

    func orderedSources(
        _ sources: [Source],
        operation: SourceMetricOperation
    ) -> [Source] {
        sources.sorted { lhs, rhs in
            let lhsScore = priorityScore(for: lhs.id, operation: operation)
            let rhsScore = priorityScore(for: rhs.id, operation: operation)
            if abs(lhsScore - rhsScore) > 0.000_001 {
                return lhsScore > rhsScore
            }

            let lhsLegacy = SourcePerformanceStore.shared.priorityScore(for: lhs.id)
            let rhsLegacy = SourcePerformanceStore.shared.priorityScore(for: rhs.id)
            if abs(lhsLegacy - rhsLegacy) > 0.000_001 {
                return lhsLegacy > rhsLegacy
            }

            return lhs.id < rhs.id
        }
    }

    func makeQueue(
        qualityOfService: QualityOfService,
        sourceCount: Int
    ) -> OperationQueue {
        let queue = OperationQueue()
        queue.qualityOfService = qualityOfService
        queue.maxConcurrentOperationCount = min(
            maximumConcurrentSources,
            max(sourceCount, 1)
        )
        return queue
    }

    func queuePriority(for index: Int) -> Operation.QueuePriority {
        if index < maximumConcurrentSources {
            return .high
        }
        if index < maximumConcurrentSources * 3 {
            return .normal
        }
        return .low
    }

    func withExecutionSlot<T>(
        priority: SourceRequestPriority,
        cancellationToken: RequestCancellationToken? = nil,
        operation: () throws -> T
    ) throws -> T {
        try executionGate.acquire(
            priority: priority,
            cancellationToken: cancellationToken
        )
        defer { executionGate.release() }
        return try operation()
    }
}

private final class SourceQueryExecutionGate {
    static let shared = SourceQueryExecutionGate(maximumConcurrentSources: 5)

    private let condition = NSCondition()
    private let maximumConcurrentSources: Int
    private var activeSourceOperations = 0
    private var waitingInteractiveOperations = 0

    init(maximumConcurrentSources: Int) {
        self.maximumConcurrentSources = max(maximumConcurrentSources, 1)
    }

    func acquire(
        priority: SourceRequestPriority,
        cancellationToken: RequestCancellationToken?
    ) throws {
        condition.lock()

        if priority == .interactive {
            waitingInteractiveOperations += 1
        }

        defer {
            if priority == .interactive {
                waitingInteractiveOperations = max(0, waitingInteractiveOperations - 1)
            }
            condition.unlock()
        }

        while activeSourceOperations >= maximumConcurrentSources
            || (priority == .background && waitingInteractiveOperations > 0) {
            if cancellationToken?.isCancelled == true {
                throw HTTPClientError.cancelled
            }

            _ = condition.wait(until: Date().addingTimeInterval(0.05))
        }

        if cancellationToken?.isCancelled == true {
            throw HTTPClientError.cancelled
        }

        activeSourceOperations += 1
    }

    func release() {
        condition.lock()
        activeSourceOperations = max(0, activeSourceOperations - 1)
        condition.broadcast()
        condition.unlock()
    }
}


// MARK: - Manga Intake Pipeline

struct MangaIntakePipeline {
    func normalizeSearchResults(_ mangas: [Manga]) -> [Manga] {
        var bestByKey: [String: Manga] = [:]
        var order: [String] = []

        for manga in mangas {
            guard let normalized = normalize(manga), normalized.isReadableCandidate else {
                continue
            }

            let key = "\(normalized.sourceID)|\(normalized.crossSourceTitleKey)"

            if bestByKey[key] == nil {
                order.append(key)
                bestByKey[key] = normalized
                continue
            }

            if let current = bestByKey[key], normalized.intakeScore > current.intakeScore {
                bestByKey[key] = normalized
            }
        }

        return order.compactMap { bestByKey[$0] }
    }

    func normalizeDetail(_ manga: Manga) -> Manga {
        normalize(manga) ?? manga
    }

    private func normalize(_ manga: Manga) -> Manga? {
        let title = manga.title
            .removingYomuhonSourceMarkers
            .removingTrailingSourceNumericIdentifier
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty, !title.isGarbageMangaTitle else {
            return nil
        }

        return Manga(
            id: manga.id,
            sourceID: manga.sourceID,
            title: title,
            coverURL: manga.coverURL,
            // Keep internal source-url markers intact.
            // The UI uses `cleanSynopsis`/`displaySynopsis`, so markers stay hidden,
            // but source adapters still need them to fetch details and chapters.
            synopsis: manga.synopsis,
            alternativeTitles: manga.alternativeTitles,
            author: manga.author,
            releaseYear: manga.releaseYear,
            chapters: manga.chapters
        )
    }
}

private extension Manga {
    var intakeScore: Int {
        var score = 0

        if coverURL != nil {
            score += 16
        }

        if cleanSynopsis?.isEmpty == false {
            score += 10
        }

        score += min(chapters.count, 100)

        if chapters.contains(where: { !$0.pages.isEmpty || !NativeSourceCatalog.supportsReading(sourceID: sourceID) }) {
            score += 6
        }

        return score
    }

    var isReadableCandidate: Bool {
        NativeSourceCatalog.supportsReading(sourceID: sourceID)
    }
}

private extension String {
    var isGarbageMangaTitle: Bool {
        let value = lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let blocked: Set<String> = [
            "[cover]",
            "cover",
            "image",
            "poster",
            "read more",
            "chapter",
            "chapters",
            "manga"
        ]

        if blocked.contains(value) {
            return true
        }

        return value.range(of: #"^chapter\s*[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil
            || value.range(of: #"^ch\.?\s*[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil
    }
}




private extension Manga {
    var hasYomuhonSourceURLMarker: Bool {
        synopsis?.components(separatedBy: "\n").contains { line in
            line.hasPrefix("yomuhon-source-url:")
                || line.hasPrefix("yomuhon-declarative-source-url:")
        } ?? false
    }

    func mergingRepairData(from original: Manga) -> Manga {
        let originalSynopsis = original.synopsis?.removingYomuhonSourceMarkers
        let repairedMarkers = synopsis?.yomuhonSourceMarkerLines ?? []
        let cleanSynopsis = originalSynopsis?.isEmpty == false ? originalSynopsis : synopsis?.removingYomuhonSourceMarkers

        var synopsisParts: [String?] = repairedMarkers.map { Optional($0) }
        synopsisParts.append(cleanSynopsis)

        return Manga(
            id: original.id,
            sourceID: original.sourceID,
            title: original.title,
            coverURL: original.coverURL ?? coverURL,
            synopsis: synopsisParts
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "\n"),
            alternativeTitles: original.alternativeTitles ?? alternativeTitles,
            author: original.author ?? author,
            releaseYear: original.releaseYear ?? releaseYear,
            chapters: chapters.isEmpty ? original.chapters : chapters
        )
    }
}

private extension Array where Element == Manga {
    func bestRepairCandidate(for manga: Manga) -> Manga? {
        let targetKey = manga.crossSourceTitleKey

        return map { candidate -> (manga: Manga, score: Int) in
            let candidateKey = candidate.crossSourceTitleKey
            var score = 0

            if candidateKey == targetKey {
                score += 100
            }

            if candidateKey.contains(targetKey) || targetKey.contains(candidateKey) {
                score += 45
            }

            let left = Set(targetKey.split(separator: " ").map(String.init).filter { $0.count > 1 })
            let right = Set(candidateKey.split(separator: " ").map(String.init).filter { $0.count > 1 })

            if !left.isEmpty, !right.isEmpty {
                score += left.intersection(right).count * 10
            }

            if candidate.hasYomuhonSourceURLMarker {
                score += 40
            }

            if candidate.coverURL != nil {
                score += 5
            }

            return (candidate, score)
        }
        .filter { $0.score >= 45 }
        .max { lhs, rhs in lhs.score < rhs.score }?
        .manga
    }
}


// MARK: - Metadata Enrichment

struct MangaMetadataEnrichmentService {
    private let providers: [Source]
    private let maxSearchEnrichmentCount: Int

    init(
        providers: [Source] = [JikanMetadataSource()],
        maxSearchEnrichmentCount: Int = 8
    ) {
        self.providers = providers
        self.maxSearchEnrichmentCount = maxSearchEnrichmentCount
    }

    func enrich(_ mangas: [Manga]) -> [Manga] {
        var remainingBudget = maxSearchEnrichmentCount

        return mangas.map { manga in
            guard manga.needsMetadataEnrichment, remainingBudget > 0 else {
                return manga
            }

            remainingBudget -= 1
            return enrich(manga)
        }
    }

    func enrich(_ manga: Manga) -> Manga {
        guard manga.needsMetadataEnrichment else {
            return manga
        }

        let key = manga.metadataLookupKey

        if let cached = MangaMetadataEnrichmentCache.shared.value(for: key) {
            return manga.mergingMetadata(from: cached)
        }

        for provider in providers where provider.id != manga.sourceID {
            guard let metadata = metadata(for: manga, provider: provider) else {
                continue
            }

            MangaMetadataEnrichmentCache.shared.set(metadata, for: key)
            return manga.mergingMetadata(from: metadata)
        }

        return manga
    }

    private func metadata(for manga: Manga, provider: Source) -> Manga? {
        do {
            let candidates = try provider.searchManga(query: manga.metadataSearchTitle)
            guard let candidate = bestCandidate(for: manga, candidates: candidates) else {
                return nil
            }

            let detailed = (try? provider.fetchDetails(for: candidate)) ?? candidate
            return detailed.asMetadataOnlyManga
        } catch {
            return nil
        }
    }

    private func bestCandidate(for manga: Manga, candidates: [Manga]) -> Manga? {
        let targetKey = manga.crossSourceTitleKey

        return candidates
            .map { candidate -> (manga: Manga, score: Int) in
                var score = 0
                let candidateKey = candidate.crossSourceTitleKey

                if candidateKey == targetKey {
                    score += 100
                }

                if candidateKey.contains(targetKey) || targetKey.contains(candidateKey) {
                    score += 40
                }

                score += titleTokenOverlapScore(lhs: targetKey, rhs: candidateKey)

                if candidate.coverURL != nil {
                    score += 12
                }

                if candidate.cleanSynopsis?.isEmpty == false {
                    score += 8
                }

                return (candidate, score)
            }
            .filter { $0.score >= 28 }
            .max { lhs, rhs in
                lhs.score < rhs.score
            }?
            .manga
    }

    private func titleTokenOverlapScore(lhs: String, rhs: String) -> Int {
        let left = Set(lhs.split(separator: " ").map(String.init).filter { $0.count > 1 })
        let right = Set(rhs.split(separator: " ").map(String.init).filter { $0.count > 1 })

        guard !left.isEmpty, !right.isEmpty else {
            return 0
        }

        let overlap = left.intersection(right).count
        let denominator = max(left.count, right.count)
        return Int((Double(overlap) / Double(denominator)) * 40.0)
    }
}

private final class MangaMetadataEnrichmentCache {
    static let shared = MangaMetadataEnrichmentCache()

    private var storage: [String: Manga] = [:]
    private let lock = NSLock()

    func value(for key: String) -> Manga? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func set(_ manga: Manga, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = manga
    }
}

private extension Manga {
    var needsMetadataEnrichment: Bool {
        coverURL == nil || cleanSynopsis == nil || cleanSynopsis?.isEmpty == true
    }

    var metadataLookupKey: String {
        crossSourceTitleKey
    }

    var metadataSearchTitle: String {
        let cleanTitle = title
            .removingYomuhonSourceMarkers
            .replacingOccurrences(of: #"\bchapter\s+[0-9]+(?:\.[0-9]+)?\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bch\.?\s+[0-9]+(?:\.[0-9]+)?\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleanTitle.isEmpty ? title : cleanTitle
    }

    var asMetadataOnlyManga: Manga {
        Manga(
            id: "metadata-\(sourceID)-\(id)",
            sourceID: sourceID,
            title: title,
            coverURL: coverURL,
            synopsis: cleanSynopsis,
            alternativeTitles: alternativeTitles,
            author: author,
            releaseYear: releaseYear,
            chapters: []
        )
    }

    func mergedIdentityTitles(with metadata: Manga) -> [String]? {
        var seen = Set<String>()
        var candidates: [String] = alternativeTitles ?? []
        candidates.append(contentsOf: metadata.identityTitles)
        let merged = candidates
            .filter { candidate in
                let key = candidate
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty, key != crossSourceTitleKey else { return false }
                return seen.insert(key).inserted
            }
        return merged.isEmpty ? nil : merged
    }

    func mergingMetadata(from metadata: Manga) -> Manga {
        let mergedCoverURL = coverURL ?? metadata.coverURL
        let currentSynopsis = cleanSynopsis
        let metadataSynopsis = metadata.cleanSynopsis
        let mergedSynopsis = currentSynopsis?.isEmpty == false ? currentSynopsis : metadataSynopsis
        let originalMarkers = synopsis?.yomuhonSourceMarkerLines ?? []

        var synopsisParts: [String?] = originalMarkers.map { Optional($0) }
        synopsisParts.append(mergedSynopsis)

        return Manga(
            id: id,
            sourceID: sourceID,
            title: title,
            coverURL: mergedCoverURL,
            synopsis: synopsisParts
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "\n"),
            alternativeTitles: mergedIdentityTitles(with: metadata),
            author: author ?? metadata.author,
            releaseYear: releaseYear ?? metadata.releaseYear,
            chapters: chapters
        )
    }
}



// MARK: - Jikan Metadata Provider

private struct JikanMetadataSource: Source {
    let id = "jikan_metadata"
    let name = "Jikan Metadata"

    private let apiBaseURL = URL(string: "https://api.jikan.moe/v4")!
    private let httpClient = HTTPClient()
    private let decoder = JSONDecoder()

    func searchManga(query: String) throws -> [Manga] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            return []
        }

        var components = URLComponents(
            url: apiBaseURL.appendingPathComponent("manga"),
            resolvingAgainstBaseURL: false
        )

        components?.queryItems = [
            URLQueryItem(name: "q", value: trimmedQuery),
            URLQueryItem(name: "sfw", value: "true"),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "order_by", value: "members"),
            URLQueryItem(name: "sort", value: "desc")
        ]

        guard let url = components?.url else {
            return []
        }

        let data = try httpClient.data(from: url)
        let response = try decoder.decode(JikanMangaSearchResponse.self, from: data)

        return response.data.map { item in
            Manga(
                id: "\(id)-\(item.malID)",
                sourceID: id,
                title: item.resolvedTitle,
                coverURL: item.resolvedCoverURL,
                synopsis: item.synopsis,
                alternativeTitles: item.resolvedAlternativeTitles,
                chapters: []
            )
        }
    }

    func fetchDetails(for manga: Manga) throws -> Manga {
        manga
    }

    func fetchChapters(for manga: Manga) throws -> [Chapter] {
        []
    }
}

private struct JikanMangaSearchResponse: Decodable {
    let data: [JikanMangaItem]
}

private struct JikanMangaItem: Decodable {
    let malID: Int
    let title: String?
    let titleEnglish: String?
    let titleJapanese: String?
    let titles: [JikanTitle]?
    let synopsis: String?
    let images: JikanImages?

    enum CodingKeys: String, CodingKey {
        case malID = "mal_id"
        case title
        case titleEnglish = "title_english"
        case titleJapanese = "title_japanese"
        case titles
        case synopsis
        case images
    }

    var resolvedTitle: String {
        if let title, !title.isEmpty {
            return title
        }

        if let titleEnglish, !titleEnglish.isEmpty {
            return titleEnglish
        }

        if let firstTitle = titles?.first?.title, !firstTitle.isEmpty {
            return firstTitle
        }

        return titleJapanese ?? "Untitled"
    }

    var resolvedAlternativeTitles: [String]? {
        var seen = Set<String>()
        let primaryKey = resolvedTitle
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [String] = [titleEnglish, titleJapanese]
            .compactMap { $0 }
        if let titles {
            candidates.append(contentsOf: titles.compactMap(\.title))
        }

        let aliases = candidates.filter { value in
            let key = value
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, key != primaryKey else { return false }
            return seen.insert(key).inserted
        }

        return aliases.isEmpty ? nil : aliases
    }

    var resolvedCoverURL: URL? {
        let candidates = [
            images?.jpg?.largeImageURL,
            images?.jpg?.imageURL,
            images?.webp?.largeImageURL,
            images?.webp?.imageURL
        ]

        return candidates
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first
    }
}

private struct JikanTitle: Decodable {
    let type: String?
    let title: String?
}

private struct JikanImages: Decodable {
    let jpg: JikanImageSet?
    let webp: JikanImageSet?
}

private struct JikanImageSet: Decodable {
    let imageURL: String?
    let smallImageURL: String?
    let largeImageURL: String?

    enum CodingKeys: String, CodingKey {
        case imageURL = "image_url"
        case smallImageURL = "small_image_url"
        case largeImageURL = "large_image_url"
    }
}

private extension String {
    var yomuhonSourceMarkerLines: [String] {
        components(separatedBy: "\n")
            .filter { line in
                line.hasPrefix("yomuhon-source-url:")
                    || line.hasPrefix("yomuhon-declarative-source-url:")
            }
    }
}
