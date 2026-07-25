//
//  SourcesViewModel.swift
//  Yomuhon
//

import Combine
import Foundation

enum SourceTestState: Equatable {
    case idle
    case testing
    case passed(String)
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            return String(localized: "sources.test.idle")
        case .testing:
            return String(localized: "sources.test.testing")
        case .passed(let message), .failed(let message):
            return message
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "circle.dotted"
        case .testing:
            return "clock"
        case .passed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}

enum SourceHealthAutomationState: Equatable {
    case idle
    case checking
    case completed(Date)

    var title: String {
        switch self {
        case .idle:
            return String(localized: "sources.auto.idle")
        case .checking:
            return String(localized: "sources.auto.checking")
        case .completed(let date):
            return String.localizedStringWithFormat(
                NSLocalizedString("sources.auto.completedFormat", comment: ""),
                date.formatted(date: .omitted, time: .shortened)
            )
        }
    }
}

protocol SourceSettingsStoring {
    func loadRepositories() -> [SourceRepositoryConfiguration]
    func saveRepositories(_ repositories: [SourceRepositoryConfiguration])
}

extension SourceSettingsStore: SourceSettingsStoring {}

struct SourceRepositoryRowItem: Identifiable, Hashable {
    let repository: SourceRepositoryConfiguration

    var id: String { repository.id }
    var title: String { NativeSourceCatalog.displayName(for: repository.id) }
    var language: String {
        let value = repository.installedSources.first?.language ?? "multi"
        return value.uppercased()
    }
    var isReadable: Bool { NativeSourceCatalog.canRead(repository) }
    var isOperational: Bool {
        NativeSourceCatalog.isOperational(repository)
    }

    var statusTitle: String {
        isOperational
            ? String(localized: "sources.product.available")
            : String(localized: "sources.product.temporarilyUnavailable")
    }

    var statusMessage: String {
        isOperational
            ? String(localized: "sources.product.available.message")
            : String(localized: "sources.product.temporarilyUnavailable.message")
    }
}

final class SourcesViewModel: ObservableObject {
    @Published private(set) var repositories: [SourceRepositoryConfiguration] = []
    @Published var successMessage: String?
    @Published private(set) var isRefreshingRemoteSources = false
    @Published private(set) var testStates: [String: SourceTestState] = [:]
    @Published private(set) var healthAutomationState: SourceHealthAutomationState = .idle

    private let store: SourceSettingsStoring
    private let autoHealthInterval: TimeInterval = 60 * 60 * 12
    private var scheduledMaintenanceWorkItem: DispatchWorkItem?
    private var hasStartedLaunchCatalogRefresh = false
    private let automaticMaintenanceLaunchDelay: TimeInterval = 45
    private let lastMaintenanceKey = "yomuhon.sources.lastVerifiedMaintenance.v5"
    private let catalogFingerprintKey = "yomuhon.sources.catalogFingerprint.v2"
    private var cancellables = Set<AnyCancellable>()

    init(store: SourceSettingsStoring) {
        self.store = store
        repositories = store.loadRepositories()

        Publishers.Merge(
            NotificationCenter.default.publisher(for: .yomuhonSourceCatalogDidChange),
            NotificationCenter.default.publisher(for: .yomuhonSourceAvailabilityDidChange)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.reloadPublishedRepositories()
        }
        .store(in: &cancellables)
    }

    var repositoryItems: [SourceRepositoryRowItem] {
        repositories
            .filter { repository in
                NativeSourceCatalog.canRead(repository)
                    && !NativeSourceCatalog.isLegacyNativeAdapterID(repository.id)
            }
            .map(SourceRepositoryRowItem.init)
            .sorted { lhs, rhs in
                if lhs.isOperational != rhs.isOperational {
                    return lhs.isOperational && !rhs.isOperational
                }

                let lhsScore = SourcePerformanceStore.shared.priorityScore(for: lhs.id)
                let rhsScore = SourcePerformanceStore.shared.priorityScore(for: rhs.id)
                if lhsScore != rhsScore { return lhsScore > rhsScore }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    var readableAdapterCount: Int {
        repositories.filter { repository in
            NativeSourceCatalog.canRead(repository)
                && !NativeSourceCatalog.isLegacyNativeAdapterID(repository.id)
        }.count
    }

    var healthyAdapterCount: Int {
        repositoryItems.filter(\.isOperational).count
    }

    var pausedAdapterCount: Int {
        max(0, readableAdapterCount - healthyAdapterCount)
    }

    var diagnosticsButtonTitle: String {
        healthAutomationState == .checking
            ? String(localized: "sources.auto.checking")
            : String(localized: "sources.health.testAll")
    }

    var automaticStatusMessage: String {
        if healthyAdapterCount == 0 {
            return String(localized: "search.noSources.message")
        }

        return String.localizedStringWithFormat(
            NSLocalizedString("sources.auto.updatedFormat", comment: ""),
            healthyAdapterCount,
            readableAdapterCount
        )
    }

    func testState(for repository: SourceRepositoryConfiguration) -> SourceTestState {
        if let state = testStates[repository.id] {
            return state
        }

        return SourceRuntimeCircuitBreaker.shared.shouldSkip(sourceID: repository.id)
            ? .idle
            : .passed(String(localized: "source.state.ready"))
    }

    func testAllSources() {
        runHealthDiagnostics(force: true)
    }

    func performScheduledMaintenanceIfNeeded() {
        refreshCatalogOnLaunchIfNeeded()

        // Full live diagnostics are maintenance, never part of app launch or the
        // reader critical path. Give Search/Detail a quiet network window first.
        scheduleAutomaticMaintenance(after: automaticMaintenanceLaunchDelay)
    }

    private func refreshCatalogOnLaunchIfNeeded() {
        guard !hasStartedLaunchCatalogRefresh else { return }
        hasStartedLaunchCatalogRefresh = true

        let store = self.store
        DispatchQueue.global(qos: .utility).async { [weak self] in
            _ = SourceRequestPriorityContext.withPriority(.background) {
                DeclarativeRemoteConfigLoader.refreshConfigs()
            }
            let refreshedRepositories = store.loadRepositories()

            DispatchQueue.main.async {
                self?.repositories = refreshedRepositories
            }
        }
    }

    private func scheduleAutomaticMaintenance(after delay: TimeInterval) {
        scheduledMaintenanceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if SourceRuntimeActivityCenter.shared.hasInteractiveActivity {
                self.scheduleAutomaticMaintenance(after: 15)
                return
            }
            self.runHealthDiagnostics(force: false)
        }
        scheduledMaintenanceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func runHealthDiagnostics(force: Bool) {
        guard healthAutomationState != .checking else { return }

        if !force, SourceRuntimeActivityCenter.shared.hasInteractiveActivity {
            scheduleAutomaticMaintenance(after: 15)
            return
        }

        healthAutomationState = .checking
        isRefreshingRemoteSources = true
        successMessage = force ? String(localized: "sources.auto.checking") : nil

        let store = self.store
        let lastMaintenanceKey = self.lastMaintenanceKey
        let catalogFingerprintKey = self.catalogFingerprintKey
        let autoHealthInterval = self.autoHealthInterval

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let defaults = UserDefaults.standard
            let previousFingerprint = defaults.string(forKey: catalogFingerprintKey) ?? ""

            _ = SourceRequestPriorityContext.withPriority(.background) {
                DeclarativeRemoteConfigLoader.refreshConfigs()
            }
            let currentFingerprint = DeclarativeRemoteConfigLoader.catalogFingerprint
            let refreshedRepositories = store.loadRepositories()

            let lastRun = defaults.double(forKey: lastMaintenanceKey)
            let fullCheckDue = force
                || lastRun <= 0
                || Date().timeIntervalSince1970 - lastRun >= autoHealthInterval
            let catalogChanged = currentFingerprint != previousFingerprint
            let shouldRunSmokeTests = fullCheckDue || catalogChanged

            guard shouldRunSmokeTests else {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.repositories = refreshedRepositories
                    self.healthAutomationState = .idle
                    self.isRefreshingRemoteSources = false
                }
                return
            }

            let candidates = refreshedRepositories.filter { repository in
                NativeSourceCatalog.canRead(repository)
                    && !NativeSourceCatalog.isLegacyNativeAdapterID(repository.id)
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.repositories = refreshedRepositories
                candidates.forEach { self.testStates[$0.id] = .testing }
            }

            let operationQueue = OperationQueue()
            operationQueue.qualityOfService = .utility
            operationQueue.maxConcurrentOperationCount = 1

            let resultLock = NSLock()
            var results: [String: Result<String, Error>] = [:]

            for repository in candidates {
                operationQueue.addOperation {
                    let result = SourceRequestPriorityContext.withPriority(.background) {
                        SourceSmokeTester.test(sourceID: repository.id)
                    }
                    SourceDebugTrace.log(
                        "Health",
                        "source=\(repository.id) result=\(Self.healthResultDescription(result))"
                    )
                    resultLock.lock()
                    results[repository.id] = result
                    resultLock.unlock()
                }
            }

            operationQueue.waitUntilAllOperationsAreFinished()

            DispatchQueue.main.async {
                guard let self else { return }

                for repository in candidates {
                    guard let result = results[repository.id] else { continue }

                    switch result {
                    case .success(let message):
                        SourceHealthFailureStore.shared.recordSuccess(sourceID: repository.id)
                        self.testStates[repository.id] = .passed(message)
                    case .failure(let error):
                        if let smokeError = error as? SourceSmokeTestError,
                           case .deferredForInteractiveActivity = smokeError {
                            self.testStates[repository.id] = .idle
                        } else {
                            _ = SourceHealthFailureStore.shared.recordFailure(sourceID: repository.id)
                            self.testStates[repository.id] = .failed(error.localizedDescription)
                        }
                    }
                }

                // Diagnostics never activate/deactivate a provider. The repository
                // index controls discovery; real interactive failures feed the
                // runtime circuit breaker. Reload the current published snapshot so
                // a maintenance ViewModel and the visible Sources screen agree.
                self.repositories = store.loadRepositories()
                SourceSearchCache.shared.removeAll()
                if previousFingerprint != currentFingerprint {
                    SourceContentCache.shared.removeAll()
                }

                let now = Date()
                defaults.set(now.timeIntervalSince1970, forKey: lastMaintenanceKey)
                defaults.set(currentFingerprint, forKey: catalogFingerprintKey)
                self.healthAutomationState = .completed(now)
                self.isRefreshingRemoteSources = false
                self.successMessage = String.localizedStringWithFormat(
                    NSLocalizedString("sources.auto.updatedFormat", comment: ""),
                    self.healthyAdapterCount,
                    candidates.count
                )
            }
        }
    }

    private static func healthResultDescription(_ result: Result<String, Error>) -> String {
        switch result {
        case .success(let message):
            return "success message=\(message)"
        case .failure(let error):
            if let smokeError = error as? SourceSmokeTestError,
               case .deferredForInteractiveActivity = smokeError {
                return "deferred reason=interactiveActivity"
            }
            return "failure error=\(error.localizedDescription)"
        }
    }

    private func reloadPublishedRepositories() {
        repositories = store.loadRepositories()
    }
}

struct SourceSmokeTester {
    private static let diagnosticTimeout: TimeInterval = 96

    static func quickTest(sourceID: String) -> Result<String, Error> {
        runWithTimeout {
            try SourceRuntimeActivityCenter.shared.waitUntilInteractiveIdle(
                timeout: diagnosticTimeout,
                cancellationToken: HTTPRequestCancellationContext.currentToken
            )
            guard let source = source(for: sourceID) else {
                throw SourceSmokeTestError.notFound
            }

            let requirements = diagnosticRequirements(for: source)
            guard (try source.searchManga(query: requirements.query)).count >= requirements.minimumSearchResults else {
                throw SourceSmokeTestError.noSearchResults
            }

            return String(localized: "source.state.ready")
        }
    }

    static func test(sourceID: String) -> Result<String, Error> {
        runWithTimeout {
            try SourceRuntimeActivityCenter.shared.waitUntilInteractiveIdle(
                timeout: diagnosticTimeout,
                cancellationToken: HTTPRequestCancellationContext.currentToken
            )
            guard let source = source(for: sourceID) else {
                throw SourceSmokeTestError.notFound
            }

            let requirements = diagnosticRequirements(for: source)
            let results = try source.searchManga(query: requirements.query)
            guard results.count >= requirements.minimumSearchResults,
                  let manga = results.first
            else {
                throw SourceSmokeTestError.noSearchResults
            }

            try SourceRuntimeActivityCenter.shared.waitUntilInteractiveIdle(
                timeout: diagnosticTimeout,
                cancellationToken: HTTPRequestCancellationContext.currentToken
            )
            var detailed = try source.fetchDetails(for: manga)
            if detailed.chapters.count < requirements.minimumChapters {
                detailed.chapters = try source.fetchChapters(for: detailed)
            }

            guard detailed.chapters.count >= requirements.minimumChapters else {
                throw SourceSmokeTestError.noChapters
            }

            // A provider can contain one stale or removed chapter without the
            // whole source being broken. Probe a small deterministic sample and
            // accept the first chapter that returns real pages + an image.
            let chapterCandidates = Array(detailed.chapters.prefix(6))
                + Array(detailed.chapters.suffix(3))
            var seenChapterIDs = Set<String>()
            var lastReaderError: Error?

            for chapter in chapterCandidates where seenChapterIDs.insert(chapter.id).inserted {
                do {
                    try SourceRuntimeActivityCenter.shared.waitUntilInteractiveIdle(
                        timeout: diagnosticTimeout,
                        cancellationToken: HTTPRequestCancellationContext.currentToken
                    )
                    let pages = try source.fetchPages(for: chapter, manga: detailed)
                    guard pages.count >= requirements.minimumPages,
                          let firstPageURL = pages.first?.imageURL
                    else {
                        lastReaderError = SourceSmokeTestError.noPages
                        continue
                    }

                    try verifyFirstImage(
                        at: firstPageURL,
                        source: source,
                        refererURL: chapter.declarativeSourceURL
                    )

                    return String.localizedStringWithFormat(
                        NSLocalizedString("sources.test.passedFormat", comment: ""),
                        detailed.title,
                        detailed.chapters.count,
                        pages.count
                    )
                } catch {
                    lastReaderError = error
                }
            }

            throw lastReaderError ?? SourceSmokeTestError.noPages
        }
    }

    private static func runWithTimeout(
        operation: @escaping () throws -> String
    ) -> Result<String, Error> {
        let token = RequestCancellationToken()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + diagnosticTimeout) {
            token.cancel()
        }

        do {
            let value = try HTTPRequestCancellationContext.withToken(token, operation: operation)
            token.cancel()
            return .success(value)
        } catch HTTPClientError.preemptedByInteractiveActivity {
            return .failure(SourceSmokeTestError.deferredForInteractiveActivity)
        } catch let error as HTTPClientError where error.isCancellation {
            return .failure(SourceSmokeTestError.timedOut)
        } catch {
            return .failure(error)
        }
    }

    private static func verifyFirstImage(
        at url: URL,
        source: Source,
        refererURL: URL?
    ) throws {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-2047", forHTTPHeaderField: "Range")
        request.setValue("Mozilla/5.0 Yomuhon/1.0", forHTTPHeaderField: "User-Agent")

        if let config = declarativeConfig(for: source) {
            for (key, value) in config.network?.headers ?? [:] {
                request.setValue(value, forHTTPHeaderField: key)
            }

            let referer = refererURL?.absoluteString
                ?? (config.baseURL.absoluteString.hasSuffix("/")
                    ? config.baseURL.absoluteString
                    : config.baseURL.absoluteString + "/")
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }

        let data = try HTTPClient(
            timeout: 20,
            maximumRetryCount: 1
        ).data(for: request)

        guard !data.isEmpty else {
            throw SourceSmokeTestError.noPages
        }
    }

    private static func source(for sourceID: String) -> Source? {
        DeclarativeRemoteConfigLoader.sourceForDiagnostics(id: sourceID)
    }

    private static func diagnosticRequirements(for source: Source) -> SourceDiagnosticRequirements {
        guard let tests = declarativeConfig(for: source)?.tests else {
            return SourceDiagnosticRequirements(
                query: "one piece",
                minimumSearchResults: 1,
                minimumChapters: 1,
                minimumPages: 1
            )
        }

        return SourceDiagnosticRequirements(
            query: tests.query,
            minimumSearchResults: max(1, tests.minSearchResults ?? 1),
            minimumChapters: max(1, tests.minChapters ?? 1),
            minimumPages: max(1, tests.minPages ?? 1)
        )
    }

    private static func declarativeConfig(for source: Source) -> DeclarativeSourceConfig? {
        if let runtime = source as? DeclarativeSourceRuntime {
            return runtime.config
        }

        if let legacy = source as? DeclarativeHTMLSource {
            return legacy.config
        }

        return nil
    }
}

private final class SourceHealthFailureStore {
    static let shared = SourceHealthFailureStore()

    private let lock = NSLock()
    private let userDefaults = UserDefaults.standard
    private let key = "yomuhon.sources.consecutiveHealthFailures.v2"

    @discardableResult
    func recordFailure(sourceID: String) -> Int {
        lock.lock()
        defer { lock.unlock() }

        var values = userDefaults.dictionary(forKey: key) ?? [:]
        let previous = (values[sourceID] as? NSNumber)?.intValue ?? 0
        let count = previous + 1
        values[sourceID] = count
        userDefaults.set(values, forKey: key)
        return count
    }

    func recordSuccess(sourceID: String) {
        lock.lock()
        defer { lock.unlock() }

        var values = userDefaults.dictionary(forKey: key) ?? [:]
        values.removeValue(forKey: sourceID)
        userDefaults.set(values, forKey: key)
    }
}

private struct SourceDiagnosticRequirements {
    let query: String
    let minimumSearchResults: Int
    let minimumChapters: Int
    let minimumPages: Int
}

enum SourceSmokeTestError: LocalizedError {
    case notFound
    case noSearchResults
    case noChapters
    case noPages
    case timedOut
    case deferredForInteractiveActivity

    var errorDescription: String? {
        switch self {
        case .notFound:
            return String(localized: "sources.test.error.notFound")
        case .noSearchResults:
            return String(localized: "sources.test.error.noSearchResults")
        case .noChapters:
            return String(localized: "sources.test.error.noChapters")
        case .noPages:
            return String(localized: "sources.test.error.noPages")
        case .timedOut:
            return String(localized: "detail.loadTimedOut")
        case .deferredForInteractiveActivity:
            return String(localized: "sources.auto.checking")
        }
    }
}
