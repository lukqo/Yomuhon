//
//  RemoteSourceCatalog.swift
//  Yomuhon
//
//  Trusted catalog/cache layer for Yomuhon-Sources.
//

import Foundation

extension Notification.Name {
    static let yomuhonSourceCatalogDidChange = Notification.Name("yomuhon.sourceCatalog.didChange")
    static let yomuhonSourceAvailabilityDidChange = Notification.Name("yomuhon.sourceAvailability.didChange")
}

private final class DeclarativeConfigResultStore {
    private let lock = NSLock()
    private var storage: [String: DeclarativeSourceConfig] = [:]

    func set(_ config: DeclarativeSourceConfig, for sourceID: String) {
        lock.lock()
        storage[sourceID] = config
        lock.unlock()
    }

    func value(for sourceID: String) -> DeclarativeSourceConfig? {
        lock.lock()
        defer { lock.unlock() }
        return storage[sourceID]
    }
}

enum DeclarativeRemoteConfigLoader {
    static let standardIndexURL = URL(
        string: "https://raw.githubusercontent.com/lukqo/Yomuhon-Sources/main/index.json"
    )!

    private static let lock = NSLock()
    private static let refreshCondition = NSCondition()
    private static var refreshInProgress = false
    private static var lastRefreshCompletedAt: Date?
    private static let minimumRefreshInterval: TimeInterval = 5 * 60
    private static var memoryConfigs: [DeclarativeSourceConfig]?
    private static var memoryDiagnostics = DeclarativeRemoteConfigDiagnostics(
        state: .unknown,
        message: "sources.remote.state.unknown",
        configCount: 0
    )

    static func availableConfigs() -> [DeclarativeSourceConfig] {
        lock.lock()
        if let memoryConfigs {
            lock.unlock()
            return memoryConfigs
        }
        lock.unlock()

        let configs = loadCachedConfigs()
            .filter { DeclarativeSourceConfigurationValidator.validateStandalone($0) }

        let diagnostics = DeclarativeRemoteConfigDiagnostics(
            state: configs.isEmpty ? .unknown : .cache,
            message: configs.isEmpty ? "sources.remote.state.unknown" : "sources.remote.state.cache",
            configCount: configs.count
        )

        storeInMemory(configs: configs, diagnostics: diagnostics)
        return configs
    }

    @discardableResult
    static func refreshConfigs() -> [DeclarativeSourceConfig] {
        // Catalog refresh is synchronous for callers, but startup, Settings and
        // diagnostics may ask for it at nearly the same time. Share one refresh
        // instead of downloading index.json and every source definition twice.
        refreshCondition.lock()

        if refreshInProgress {
            while refreshInProgress {
                refreshCondition.wait()
            }
            refreshCondition.unlock()
            return availableConfigs()
        }

        if let lastRefreshCompletedAt,
           Date().timeIntervalSince(lastRefreshCompletedAt) < minimumRefreshInterval {
            refreshCondition.unlock()
            return availableConfigs()
        }

        refreshInProgress = true
        refreshCondition.unlock()

        defer {
            refreshCondition.lock()
            lastRefreshCompletedAt = Date()
            refreshInProgress = false
            refreshCondition.broadcast()
            refreshCondition.unlock()
        }

        // Keep the last in-memory snapshot as an atomic fallback. A valid index
        // may announce several sources while one individual config request fails.
        // That transient per-source failure must not shrink the live catalog from
        // three providers to one and make Search/Discover flicker.
        let fallbackCurrent = availableConfigs()
        let fallbackCached = loadCachedConfigs()

        do {
            let indexData = try HTTPClient(
                timeout: 12,
                maximumRetryCount: 1
            ).data(from: standardIndexURL)
            let configs = try resolveConfigs(
                indexData: indexData,
                fallbackCurrent: fallbackCurrent,
                fallbackCached: fallbackCached,
                configDataLoader: { url in
                    try HTTPClient(
                        timeout: 12,
                        maximumRetryCount: 1
                    ).data(from: url)
                }
            )

            // The index remains authoritative for discovery: removed/disabled
            // entries are dropped. For entries that are still discoverable, the
            // resolver may retain a last-known-valid older definition until the
            // announced version downloads successfully.
            cache(configs: configs)
            let diagnostics = DeclarativeRemoteConfigDiagnostics(
                state: .remote,
                message: "sources.remote.state.remote",
                configCount: configs.count
            )
            storeInMemory(configs: configs, diagnostics: diagnostics)
            return configs
        } catch let error as DeclarativeSourceError {
            let configs = preferNewest(primary: fallbackCurrent, fallback: fallbackCached)
                .filter { DeclarativeSourceConfigurationValidator.validateStandalone($0) }
            let diagnostics = DeclarativeRemoteConfigDiagnostics(
                state: .invalidRemote,
                message: fallbackMessage(for: error, hasCache: !fallbackCached.isEmpty),
                configCount: configs.count
            )
            storeInMemory(configs: configs, diagnostics: diagnostics)
            return configs
        } catch {
            let configs = preferNewest(primary: fallbackCurrent, fallback: fallbackCached)
                .filter { DeclarativeSourceConfigurationValidator.validateStandalone($0) }
            let diagnostics = DeclarativeRemoteConfigDiagnostics(
                state: .offline,
                message: fallbackCached.isEmpty
                    ? "sources.remote.state.offline"
                    : "sources.remote.state.cache",
                configCount: configs.count
            )
            storeInMemory(configs: configs, diagnostics: diagnostics)
            return configs
        }
    }

    /// Pure catalog resolution used by the live loader and regression tests.
    /// The repository index is the source of discovery; app code does not need
    /// a hard-coded adapter entry for a compatible declarative source.
    static func resolveConfigs(
        indexData: Data,
        fallbackCurrent: [DeclarativeSourceConfig] = [],
        fallbackCached: [DeclarativeSourceConfig] = [],
        configDataLoader: @escaping (URL) throws -> Data
    ) throws -> [DeclarativeSourceConfig] {
        let index = try JSONDecoder().decode(DeclarativeSourceIndex.self, from: indexData)
        try DeclarativeSourceConfigurationValidator.validate(index: index)

        let currentByID = Dictionary(uniqueKeysWithValues: fallbackCurrent.map { ($0.id, $0) })
        let cachedByID = Dictionary(uniqueKeysWithValues: fallbackCached.map { ($0.id, $0) })
        var seenIDs = Set<String>()
        let discoverableEntries = index.sources.filter { entry in
            shouldDiscover(entry) && seenIDs.insert(entry.id).inserted
        }

        // Definitions are independent. Fetch them concurrently so repository
        // growth does not turn startup discovery into a serial timeout chain.
        let resultStore = DeclarativeConfigResultStore()
        let fetchQueue = OperationQueue()
        fetchQueue.qualityOfService = .utility
        fetchQueue.maxConcurrentOperationCount = min(4, max(1, discoverableEntries.count))

        for entry in discoverableEntries {
            fetchQueue.addOperation {
                let remote: DeclarativeSourceConfig? = try? fetchRemoteConfig(
                    for: entry,
                    dataLoader: configDataLoader
                )

                let fallbackCandidates = [
                    currentByID[entry.id],
                    cachedByID[entry.id]
                ]
                .compactMap { $0 }
                .filter {
                    DeclarativeSourceConfigurationValidator.validateLastKnownGood(
                        config: $0,
                        for: entry
                    )
                }
                .sorted { lhs, rhs in lhs.version > rhs.version }

                if let config = remote ?? fallbackCandidates.first {
                    if remote == nil {
                        SourceDebugTrace.log(
                            "Catalog",
                            "source=\(entry.id) remote config unavailable; keeping last-known-good v\(config.version) while index announces v\(entry.version)"
                        )
                    }
                    resultStore.set(config, for: entry.id)
                }
            }
        }

        fetchQueue.waitUntilAllOperationsAreFinished()
        return discoverableEntries.compactMap { resultStore.value(for: $0.id) }
    }

    static func sourceForDiagnostics(id: String) -> Source? {
        availableConfigs()
            .first(where: { $0.id == id })
            .map { DeclarativeSourceRuntime(config: $0) }
    }

    static func diagnostics() -> DeclarativeRemoteConfigDiagnostics {
        _ = availableConfigs()
        lock.lock()
        defer { lock.unlock() }
        return memoryDiagnostics
    }

    static var catalogFingerprint: String {
        availableConfigs()
            .map { "\($0.id):\($0.version)" }
            .sorted()
            .joined(separator: "|")
    }

    static func loadCachedConfigs() -> [DeclarativeSourceConfig] {
        do {
            let data = try Data(contentsOf: cacheFileURL())
            return try JSONDecoder().decode([DeclarativeSourceConfig].self, from: data)
        } catch {
            return []
        }
    }

    private static func fetchRemoteConfig(
        for entry: DeclarativeSourceIndexEntry,
        dataLoader: (URL) throws -> Data
    ) throws -> DeclarativeSourceConfig {
        guard entry.url.scheme?.lowercased() == "https" else {
            throw DeclarativeSourceError.invalidURL(entry.url.absoluteString)
        }

        let data = try dataLoader(entry.url)
        let config = try JSONDecoder().decode(DeclarativeSourceConfig.self, from: data)

        guard DeclarativeSourceConfigurationValidator.validate(config: config, against: entry) else {
            throw DeclarativeSourceError.invalidConfiguration(
                "Config \(entry.id) does not match its index entry."
            )
        }

        if config.tests != nil {
            return config
        }

        guard let testURL = repositoryTestURL(for: entry.url),
              let testData = try? dataLoader(testURL),
              let definition = try? JSONDecoder().decode(
                  DeclarativeRepositoryTestDefinition.self,
                  from: testData
              ),
              definition.sourceID == entry.id,
              let requirements = definition.runtimeRequirements
        else {
            throw DeclarativeSourceError.invalidConfiguration(
                "Source \(entry.id) has no valid smoke-test definition."
            )
        }

        return config.replacingTests(requirements)
    }

    private static func repositoryTestURL(for configURL: URL) -> URL? {
        guard var components = URLComponents(
            url: configURL,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }

        var parts = components.path.split(separator: "/").map(String.init)
        guard let sourcesIndex = parts.lastIndex(of: "sources"),
              sourcesIndex + 1 == parts.count - 1,
              let filename = parts.last,
              filename.hasSuffix(".json")
        else {
            return nil
        }

        let stem = String(filename.dropLast(".json".count))
        parts[sourcesIndex] = "tests"
        parts[parts.count - 1] = "\(stem).test.json"
        components.path = "/" + parts.joined(separator: "/")
        return components.url
    }

    private static func shouldDiscover(_ entry: DeclarativeSourceIndexEntry) -> Bool {
        guard entry.enabled else { return false }

        switch entry.status.lowercased() {
        case "stable", "testing":
            return true
        case "broken", "disabled", "deprecated":
            return false
        default:
            return false
        }
    }

    private static func preferNewest(
        primary: [DeclarativeSourceConfig],
        fallback: [DeclarativeSourceConfig]
    ) -> [DeclarativeSourceConfig] {
        var byID: [String: DeclarativeSourceConfig] = [:]
        var order: [String] = []

        for config in fallback + primary {
            if byID[config.id] == nil {
                order.append(config.id)
            }

            if let current = byID[config.id], current.version > config.version {
                continue
            }

            byID[config.id] = config
        }

        return order.compactMap { byID[$0] }
    }

    private static func cache(configs: [DeclarativeSourceConfig]) {
        do {
            let directory = try cacheDirectory()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try JSONEncoder().encode(configs)
            try data.write(
                to: directory.appendingPathComponent("source-catalog-v2.json"),
                options: .atomic
            )
        } catch {
            // A cache write failure must never make a validated source unusable.
        }
    }

    private static func cacheFileURL() throws -> URL {
        try cacheDirectory().appendingPathComponent("source-catalog-v2.json")
    }

    private static func cacheDirectory() throws -> URL {
        try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Yomuhon", isDirectory: true)
        .appendingPathComponent("RemoteSources", isDirectory: true)
    }

    private static func storeInMemory(
        configs: [DeclarativeSourceConfig],
        diagnostics: DeclarativeRemoteConfigDiagnostics
    ) {
        lock.lock()
        let previousFingerprint = memoryConfigs.map(catalogFingerprint)
        let currentFingerprint = catalogFingerprint(configs)
        memoryConfigs = configs
        memoryDiagnostics = diagnostics
        lock.unlock()

        guard let previousFingerprint,
              previousFingerprint != currentFingerprint
        else {
            return
        }

        SourceDebugTrace.log(
            "Catalog",
            "source catalog changed old=\(previousFingerprint) new=\(currentFingerprint)"
        )
        NotificationCenter.default.post(name: .yomuhonSourceCatalogDidChange, object: nil)
    }

    private static func catalogFingerprint(_ configs: [DeclarativeSourceConfig]) -> String {
        configs
            .sorted { $0.id < $1.id }
            .map { "\($0.id):\($0.version)" }
            .joined(separator: "|")
    }

    private static func fallbackMessage(
        for error: DeclarativeSourceError,
        hasCache: Bool
    ) -> String {
        if hasCache {
            return "sources.remote.state.cache"
        }

        switch error {
        case .unsupportedSchema:
            return "sources.remote.state.badSchema"
        default:
            return "sources.remote.state.noValidConfigs"
        }
    }
}


/// Remote catalog definitions are activated by `index.json`. Runtime health
/// is isolated locally by `SourceRuntimeCircuitBreaker`; diagnostics never gate use.
enum DeclarativeSourceConfigurationValidator {
    private static let sourceIDPattern = #"^[a-z0-9][a-z0-9_-]*$"#
    private static let semanticVersionPattern = #"^[0-9]+\.[0-9]+\.[0-9]+$"#

    static func validate(index: DeclarativeSourceIndex) throws {
        guard index.schemaVersion == 1 else {
            throw DeclarativeSourceError.unsupportedSchema(index.schemaVersion)
        }
        guard index.minimumAppVersion.range(
            of: semanticVersionPattern,
            options: .regularExpression
        ) != nil else {
            throw DeclarativeSourceError.invalidConfiguration("Invalid minimumAppVersion.")
        }
        guard compareVersions(currentAppVersion, index.minimumAppVersion) != .orderedAscending else {
            throw DeclarativeSourceError.minimumAppVersion(index.minimumAppVersion)
        }
        guard isISODate(index.updatedAt) else {
            throw DeclarativeSourceError.invalidConfiguration("updatedAt must use YYYY-MM-DD.")
        }
        guard !index.sources.isEmpty else {
            throw DeclarativeSourceError.invalidConfiguration("The source index is empty.")
        }

        var ids = Set<String>()
        for entry in index.sources {
            guard entry.id.range(of: sourceIDPattern, options: .regularExpression) != nil,
                  !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  entry.version >= 1,
                  entry.language.count >= 2,
                  ["declarative-html", "declarative-json-api"].contains(entry.kind),
                  entry.url.scheme?.lowercased() == "https",
                  !entry.allowedDomains.isEmpty,
                  entry.allowedDomains.allSatisfy(isValidDomain),
                  Set(entry.allowedDomains.map(normalizedDomain)).count == entry.allowedDomains.count,
                  ["stable", "testing", "broken", "disabled", "deprecated"].contains(entry.status),
                  ids.insert(entry.id).inserted
            else {
                throw DeclarativeSourceError.invalidConfiguration("Invalid index entry: \(entry.id)")
            }
        }
    }

    static func validateStandalone(_ config: DeclarativeSourceConfig) -> Bool {
        let syntheticEntry = DeclarativeSourceIndexEntry(
            id: config.id,
            name: config.name,
            version: config.version,
            language: config.language,
            kind: config.engineMode == .jsonAPI ? "declarative-json-api" : "declarative-html",
            url: URL(
                string: "https://raw.githubusercontent.com/lukqo/Yomuhon-Sources/main/sources/\(config.id).json"
            )!,
            enabled: true,
            experimental: config.experimental,
            status: "testing",
            allowedDomains: config.allowedDomains,
            notes: nil
        )

        return validate(config: config, against: syntheticEntry)
    }

    static func validateLastKnownGood(
        config: DeclarativeSourceConfig,
        for entry: DeclarativeSourceIndexEntry
    ) -> Bool {
        guard validateStandalone(config),
              config.id == entry.id,
              config.version <= entry.version,
              config.language == entry.language,
              ((entry.kind == "declarative-html" && config.engineMode == .html)
                || (entry.kind == "declarative-json-api" && config.engineMode == .jsonAPI)),
              config.allowedDomains.allSatisfy({
                  domainMatches($0, allowedDomains: entry.allowedDomains)
              })
        else {
            return false
        }

        return true
    }

    static func validate(
        config: DeclarativeSourceConfig,
        against entry: DeclarativeSourceIndexEntry
    ) -> Bool {
        guard config.schemaVersion == 1,
              config.id == entry.id,
              config.version == entry.version,
              config.name == entry.name,
              config.language == entry.language,
              ((entry.kind == "declarative-html" && config.engineMode == .html)
                || (entry.kind == "declarative-json-api" && config.engineMode == .jsonAPI)),
              config.enabledByDefault != true,
              config.version >= 1,
              config.id.range(of: sourceIDPattern, options: .regularExpression) != nil,
              config.baseURL.scheme?.lowercased() == "https",
              !config.allowedDomains.isEmpty,
              config.allowedDomains.allSatisfy(isValidDomain),
              config.allowedDomains.allSatisfy({
                  domainMatches($0, allowedDomains: entry.allowedDomains)
              }),
              domainMatches(config.baseURL.host, allowedDomains: config.allowedDomains),
              validateRouteAndSelectorContract(config),
              validateSelectorSyntax(config)
        else {
            return false
        }

        return true
    }

    private static func validateRouteAndSelectorContract(
        _ config: DeclarativeSourceConfig
    ) -> Bool {
        func validAPIRequest(_ request: DeclarativeAPIRequest) -> Bool {
            guard request.path.hasPrefix("/") else { return false }
            let method = (request.method ?? "GET").uppercased()
            guard method == "GET" else { return false }
            if let baseURL = request.baseURL {
                guard baseURL.scheme?.lowercased() == "https",
                      domainMatches(baseURL.host, allowedDomains: config.allowedDomains)
                else { return false }
            }
            return true
        }

        func validVariables(_ variables: [String: DeclarativeAPIVariableRule]?) -> Bool {
            guard let variables else { return true }
            return variables.allSatisfy { name, rule in
                guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      ["mangaID", "mangaURL"].contains(rule.from)
                else { return false }
                if let regex = rule.regex,
                   (regex.isEmpty || (try? NSRegularExpression(pattern: regex)) == nil) {
                    return false
                }
                return rule.defaultValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != true
            }
        }

        if let preserved = config.identity?.preserveQueryItems {
            let normalized = preserved.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            guard normalized.allSatisfy({
                !$0.isEmpty && $0.range(
                    of: #"^[a-z0-9_.~-]+$"#,
                    options: [.regularExpression, .caseInsensitive]
                ) != nil
            }), Set(normalized).count == normalized.count else {
                return false
            }
        }

        if config.supports.search {
            switch config.engineMode(for: .search) {
            case .html:
                guard let route = config.routes.search,
                      config.selectors.search != nil,
                      validate(route)
                else { return false }
            case .jsonAPI:
                guard let operation = config.api?.search,
                      validAPIRequest(operation.request),
                      validateAPIListOperation(operation)
                else { return false }
            }
        }

        if config.supports.popular {
            switch config.engineMode(for: .popular) {
            case .html:
                if let operation = config.discover?.popular {
                    guard let route = operation.route,
                          operation.selector != nil,
                          validate(route)
                    else { return false }
                } else {
                    guard let route = config.routes.popular,
                          config.selectors.popular != nil,
                          validate(route)
                    else { return false }
                }
            case .jsonAPI:
                guard let operation = config.discover?.popular?.api,
                      validAPIRequest(operation.request),
                      validateAPIListOperation(operation)
                else { return false }
            }
        }

        if config.supports.supportsGenres {
            guard let genres = config.discover?.genres,
                  validateGenreItems(genres.items)
            else { return false }

            switch config.engineMode(for: .genres) {
            case .html:
                guard let route = genres.operation.route,
                      genres.operation.selector != nil,
                      validate(route)
                else { return false }
            case .jsonAPI:
                guard let operation = genres.operation.api,
                      validAPIRequest(operation.request),
                      validateAPIListOperation(operation)
                else { return false }
            }
        }

        if config.supports.details {
            switch config.engineMode(for: .details) {
            case .html:
                guard config.selectors.details != nil else { return false }
            case .jsonAPI:
                // Schema v1 has no standalone detail API. JSON details reuse the
                // chapter operation, matching the historical json-api behavior.
                guard config.supports.chapters,
                      let operation = config.api?.chapters,
                      validAPIRequest(operation.request),
                      validVariables(operation.variables)
                else { return false }
            }
        }

        if config.supports.chapters {
            switch config.engineMode(for: .chapters) {
            case .html:
                guard config.selectors.chapters != nil else { return false }
            case .jsonAPI:
                guard let chapters = config.api?.chapters,
                      validAPIRequest(chapters.request),
                      !chapters.itemsPath.isEmpty,
                      !chapters.idPath.isEmpty,
                      !chapters.numberPath.isEmpty,
                      validVariables(chapters.variables)
                else { return false }

                if let pagination = chapters.pagination {
                    guard !pagination.offsetParam.isEmpty,
                          !pagination.limitParam.isEmpty,
                          (1...500).contains(pagination.limit)
                    else { return false }
                    if let maxPages = pagination.maxPages, !(1...1_000).contains(maxPages) {
                        return false
                    }
                    if let maxItems = pagination.maxItems, !(1...100_000).contains(maxItems) {
                        return false
                    }
                    if let totalPath = pagination.totalPath, totalPath.isEmpty {
                        return false
                    }
                }
            }
        }

        if config.supports.pages {
            guard config.supports.chapters else { return false }
            switch config.engineMode(for: .pages) {
            case .html:
                guard let pages = config.selectors.pages, !pages.extractors.isEmpty else {
                    return false
                }
                for extractor in pages.extractors {
                    switch extractor.type {
                    case "css":
                        guard let selector = extractor.selector, !selector.isEmpty else { return false }
                    case "regex":
                        guard let pattern = extractor.pattern,
                              !pattern.isEmpty,
                              (try? NSRegularExpression(pattern: pattern)) != nil
                        else { return false }
                    default:
                        return false
                    }
                }
            case .jsonAPI:
                guard let pages = config.api?.pages,
                      validAPIRequest(pages.request),
                      !pages.baseURLPath.isEmpty,
                      !pages.hashPath.isEmpty,
                      !pages.itemsPath.isEmpty,
                      pages.urlTemplate.contains("{item}")
                else { return false }
            }
        }

        return true
    }

    private static func validateGenreItems(_ items: [DeclarativeGenreItem]) -> Bool {
        guard !items.isEmpty else { return false }
        var ids = Set<String>()

        return items.allSatisfy { item in
            let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !id.isEmpty
                && !title.isEmpty
                && !value.isEmpty
                && ids.insert(id).inserted
        }
    }

    private static func validateAPIListOperation(
        _ operation: DeclarativeAPISearchOperation
    ) -> Bool {
        let method = (operation.request.method ?? "GET").uppercased()
        return operation.request.path.hasPrefix("/")
            && method == "GET"
            && !operation.itemsPath.isEmpty
            && !operation.idPath.isEmpty
            && !operation.titlePaths.isEmpty
    }

    private static func validateAPIContract(
        _ api: DeclarativeAPIConfig,
        supports: DeclarativeSourceSupports
    ) -> Bool {
        func validRequest(_ request: DeclarativeAPIRequest) -> Bool {
            guard request.path.hasPrefix("/") else { return false }
            let method = (request.method ?? "GET").uppercased()
            return ["GET"].contains(method)
        }

        if supports.search {
            guard let search = api.search,
                  validRequest(search.request),
                  validateAPIListOperation(search)
            else { return false }
        }

        if supports.chapters {
            guard let chapters = api.chapters,
                  validRequest(chapters.request),
                  !chapters.itemsPath.isEmpty,
                  !chapters.idPath.isEmpty,
                  !chapters.numberPath.isEmpty
            else { return false }

            if let pagination = chapters.pagination {
                guard !pagination.offsetParam.isEmpty,
                      !pagination.limitParam.isEmpty,
                      (1...500).contains(pagination.limit)
                else { return false }

                if let maxPages = pagination.maxPages, !(1...1_000).contains(maxPages) {
                    return false
                }

                if let maxItems = pagination.maxItems, !(1...100_000).contains(maxItems) {
                    return false
                }

                if let totalPath = pagination.totalPath, totalPath.isEmpty {
                    return false
                }
            }
        }

        if supports.pages {
            guard let pages = api.pages,
                  validRequest(pages.request),
                  !pages.baseURLPath.isEmpty,
                  !pages.hashPath.isEmpty,
                  !pages.itemsPath.isEmpty,
                  pages.urlTemplate.contains("{item}")
            else { return false }
        }

        return true
    }

    private static func validate(_ route: DeclarativeRoute) -> Bool {
        guard route.path.hasPrefix("/") else { return false }

        guard let pagination = route.pagination else { return true }
        guard ["path", "query"].contains(pagination.type) else { return false }

        let maxPages = pagination.maxPages ?? 1
        guard (1...5).contains(maxPages), (pagination.start ?? 1) >= 0 else { return false }

        if pagination.type == "query" {
            guard let param = pagination.param, !param.isEmpty else { return false }
        }

        return true
    }

    private static func validateSelectorSyntax(_ config: DeclarativeSourceConfig) -> Bool {
        var selectors: [String] = []

        func append(_ field: DeclarativeFieldSelector?) {
            guard let field else { return }
            selectors.append(contentsOf: field.selectorCandidates)
            if let regex = field.regex,
               (try? NSRegularExpression(pattern: regex)) == nil {
                selectors.append("__invalid_regex__")
            }
        }

        if config.engineMode(for: .search) == .html,
           let list = config.selectors.search {
            selectors.append(list.container)
            append(list.title)
            append(list.url)
            append(list.cover)
            if !validateHTMLScope(list.htmlScope) { return false }
        }

        if config.engineMode(for: .popular) == .html {
            let list = config.discover?.popular?.selector ?? config.selectors.popular
            if let list {
                selectors.append(list.container)
                append(list.title)
                append(list.url)
                append(list.cover)
                if !validateHTMLScope(list.htmlScope) { return false }
            }
        }

        if config.engineMode(for: .genres) == .html,
           let list = config.discover?.genres?.operation.selector {
            selectors.append(list.container)
            append(list.title)
            append(list.url)
            append(list.cover)
            if !validateHTMLScope(list.htmlScope) { return false }
        }

        if config.engineMode(for: .details) == .html,
           let details = config.selectors.details {
            append(details.title)
            append(details.synopsis)
            append(details.cover)
            append(details.alternativeTitles)
            append(details.author)
            append(details.year)
        }

        if config.engineMode(for: .chapters) == .html,
           let chapters = config.selectors.chapters {
            selectors.append(chapters.container)
            append(chapters.title)
            append(chapters.url)
            if let number = chapters.number,
               (try? NSRegularExpression(pattern: number.regex)) == nil {
                return false
            }
            if let sort = chapters.sort,
               !["numberAscending", "numberDescending"].contains(sort) {
                return false
            }
        }

        if config.engineMode(for: .pages) == .html,
           let pages = config.selectors.pages {
            selectors.append(contentsOf: pages.extractors.compactMap { $0.selector })
        }

        guard !selectors.contains("__invalid_regex__") else { return false }
        return selectors.allSatisfy(SimpleHTMLDocument.supports)
    }

    private static func validateHTMLScope(_ scope: DeclarativeHTMLScope?) -> Bool {
        guard let scope else { return true }
        let patterns = [scope.afterRegex, scope.beforeRegex].compactMap { $0 }
        return !patterns.isEmpty && patterns.allSatisfy {
            !$0.isEmpty && (try? NSRegularExpression(pattern: $0)) != nil
        }
    }

    private static func isISODate(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false

        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

    private static func isValidDomain(_ domain: String) -> Bool {
        let value = normalizedDomain(domain)
        guard !value.isEmpty,
              !value.contains("/"),
              !value.contains(":"),
              !value.contains(" "),
              !value.hasPrefix("."),
              !value.hasSuffix(".")
        else {
            return false
        }

        return value.range(
            of: #"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func normalizedDomains(_ domains: [String]) -> Set<String> {
        Set(domains.map(normalizedDomain))
    }

    private static func normalizedDomain(_ domain: String) -> String {
        domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func domainMatches(
        _ host: String?,
        allowedDomains: [String]
    ) -> Bool {
        guard let host else { return false }
        let normalizedHost = normalizedDomain(host)

        return allowedDomains.contains { domain in
            let allowed = normalizedDomain(domain)
            return normalizedHost == allowed || normalizedHost.hasSuffix(".\(allowed)")
        }
    }

    private static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue < rightValue { return .orderedAscending }
            if leftValue > rightValue { return .orderedDescending }
        }

        return .orderedSame
    }
}
