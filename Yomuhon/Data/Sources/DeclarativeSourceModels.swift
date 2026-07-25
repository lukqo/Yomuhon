//
//  DeclarativeSourceModels.swift
//  Yomuhon
//
//  Codable contract mirrored from Yomuhon-Sources schema v1.
//

import Foundation

enum DeclarativeSourceError: LocalizedError {
    case unsupportedSchema(Int)
    case minimumAppVersion(String)
    case invalidConfiguration(String)
    case invalidURL(String)
    case invalidResponse
    case missingRoute(String)
    case missingSelector(String)
    case noResults(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "Unsupported source schema version: \(version)"
        case .minimumAppVersion(let version):
            return "This source catalog requires Yomuhon \(version) or newer."
        case .invalidConfiguration(let message):
            return "Invalid source configuration: \(message)"
        case .invalidURL(let value):
            return "Blocked or invalid source URL: \(value)"
        case .invalidResponse:
            return "The source did not return a readable HTML document."
        case .missingRoute(let name):
            return "The source is missing the \(name) route."
        case .missingSelector(let name):
            return "The source is missing the \(name) selector."
        case .noResults(let stage):
            return "The source returned no \(stage)."
        }
    }
}

/// Network policy for remotely described sources.
///
/// Source JSON is controlled by the Yomuhon catalog, so `allowedDomains` is an
/// expected-host diagnostic rather than a hard runtime allowlist. Runtime URLs
/// still have to be public HTTPS destinations: loopback, private/link-local
/// addresses and common local-only hostnames are rejected.
enum DeclarativeNetworkURLPolicy {
    static func permits(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = normalizedHost(url.host),
              !isBlockedHost(host)
        else {
            return false
        }

        return true
    }

    static func isExpectedHost(_ host: String?, allowedDomains: [String]) -> Bool {
        guard let host = normalizedHost(host) else { return false }

        return allowedDomains.contains { domain in
            guard let expected = normalizedHost(domain) else { return false }
            return host == expected || host.hasSuffix(".\(expected)")
        }
    }

    private static func normalizedHost(_ host: String?) -> String? {
        guard var host = host?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty
        else {
            return nil
        }

        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if host.hasPrefix("[") && host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }
        if let zoneIndex = host.firstIndex(of: "%") {
            host = String(host[..<zoneIndex])
        }
        return host.isEmpty ? nil : host
    }

    private static func isBlockedHost(_ host: String) -> Bool {
        let localNames = [
            "localhost",
            "home.arpa",
            ".localhost",
            ".local",
            ".localdomain",
            ".lan",
            ".internal",
            ".home.arpa"
        ]

        if localNames.contains(where: { suffix in
            suffix.hasPrefix(".") ? host.hasSuffix(suffix) : host == suffix
        }) {
            return true
        }

        if let octets = ipv4Octets(host) {
            return isBlockedIPv4(octets)
        }

        if host.contains(":") {
            return isBlockedIPv6(host)
        }

        // A single-label hostname is normally local/search-domain scoped rather
        // than an Internet host. Declarative sources only need public origins.
        return !host.contains(".")
    }

    private static func ipv4Octets(_ host: String) -> [Int]? {
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else { return nil }

        let octets = components.compactMap { component -> Int? in
            guard !component.isEmpty,
                  component.allSatisfy({ $0.isNumber }),
                  let value = Int(component),
                  (0...255).contains(value)
            else {
                return nil
            }
            return value
        }

        return octets.count == 4 ? octets : nil
    }

    private static func isBlockedIPv4(_ octets: [Int]) -> Bool {
        let a = octets[0]
        let b = octets[1]
        let c = octets[2]

        if a == 0 || a >= 224 { return true }
        if a == 10 || a == 127 { return true }
        if a == 100 && (64...127).contains(b) { return true }
        if a == 169 && b == 254 { return true }
        if a == 172 && (16...31).contains(b) { return true }
        if a == 192 && b == 168 { return true }
        if a == 192 && b == 0 && [0, 2].contains(c) { return true }
        if a == 192 && b == 88 && c == 99 { return true }
        if a == 198 && (18...19).contains(b) { return true }
        if a == 198 && b == 51 && c == 100 { return true }
        if a == 203 && b == 0 && c == 113 { return true }

        return false
    }

    private static func isBlockedIPv6(_ host: String) -> Bool {
        let value = host.lowercased()

        if value == "::" || value == "::1" { return true }
        if value.hasPrefix("fc") || value.hasPrefix("fd") { return true }
        if ["fe8", "fe9", "fea", "feb"].contains(where: value.hasPrefix) { return true }
        if value.hasPrefix("ff") { return true }
        if value.hasPrefix("2001:db8:") || value == "2001:db8::" { return true }

        if let mappedIPv4 = value.split(separator: ":").last.map(String.init),
           let octets = ipv4Octets(mappedIPv4) {
            return isBlockedIPv4(octets)
        }

        return false
    }
}

enum DeclarativeEngineMode: String, Codable {
    case html
    case jsonAPI = "json-api"
}

enum DeclarativeSourceOperation {
    case popular
    case search
    case details
    case chapters
    case pages
    case genres
}

struct DeclarativeOperationModes: Codable {
    let popular: DeclarativeEngineMode?
    let search: DeclarativeEngineMode?
    let details: DeclarativeEngineMode?
    let chapters: DeclarativeEngineMode?
    let pages: DeclarativeEngineMode?
    let genres: DeclarativeEngineMode?

    func mode(for operation: DeclarativeSourceOperation) -> DeclarativeEngineMode? {
        switch operation {
        case .popular: return popular
        case .search: return search
        case .details: return details
        case .chapters: return chapters
        case .pages: return pages
        case .genres: return genres
        }
    }
}

struct DeclarativeSourceIndex: Codable {
    let schemaVersion: Int
    let updatedAt: String
    let minimumAppVersion: String
    let sources: [DeclarativeSourceIndexEntry]
}

struct DeclarativeSourceIndexEntry: Codable, Identifiable {
    let id: String
    let name: String
    let version: Int
    let language: String
    let kind: String
    let url: URL
    let enabled: Bool
    let experimental: Bool
    let status: String
    let allowedDomains: [String]
    let notes: String?
}

struct DeclarativeSourceConfig: Codable, Identifiable {
    let schemaVersion: Int
    let id: String
    let name: String
    let version: Int
    let language: String
    let baseURL: URL
    let engineMode: DeclarativeEngineMode
    /// Optional per-operation runtime overrides. When omitted, `engineMode`
    /// remains the source-wide fallback so all existing schema-v1 definitions
    /// continue to decode unchanged.
    let operationModes: DeclarativeOperationModes?
    /// Optional identity/canonicalization rules for source URLs. By default,
    /// transient query strings are removed. Sources that encode a stable title
    /// identifier in the query may declare only those public query-item names
    /// that must survive canonicalization.
    let identity: DeclarativeIdentityConfig?
    /// Legacy schema-v1 field. Publication is controlled by index.enabled/status.
    /// Missing/false are accepted for backward compatibility; true is rejected.
    let enabledByDefault: Bool?
    let experimental: Bool
    let allowedDomains: [String]
    let supports: DeclarativeSourceSupports
    let network: DeclarativeNetworkConfig?
    let routes: DeclarativeRoutes
    let selectors: DeclarativeSelectors
    let api: DeclarativeAPIConfig?
    let discover: DeclarativeDiscoverConfig?
    let cleanup: DeclarativeCleanupConfig?
    let tests: DeclarativeSourceTests?
}

struct DeclarativeIdentityConfig: Codable {
    let preserveQueryItems: [String]?
}

struct DeclarativeSourceSupports: Codable {
    let search: Bool
    let popular: Bool
    let details: Bool
    let chapters: Bool
    let pages: Bool
    let genres: Bool?

    var supportsGenres: Bool { genres == true }
}

struct DeclarativeNetworkConfig: Codable {
    let headers: [String: String]?
}

struct DeclarativeRoutes: Codable {
    let popular: DeclarativeRoute?
    let search: DeclarativeRoute?
}

struct DeclarativeRoute: Codable {
    let path: String
    let query: [String: String]?
    let pagination: DeclarativePagination?
}

struct DeclarativePagination: Codable {
    let type: String
    let param: String?
    let start: Int?
    let maxPages: Int?
}

struct DeclarativeSelectors: Codable {
    let popular: DeclarativeListSelector?
    let search: DeclarativeListSelector?
    let details: DeclarativeDetailSelector?
    let chapters: DeclarativeChapterSelector?
    let pages: DeclarativePagesSelector?
}

struct DeclarativeListSelector: Codable {
    let container: String
    let title: DeclarativeFieldSelector
    let url: DeclarativeFieldSelector
    let cover: DeclarativeFieldSelector?
    let alternativeTitles: DeclarativeFieldSelector?
    let author: DeclarativeFieldSelector?
    let year: DeclarativeFieldSelector?
    let htmlScope: DeclarativeHTMLScope?
}

/// Optional raw-HTML window applied before CSS list selection.
///
/// This stays fully declarative: a source can point a list operation at a named
/// section of a page (for example a "Hot Manga" shelf) without source-specific
/// Swift code or requiring unsupported sibling CSS selectors.
struct DeclarativeHTMLScope: Codable {
    let afterRegex: String?
    let beforeRegex: String?
}

struct DeclarativeDetailSelector: Codable {
    let title: DeclarativeFieldSelector?
    let synopsis: DeclarativeFieldSelector?
    let cover: DeclarativeFieldSelector?
    let alternativeTitles: DeclarativeFieldSelector?
    let author: DeclarativeFieldSelector?
    let year: DeclarativeFieldSelector?
}

struct DeclarativeChapterSelector: Codable {
    let container: String
    let title: DeclarativeFieldSelector?
    let url: DeclarativeFieldSelector
    let number: DeclarativeNumberRule?
    let sort: String?
}

struct DeclarativePagesSelector: Codable {
    let extractors: [DeclarativePageExtractor]
    let filters: DeclarativeImageFilters?
}

struct DeclarativePageExtractor: Codable {
    let type: String
    let selector: String?
    let attrs: [String]?
    let pattern: String?
}

struct DeclarativeFieldSelector: Codable {
    let selectors: [String]?
    let selector: String?
    let attrs: [String]?
    let attr: String?
    let regex: String?
    let required: Bool?
    let cleanup: [String]?

    var selectorCandidates: [String] {
        if let selectors, !selectors.isEmpty {
            return selectors
        }

        if let selector, !selector.isEmpty {
            return [selector]
        }

        return []
    }

    var attrCandidates: [String] {
        if let attrs, !attrs.isEmpty {
            return attrs
        }

        if let attr, !attr.isEmpty {
            return [attr]
        }

        return ["text"]
    }
}

struct DeclarativeNumberRule: Codable {
    let from: String
    let regex: String
}

struct DeclarativeImageFilters: Codable {
    let mustContain: [String]?
    let blockContains: [String]?
}



// MARK: - Declarative discovery contract

struct DeclarativeDiscoverConfig: Codable {
    let popular: DeclarativeDiscoverOperation?
    let genres: DeclarativeGenreDiscovery?
}

struct DeclarativeDiscoverOperation: Codable {
    let route: DeclarativeRoute?
    let selector: DeclarativeListSelector?
    let api: DeclarativeAPISearchOperation?
}

struct DeclarativeGenreDiscovery: Codable {
    let items: [DeclarativeGenreItem]
    let operation: DeclarativeDiscoverOperation
}

struct DeclarativeGenreItem: Codable {
    let id: String
    let title: String
    let value: String
}

struct DeclarativeCleanupConfig: Codable {
    let decodeHTMLEntities: Bool?
    let normalizeWhitespace: Bool?
    let removeText: [String]?
}

struct DeclarativeSourceTests: Codable {
    let query: String
    let minSearchResults: Int?
    let minChapters: Int?
    let minPages: Int?
}


/// Repository-side `tests/<source>.test.json` contract.
///
/// The authoring repository keeps smoke-test probes separate from source configs.
/// `DeclarativeRemoteConfigLoader` normalizes this definition into
/// `DeclarativeSourceTests` before caching the config, so diagnostics and offline
/// fallback keep using the same repository-authored probe requirements.
struct DeclarativeRepositoryTestDefinition: Codable {
    let sourceID: String
    let queries: [String]
    let probe: DeclarativeRepositoryTestProbe?
    let expected: DeclarativeRepositoryTestExpected

    var runtimeRequirements: DeclarativeSourceTests? {
        let query = probe?.query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackQuery = queries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        guard let selectedQuery = (query?.isEmpty == false ? query : fallbackQuery),
              expected.minSearchResults >= 1,
              expected.minChapters >= 1,
              expected.minPages >= 1
        else {
            return nil
        }

        return DeclarativeSourceTests(
            query: selectedQuery,
            minSearchResults: expected.minSearchResults,
            minChapters: expected.minChapters,
            minPages: expected.minPages
        )
    }
}

struct DeclarativeRepositoryTestProbe: Codable {
    let query: String?
    let expectedTitleContains: String?
    let mangaPathContains: String?
    let chapterPathContains: String?
}

struct DeclarativeRepositoryTestExpected: Codable {
    let minSearchResults: Int
    let minChapters: Int
    let minPages: Int
}

extension DeclarativeSourceConfig {
    func engineMode(for operation: DeclarativeSourceOperation) -> DeclarativeEngineMode {
        operationModes?.mode(for: operation) ?? engineMode
    }

    func replacingTests(_ tests: DeclarativeSourceTests) -> DeclarativeSourceConfig {
        DeclarativeSourceConfig(
            schemaVersion: schemaVersion,
            id: id,
            name: name,
            version: version,
            language: language,
            baseURL: baseURL,
            engineMode: engineMode,
            operationModes: operationModes,
            identity: identity,
            enabledByDefault: enabledByDefault,
            experimental: experimental,
            allowedDomains: allowedDomains,
            supports: supports,
            network: network,
            routes: routes,
            selectors: selectors,
            api: api,
            discover: discover,
            cleanup: cleanup,
            tests: tests
        )
    }
}


// MARK: - Declarative JSON API contract

struct DeclarativeAPIConfig: Codable {
    let search: DeclarativeAPISearchOperation?
    let chapters: DeclarativeAPIChapterOperation?
    let pages: DeclarativeAPIPagesOperation?
}

struct DeclarativeAPIRequest: Codable {
    let method: String?
    /// Optional operation-specific origin. This enables a source to keep its
    /// HTML website as `baseURL` while calling a public JSON endpoint hosted on
    /// another declared domain.
    let baseURL: URL?
    let path: String
    let query: [String: DeclarativeJSONValue]?
}

enum DeclarativeJSONValue: Codable {
    case string(String)
    case strings([String])
    case int(Int)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String].self) { self = .strings(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        throw DecodingError.typeMismatch(DeclarativeJSONValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON query value"))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .strings(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        }
    }
}

struct DeclarativeAPISearchOperation: Codable {
    let request: DeclarativeAPIRequest
    let itemsPath: String
    let idPath: String
    let titlePaths: [String]
    let synopsisPaths: [String]?
    let alternativeTitlePaths: [String]?
    let authorPaths: [String]?
    let yearPath: String?
    let coverRelationshipType: String?
    let coverFilePath: String?
    let coverTemplate: String?
}

struct DeclarativeAPIChapterOperation: Codable {
    let request: DeclarativeAPIRequest
    let pagination: DeclarativeAPIPagination?
    let itemsPath: String
    let idPath: String
    let numberPath: String
    let titlePath: String?
    /// Optional JSON path containing the canonical reader URL for an episode.
    /// It is resolved against the source base URL and persisted on Chapter so a
    /// following HTML pages operation can open it.
    let urlPath: String?
    let languagePath: String?
    /// Declarative variables extracted from the canonical manga URL or manga ID
    /// before expanding the API request path/query.
    let variables: [String: DeclarativeAPIVariableRule]?
    let sort: String?
}

struct DeclarativeAPIVariableRule: Codable {
    let from: String
    let regex: String?
    let defaultValue: String?

    enum CodingKeys: String, CodingKey {
        case from
        case regex
        case defaultValue = "default"
    }
}

struct DeclarativeAPIPagination: Codable {
    let offsetParam: String
    let limitParam: String
    let limit: Int

    /// Optional legacy hard page ceiling. New source definitions should omit it and
    /// let the runtime stop from the response itself. Kept Codable-compatible so
    /// already cached source definitions continue to work.
    let maxPages: Int?

    /// Absolute defensive ceiling for malformed APIs/configurations. This is not a
    /// normal pagination boundary; the runtime otherwise keeps following pages
    /// until the response proves that there is nothing new to fetch.
    let maxItems: Int?

    /// Optional JSON path containing the API-reported total result count.
    let totalPath: String?
}

struct DeclarativeAPIPagesOperation: Codable {
    let request: DeclarativeAPIRequest
    let baseURLPath: String
    let hashPath: String
    let itemsPath: String
    let urlTemplate: String
}

struct DeclarativeRemoteConfigDiagnostics {
    enum State {
        case unknown
        case remote
        case cache
        case offline
        case invalidRemote
    }

    let state: State
    let message: String
    let configCount: Int
}
