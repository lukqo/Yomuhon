//
//  SourceSettingsStore.swift
//  Yomuhon
//

import Foundation


enum SourceLanguagePreference: String, CaseIterable, Identifiable {
    case spanish
    case english
    case spanishEnglish

    var id: String {
        rawValue
    }

    var titleKey: String {
        switch self {
        case .spanish:
            return "language.preference.spanish"
        case .english:
            return "language.preference.english"
        case .spanishEnglish:
            return "language.preference.spanishEnglish"
        }
    }

    var shortTitle: String {
        switch self {
        case .spanish:
            return "ES"
        case .english:
            return "EN"
        case .spanishEnglish:
            return "ES + EN"
        }
    }

    var languageCodes: [String] {
        switch self {
        case .spanish:
            return ["es", "es-la"]
        case .english:
            return ["en"]
        case .spanishEnglish:
            return ["es", "es-la", "en"]
        }
    }

    var fallbackLanguageCodes: [String] {
        switch self {
        case .spanish:
            return ["en"]
        case .english:
            return ["es", "es-la"]
        case .spanishEnglish:
            return []
        }
    }
}

final class SourceLanguagePreferenceStore {
    static let shared = SourceLanguagePreferenceStore()

    private let userDefaults: UserDefaults
    private let defaultPreference: SourceLanguagePreference = .spanishEnglish

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func preference(for sourceID: String) -> SourceLanguagePreference {
        guard supportsLanguageSelection(sourceID: sourceID) else {
            return fixedPreference(for: sourceID)
        }

        let key = key(for: sourceID)
        let rawValue = userDefaults.string(forKey: key)
        return rawValue.flatMap(SourceLanguagePreference.init(rawValue:)) ?? defaultPreference
    }

    func setPreference(_ preference: SourceLanguagePreference, for sourceID: String) {
        guard supportsLanguageSelection(sourceID: sourceID) else {
            return
        }

        userDefaults.set(preference.rawValue, forKey: key(for: sourceID))
    }

    func languageCodes(for sourceID: String) -> [String] {
        preference(for: sourceID).languageCodes
    }

    func fallbackLanguageCodes(for sourceID: String) -> [String] {
        preference(for: sourceID).fallbackLanguageCodes
    }

    func supportsLanguageSelection(sourceID: String) -> Bool {
        DeclarativeRemoteConfigLoader.availableConfigs()
            .first(where: { $0.id.caseInsensitiveCompare(sourceID) == .orderedSame })?
            .api?
            .chapters?
            .languagePath != nil
    }

    /// A specific language chosen for a single title, overriding the broad
    /// (Spanish / English / both) global preference for that title only.
    /// `nil` means "use the global preference".
    func exactLanguageOverride(mangaID: String, sourceID: String) -> String? {
        guard supportsLanguageSelection(sourceID: sourceID) else {
            return nil
        }

        return userDefaults.string(forKey: exactOverrideKey(mangaID: mangaID, sourceID: sourceID))
    }

    func setExactLanguageOverride(_ code: String?, mangaID: String, sourceID: String) {
        guard supportsLanguageSelection(sourceID: sourceID) else {
            return
        }

        let key = exactOverrideKey(mangaID: mangaID, sourceID: sourceID)

        if let code, !code.isEmpty {
            userDefaults.set(code, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    private func fixedPreference(for sourceID: String) -> SourceLanguagePreference {
        supportsLanguageSelection(sourceID: sourceID) ? defaultPreference : .english
    }

    private func key(for sourceID: String) -> String {
        "source.language.preference.\(sourceID.lowercased())"
    }

    private func exactOverrideKey(mangaID: String, sourceID: String) -> String {
        "source.language.exactOverride.\(sourceID.lowercased()).\(mangaID)"
    }
}

extension String {
    /// Human-readable display name for a language code such as "en", "es",
    /// or "pt-br". Falls back to the uppercased code when the system can't
    /// localize it.
    var yomuhonLanguageDisplayName: String {
        let base = components(separatedBy: "-").first ?? self
        let name = Locale.current.localizedString(forLanguageCode: base)
        return name?.capitalized(with: Locale.current) ?? uppercased()
    }
}


struct NativeSourceAdapterDescriptor: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String
    let isEnabledInitially: Bool
    let supportsReading: Bool
    let statusMessage: String
    var isBundled: Bool
    var initialHealthStatus: SourceHealthStatus

    init(
        id: String,
        name: String,
        language: String,
        isEnabledInitially: Bool,
        supportsReading: Bool,
        statusMessage: String,
        isBundled: Bool = true,
        initialHealthStatus: SourceHealthStatus = .available
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.isEnabledInitially = isEnabledInitially
        self.supportsReading = supportsReading
        self.statusMessage = statusMessage
        self.isBundled = isBundled
        self.initialHealthStatus = initialHealthStatus
    }

    var configuration: SourceRepositoryConfiguration {
        SourceRepositoryConfiguration(
            id: id,
            name: name,
            isEnabled: isEnabledInitially,
            isBundled: isBundled,
            installedSources: [
                InstalledSourceConfiguration(
                    id: id,
                    name: name,
                    language: language,
                    healthStatus: initialHealthStatus,
                    mangas: [],
                    isInstalled: true
                )
            ],
            statusMessage: statusMessage
        )
    }
}

enum NativeSourceCatalog {
    static var nativeAdapters: [NativeSourceAdapterDescriptor] {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            return [
                NativeSourceAdapterDescriptor(
                    id: "ui_test",
                    name: "UI Test Source",
                    language: "en",
                    isEnabledInitially: true,
                    supportsReading: true,
                    statusMessage: "",
                    isBundled: true,
                    initialHealthStatus: .available
                )
            ]
        }
        #endif
        return []
    }

    static var adapters: [NativeSourceAdapterDescriptor] {
        var seen = Set<String>()
        return (nativeAdapters + declarativeAdapters).filter { descriptor in
            seen.insert(descriptor.id).inserted
        }
    }

    static var declarativeAdapters: [NativeSourceAdapterDescriptor] {
        DeclarativeRemoteConfigLoader.availableConfigs()
            .map { config in
                NativeSourceAdapterDescriptor(
                    id: config.id,
                    name: config.name,
                    language: config.language,
                    // `availableConfigs()` already filters index.enabled/status.
                    // A published stable/testing definition starts operational immediately;
                    // runtime failures are isolated by the circuit breaker.
                    isEnabledInitially: true,
                    supportsReading: config.supports.pages,
                    statusMessage: config.experimental ? "sources.declarative.experimentalStatus" : "sources.declarative.status",
                    isBundled: false,
                    initialHealthStatus: .available
                )
            }
    }

    static func canonicalFamily(for id: String, name: String) -> String {
        let normalized = "\(id) \(name)"
            .lowercased()
            .replacingOccurrences(of: "json", with: "")
            .replacingOccurrences(of: "declarative", with: "")
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.contains("mangakatana") {
            return "mangakatana"
        }

        if normalized.contains("mangapill") {
            return "mangapill"
        }

        if normalized.contains("mangadex") {
            return "mangadex"
        }

        if normalized.contains("local library") || normalized.contains("local") {
            return "local"
        }

        return normalized
    }

    static func familyDisplayName(for family: String, fallbackSourceID: String) -> String {
        switch family {
        case "mangakatana":
            return "MangaKatana"
        case "mangapill":
            return "MangaPill"
        case "mangadex":
            return "MangaDex"
        case "local":
            return "Local Library"
        default:
            return displayName(for: fallbackSourceID)
        }
    }

    static var adapterIDs: Set<String> {
        Set(adapters.map { $0.id })
    }

    static var defaultRepositories: [SourceRepositoryConfiguration] {
        adapters.map { $0.configuration }
    }

    static func canSearch(_ repository: SourceRepositoryConfiguration) -> Bool {
        repository.installedSources.contains { source in
            source.isInstalled && adapterIDs.contains(source.id)
        }
    }

    static func canRead(_ repository: SourceRepositoryConfiguration) -> Bool {
        repository.installedSources.contains { source in
            source.isInstalled
                && adapters.contains { descriptor in
                    descriptor.id == source.id && descriptor.supportsReading
                }
        }
    }

    static func isOperational(_ repository: SourceRepositoryConfiguration) -> Bool {
        repository.isEnabled
            && !SourceRuntimeCircuitBreaker.shared.shouldSkip(sourceID: repository.id)
            && repository.installedSources.contains { source in
                source.isInstalled
                    && source.healthStatus == .available
                    && adapters.contains { descriptor in
                        descriptor.id == source.id && descriptor.supportsReading
                    }
            }
    }

    static func supportsSearch(sourceID: String) -> Bool {
        adapterIDs.contains(sourceID)
    }

    static func isLegacyNativeAdapterID(_ sourceID: String) -> Bool {
        let normalized = sourceID.lowercased()
        return normalized == "mangapill" || normalized == "mangakatana"
    }

    static func supportsReading(sourceID: String) -> Bool {
        adapters.contains { descriptor in
            descriptor.id == sourceID && descriptor.supportsReading }
    }

    /// Stable trust tier used only for automatic source selection. The app
    /// ranks runtime capabilities, not provider names: structured JSON APIs are
    /// preferred over HTML extraction, and experimental definitions rank lower.
    static func automaticSelectionTrustRank(for sourceID: String) -> Int {
        guard let config = DeclarativeRemoteConfigLoader.availableConfigs()
            .first(where: { $0.id.caseInsensitiveCompare(sourceID) == .orderedSame })
        else {
            return 100
        }

        let engineRank = config.engineMode == .jsonAPI ? 300 : 200
        return config.experimental ? engineRank - 80 : engineRank
    }

    static func language(for sourceID: String) -> String {
        if supportsLanguageSelection(sourceID: sourceID) {
            return SourceLanguagePreferenceStore.shared.preference(for: sourceID).shortTitle
        }

        return adapters.first(where: { $0.id == sourceID })?.language ?? "multi"
    }

    static func supportsLanguageSelection(sourceID: String) -> Bool {
        SourceLanguagePreferenceStore.shared.supportsLanguageSelection(sourceID: sourceID)
    }

    /// The source language declared by the remote definition, normalized for
    /// user-facing language routing. A `multi` source returns nil because its
    /// chapter operation must decide availability for the selected title.
    static func declaredLanguageCode(for sourceID: String) -> String? {
        guard let rawLanguage = adapters
            .first(where: { $0.id.caseInsensitiveCompare(sourceID) == .orderedSame })?
            .language
        else {
            return nil
        }

        let normalized = canonicalLanguageCode(rawLanguage)
        return normalized == "multi" ? nil : normalized
    }

    /// Languages Yomuhon can meaningfully ask the currently active source
    /// catalog for. Fixed-language HTML sources contribute their declared
    /// language; chapter-language APIs contribute the language codes supported
    /// by the app's per-title selector.
    static var selectableLanguageCodes: [String] {
        var codes = Set<String>()

        for adapter in adapters {
            if supportsLanguageSelection(sourceID: adapter.id) {
                SourceLanguagePreference.allCases
                    .flatMap { $0.languageCodes }
                    .map(canonicalLanguageCode)
                    .forEach { codes.insert($0) }
            } else if let code = declaredLanguageCode(for: adapter.id) {
                codes.insert(code)
            }
        }

        let preferredOrder = ["es", "en"]
        return codes.sorted { lhs, rhs in
            let lhsIndex = preferredOrder.firstIndex(of: lhs) ?? Int.max
            let rhsIndex = preferredOrder.firstIndex(of: rhs) ?? Int.max
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            return lhs < rhs
        }
    }

    static func canServeLanguage(_ languageCode: String, sourceID: String) -> Bool {
        let requested = canonicalLanguageCode(languageCode)

        if supportsLanguageSelection(sourceID: sourceID) {
            // A source with a declarative chapter language path can be queried
            // for an exact language. Actual title availability is verified by
            // loading its chapter operation before Yomuhon switches source.
            return !requested.isEmpty && requested != "multi"
        }

        return declaredLanguageCode(for: sourceID) == requested
    }

    static func canonicalLanguageCode(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")

        if normalized == "multi" { return "multi" }
        if normalized == "es" || normalized.hasPrefix("es-") { return "es" }
        if normalized == "en" || normalized.hasPrefix("en-") { return "en" }
        return normalized
    }

    static func displayName(for sourceID: String) -> String {
        let normalized = sourceID.lowercased()

        if let adapterName = adapters.first(where: { $0.id.lowercased() == normalized })?.name {
            return userFacingName(adapterName)
        }

        if normalized == "mangadex" || normalized.contains("mangadex") {
            return "MangaDex"
        }

        if normalized == "mangapill" || normalized.contains("mangapill") {
            return "MangaPill"
        }

        if normalized == "mangakatana" || normalized.contains("mangakatana") {
            return "MangaKatana"
        }

        return userFacingName(sourceID)
    }

    private static func userFacingName(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+(JSON|Declarative|Adapter)$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+Source$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class SourceSettingsStore {
    static let shared = SourceSettingsStore()

    private let userDefaults: UserDefaults
    private let key = "source.repository.configurations"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadRepositories() -> [SourceRepositoryConfiguration] {
        let repositories: [SourceRepositoryConfiguration]
        if let data = userDefaults.data(forKey: key),
           let savedRepositories = try? JSONDecoder().decode([SourceRepositoryConfiguration].self, from: data) {
            repositories = mergedWithDefaults(savedRepositories)
        } else {
            repositories = Self.defaultRepositories
        }

        return protectingRuntimeBaselines(
            applyingSafetyMigrations(to: repositories)
        )
    }

    private func applyingSafetyMigrations(to repositories: [SourceRepositoryConfiguration]) -> [SourceRepositoryConfiguration] {
        let legacyMigrationKey = "yomuhon.sources.verifiedActivation.v3"
        let healthRepairMigrationKey = "yomuhon.sources.runtimeHealthRepair.v1"
        let needsLegacyMigration = !userDefaults.bool(forKey: legacyMigrationKey)
        let needsHealthRepair = !userDefaults.bool(forKey: healthRepairMigrationKey)

        guard needsLegacyMigration || needsHealthRepair else {
            return repositories
        }

        let migrated = repositories.map { repository -> SourceRepositoryConfiguration in
            var safeRepository = repository

            if needsLegacyMigration,
               NativeSourceCatalog.isLegacyNativeAdapterID(repository.id) {
                safeRepository.isEnabled = false
                safeRepository.installedSources = safeRepository.installedSources.map { source in
                    var source = source
                    source.healthStatus = .unavailable
                    return source
                }
            }

            return safeRepository
        }

        if needsLegacyMigration {
            userDefaults.set(true, forKey: legacyMigrationKey)
        }
        if needsHealthRepair {
            userDefaults.set(true, forKey: healthRepairMigrationKey)
        }
        if let data = try? JSONEncoder().encode(migrated) {
            userDefaults.set(data, forKey: key)
        }
        return migrated
    }

    private func protectingRuntimeBaselines(
        _ repositories: [SourceRepositoryConfiguration]
    ) -> [SourceRepositoryConfiguration] {
        let publishedDeclarativeIDs = Set(
            DeclarativeRemoteConfigLoader.availableConfigs().map(\.id)
        )

        return repositories.map { repository in
            guard publishedDeclarativeIDs.contains(repository.id) else {
                return repository
            }

            var repository = repository
            repository.isEnabled = true
            repository.installedSources = repository.installedSources.map { source in
                var source = source
                source.isInstalled = true
                source.healthStatus = .available
                return source
            }
            return repository
        }
    }

    func saveRepositories(_ repositories: [SourceRepositoryConfiguration]) {
        guard let data = try? JSONEncoder().encode(mergedWithDefaults(repositories)) else {
            return
        }

        userDefaults.set(data, forKey: key)
    }

    private func mergedWithDefaults(_ repositories: [SourceRepositoryConfiguration]) -> [SourceRepositoryConfiguration] {
        let defaultRepositories = Self.defaultRepositories
        let defaultIDs = Set(defaultRepositories.map(\.id))

        let mergedDefaults = defaultRepositories.map { defaultRepository in
            guard let savedRepository = repositories.first(where: { $0.id == defaultRepository.id }) else {
                return defaultRepository
            }

            var mergedRepository = defaultRepository
            mergedRepository.isEnabled = savedRepository.isEnabled
            mergedRepository.installedSources = defaultRepository.installedSources.map { defaultSource in
                guard let savedSource = savedRepository.installedSources.first(where: { $0.id == defaultSource.id }) else {
                    return defaultSource
                }

                var mergedSource = defaultSource
                mergedSource.healthStatus = savedSource.healthStatus
                mergedSource.isInstalled = savedSource.isInstalled
                return mergedSource
            }
            return mergedRepository
        }

        let savedRemoteOnly = repositories.filter { !defaultIDs.contains($0.id) }
        return mergedDefaults + savedRemoteOnly
    }

    static var defaultRepositories: [SourceRepositoryConfiguration] {
        NativeSourceCatalog.defaultRepositories
    }
}
