//
//  DeclarativeSourceRuntime.swift
//  Yomuhon
//
//  Runtime for `declarative-html` definitions published by Yomuhon-Sources.
//  Its parsing stages intentionally mirror scripts/validate_sources.py:
//  search -> canonical manga URL -> detail HTML -> chapters -> chapter HTML -> pages.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func parseDeclarativeAlternativeTitles(_ raw: String) -> [String] {
    raw
        .components(separatedBy: CharacterSet(charactersIn: "|;\n"))
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .deduplicatedCaseInsensitive
}

private func parseDeclarativeReleaseYear(_ raw: String) -> Int? {
    guard let range = raw.range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression) else {
        return nil
    }
    return Int(raw[range])
}

struct DeclarativeSourceRuntime: Source {
    let config: DeclarativeSourceConfig
    private let dataLoader: (URLRequest) throws -> Data

    var id: String { config.id }
    var name: String { config.name }
    var supportsPopularDiscovery: Bool { config.supports.popular }
    var supportsGenreDiscovery: Bool {
        config.supports.supportsGenres && config.discover?.genres != nil
    }
    var discoveryGenres: [SourceDiscoveryGenre] {
        guard supportsGenreDiscovery else { return [] }
        return (config.discover?.genres?.items ?? []).map {
            SourceDiscoveryGenre(id: $0.id, title: $0.title)
        }
    }

    init(config: DeclarativeSourceConfig, httpClient: HTTPClient = HTTPClient(timeout: 10, maximumRetryCount: 0)) {
        self.config = config
        self.dataLoader = { request in
            try httpClient.data(for: request)
        }
    }

    init(config: DeclarativeSourceConfig, dataLoader: @escaping (URLRequest) throws -> Data) {
        self.config = config
        self.dataLoader = dataLoader
    }

    func popularManga() throws -> [Manga] {
        guard supportsPopularDiscovery else { return [] }

        if config.engineMode == .jsonAPI {
            guard let operation = config.discover?.popular?.api else {
                throw DeclarativeSourceError.missingRoute("discover.popular.api")
            }
            return try JSONAPISourceExecutor(config: config, dataLoader: dataLoader)
                .list(operation: operation, variables: [:])
        }

        let explicit = config.discover?.popular
        guard let route = explicit?.route ?? config.routes.popular else {
            throw DeclarativeSourceError.missingRoute("popular")
        }
        guard let selector = explicit?.selector ?? config.selectors.popular else {
            throw DeclarativeSourceError.missingSelector("popular")
        }

        let mangas = try parseMangaList(
            route: route,
            selector: selector,
            variables: [:],
            stage: "POPULAR"
        )
        SourceDebugTrace.log(
            "Runtime",
            "source=\(id) POPULAR html count=\(mangas.count) covers=\(mangas.filter { $0.coverURL != nil }.count)"
        )
        return mangas
    }

    func manga(forGenreID genreID: String) throws -> [Manga] {
        guard supportsGenreDiscovery,
              let genres = config.discover?.genres,
              let item = genres.items.first(where: { $0.id == genreID })
        else {
            return []
        }

        let variables = ["genre": item.value]
        if config.engineMode == .jsonAPI {
            guard let operation = genres.operation.api else {
                throw DeclarativeSourceError.missingRoute("discover.genres.operation.api")
            }
            return try JSONAPISourceExecutor(config: config, dataLoader: dataLoader)
                .list(operation: operation, variables: variables)
        }

        guard let route = genres.operation.route else {
            throw DeclarativeSourceError.missingRoute("discover.genres.operation.route")
        }
        guard let selector = genres.operation.selector else {
            throw DeclarativeSourceError.missingSelector("discover.genres.operation.selector")
        }
        let mangas = try parseMangaList(
            route: route,
            selector: selector,
            variables: variables,
            stage: "GENRE id=\(genreID)"
        )
        SourceDebugTrace.log(
            "Runtime",
            "source=\(id) GENRE id=\(genreID) html count=\(mangas.count) covers=\(mangas.filter { $0.coverURL != nil }.count)"
        )
        return mangas
    }

    func searchManga(query: String) throws -> [Manga] {
        SourceDebugTrace.log("Runtime", "source=\(id) SEARCH engine=\(config.engineMode.rawValue) query=\(query)")
        if config.engineMode == .jsonAPI {
            let mangas = try JSONAPISourceExecutor(config: config, dataLoader: dataLoader).search(query: query)
            SourceDebugTrace.log("Runtime", "source=\(id) SEARCH json count=\(mangas.count)")
            return mangas
        }
        guard config.supports.search else { return [] }
        guard let route = config.routes.search else {
            throw DeclarativeSourceError.missingRoute("search")
        }
        guard let selector = config.selectors.search else {
            throw DeclarativeSourceError.missingSelector("search")
        }

        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        let mangas = try parseMangaList(route: route, selector: selector, variables: ["query": query], stage: "SEARCH")
        SourceDebugTrace.log("Runtime", "source=\(id) SEARCH html count=\(mangas.count)")
        return mangas
    }

    func fetchDetails(for manga: Manga) throws -> Manga {
        SourceDebugTrace.log(
            "Runtime",
            "source=\(id) DETAIL start mangaID=\(manga.id) title=\(manga.title) marker=\(manga.declarativeSourceURL?.absoluteString ?? "nil") engine=\(config.engineMode.rawValue)"
        )
        if config.engineMode == .jsonAPI {
            var copy = manga
            copy.chapters = try JSONAPISourceExecutor(config: config, dataLoader: dataLoader).chapters(for: manga)
            SourceDebugTrace.log("Runtime", "source=\(id) DETAIL json chapters=\(copy.chapters.count)")
            return copy
        }
        guard config.supports.details || config.supports.chapters else {
            return manga
        }
        guard let mangaURL = manga.declarativeSourceURL else {
            throw DeclarativeSourceError.invalidConfiguration("Missing canonical manga URL for \(manga.id)")
        }

        let document = try fetchDocument(at: mangaURL)
        let detailsSelector = config.selectors.details
        SourceDebugTrace.log(
            "Runtime",
            "source=\(id) DETAIL documentReady rawBytesApprox=\(document.rawHTML.utf8.count) chapterSelector=\(config.selectors.chapters?.container ?? "nil") selectorSupported=\(config.selectors.chapters.map { SimpleHTMLDocument.supports($0.container) } ?? false)"
        )

        let rawTitle = detailsSelector?.title.flatMap { extractField($0, from: document) }
        let title = normalizedMangaTitle(rawTitle ?? manga.title, mangaURL: mangaURL, originalURL: mangaURL)
        let synopsis = detailsSelector?.synopsis
            .flatMap { extractField($0, from: document) }
            ?? manga.declarativeCleanSynopsis
        let coverURL = detailsSelector?.cover
            .flatMap { extractField($0, from: document) }
            .flatMap { resolveURL($0, relativeTo: mangaURL, enforceAllowedHost: true) }
            ?? manga.coverURL
        let alternativeTitles = detailsSelector?.alternativeTitles
            .flatMap { extractField($0, from: document) }
            .map { parseDeclarativeAlternativeTitles($0) }
            ?? manga.alternativeTitles
        let author = detailsSelector?.author
            .flatMap { extractField($0, from: document) }
            ?? manga.author
        let releaseYear = detailsSelector?.year
            .flatMap { extractField($0, from: document) }
            .flatMap { parseDeclarativeReleaseYear($0) }
            ?? manga.releaseYear

        let resolvedChapters: [Chapter]
        if config.supports.chapters, let chapterSelector = config.selectors.chapters {
            resolvedChapters = parseChapters(document: document, manga: manga, mangaURL: mangaURL, selector: chapterSelector)
            SourceDebugTrace.log("Runtime", "source=\(id) DETAIL parsedChapters=\(resolvedChapters.count)")
            guard !resolvedChapters.isEmpty else {
                throw DeclarativeSourceError.noResults("chapters")
            }
        } else {
            resolvedChapters = manga.chapters
        }

        return Manga(
            id: manga.id,
            sourceID: manga.sourceID,
            title: title.isEmpty ? manga.title : title,
            coverURL: coverURL,
            synopsis: synopsis,
            alternativeTitles: alternativeTitles,
            author: author,
            releaseYear: releaseYear,
            chapters: resolvedChapters
        )
        .withDeclarativeSourceURL(mangaURL)
    }

    func fetchChapters(for manga: Manga) throws -> [Chapter] {
        if config.engineMode == .jsonAPI { return try JSONAPISourceExecutor(config: config, dataLoader: dataLoader).chapters(for: manga) }
        guard config.supports.chapters else { return manga.chapters }
        guard let selector = config.selectors.chapters else {
            throw DeclarativeSourceError.missingSelector("chapters")
        }
        guard let mangaURL = manga.declarativeSourceURL else {
            throw DeclarativeSourceError.invalidConfiguration("Missing canonical manga URL for \(manga.id)")
        }

        let document = try fetchDocument(at: mangaURL)
        let chapters = parseChapters(document: document, manga: manga, mangaURL: mangaURL, selector: selector)
        guard !chapters.isEmpty else {
            throw DeclarativeSourceError.noResults("chapters")
        }
        return chapters
    }

    func fetchPages(for chapter: Chapter, manga: Manga) throws -> [Page] {
        if config.engineMode == .jsonAPI {
            SourceDebugTrace.log(
                "Pages",
                "source=\(id) START engine=json-api manga=\(manga.id) chapter=\(chapter.id) number=\(chapter.number)"
            )
            let pages = try JSONAPISourceExecutor(config: config, dataLoader: dataLoader)
                .pages(for: chapter, manga: manga)
            SourceDebugTrace.log(
                "Pages",
                "source=\(id) SUCCESS engine=json-api manga=\(manga.id) chapter=\(chapter.id) count=\(pages.count)"
            )
            return pages
        }

        guard config.supports.pages else { return chapter.pages }
        guard let selector = config.selectors.pages else {
            throw DeclarativeSourceError.missingSelector("pages")
        }
        guard let chapterURL = chapter.declarativeSourceURL else {
            SourceDebugTrace.log(
                "Pages",
                "source=\(id) chapter=\(chapter.id) manga=\(manga.id) missingChapterURL=true"
            )
            throw DeclarativeSourceError.invalidConfiguration("Missing chapter URL for \(chapter.id)")
        }

        SourceDebugTrace.log(
            "Pages",
            "source=\(id) START engine=html manga=\(manga.id) chapter=\(chapter.id) number=\(chapter.number) url=\(chapterURL.absoluteString)"
        )
        let document = try fetchDocument(at: chapterURL)
        let urls = parsePageURLs(document: document, chapterURL: chapterURL, selector: selector)
        guard !urls.isEmpty else {
            SourceDebugTrace.log(
                "Pages",
                "source=\(id) EMPTY manga=\(manga.id) chapter=\(chapter.id) url=\(chapterURL.absoluteString) htmlBytes=\(document.rawHTML.utf8.count)"
            )
            throw DeclarativeSourceError.noResults("pages")
        }

        SourceDebugTrace.log(
            "Pages",
            "source=\(id) SUCCESS engine=html manga=\(manga.id) chapter=\(chapter.id) count=\(urls.count) hosts=\(Array(Set(urls.compactMap { $0.host })).sorted())"
        )
        return urls.enumerated().map { index, url in
            Page(
                id: "\(chapter.id)-\(index)",
                index: index,
                imageURL: url,
                localFileURL: nil
            )
        }
    }

    // MARK: - Search / list parsing

    private func parseMangaList(
        route: DeclarativeRoute,
        selector: DeclarativeListSelector,
        variables: [String: String],
        stage: String
    ) throws -> [Manga] {
        var mangaByURL: [String: Manga] = [:]
        var orderedKeys: [String] = []

        for url in routeURLs(route: route, variables: variables) {
            let document = try fetchDocument(at: url)
            let scopedDocument = scopedListDocument(document, selector: selector)
            let selectedItems = scopedDocument.select(selector.container)
            var rejectedURLCount = 0
            var rejectedTitleCount = 0

            for item in selectedItems {
                let rawURL = extractField(selector.url, from: item) ?? item.attr("href")
                guard let rawURL,
                      let originalURL = resolveURL(rawURL, relativeTo: url, enforceAllowedHost: true)
                else {
                    rejectedURLCount += 1
                    continue
                }

                let mangaURL = canonicalMangaURL(originalURL)
                let key = mangaURL.absoluteString
                let fallbackTitle = mangaTitleFromURL(mangaURL)
                let rawTitle = extractField(selector.title, from: item) ?? item.text
                let title = normalizedMangaTitle(rawTitle, mangaURL: mangaURL, originalURL: originalURL)
                guard !title.isEmpty else {
                    rejectedTitleCount += 1
                    continue
                }

                let coverURL = selector.cover
                    .flatMap { extractField($0, from: item) }
                    .flatMap { resolveURL($0, relativeTo: url, enforceAllowedHost: true) }
                let alternativeTitles = selector.alternativeTitles
                    .flatMap { extractField($0, from: item) }
                    .map { parseDeclarativeAlternativeTitles($0) }
                let author = selector.author
                    .flatMap { extractField($0, from: item) }
                let releaseYear = selector.year
                    .flatMap { extractField($0, from: item) }
                    .flatMap { parseDeclarativeReleaseYear($0) }

                let candidate = Manga(
                    id: "\(id)-\(key.yomuhonStableIdentifier)",
                    sourceID: id,
                    title: title,
                    coverURL: coverURL,
                    synopsis: nil,
                    alternativeTitles: alternativeTitles,
                    author: author,
                    releaseYear: releaseYear,
                    chapters: []
                )
                .withDeclarativeSourceURL(mangaURL)

                if let existing = mangaByURL[key] {
                    let existingUsesFallback = existing.title.caseInsensitiveCompare(fallbackTitle) == .orderedSame
                    let candidateUsesFallback = candidate.title.caseInsensitiveCompare(fallbackTitle) == .orderedSame
                    let preferredTitle: String
                    if existingUsesFallback && !candidateUsesFallback {
                        preferredTitle = candidate.title
                    } else if !existingUsesFallback && candidateUsesFallback {
                        preferredTitle = existing.title
                    } else {
                        preferredTitle = candidate.title.count > existing.title.count
                            ? candidate.title
                            : existing.title
                    }

                    mangaByURL[key] = Manga(
                        id: existing.id,
                        sourceID: existing.sourceID,
                        title: preferredTitle,
                        coverURL: existing.coverURL ?? candidate.coverURL,
                        synopsis: existing.synopsis ?? candidate.synopsis,
                        alternativeTitles: mergedAlternativeTitles(existing.alternativeTitles, candidate.alternativeTitles),
                        author: existing.author ?? candidate.author,
                        releaseYear: existing.releaseYear ?? candidate.releaseYear,
                        chapters: existing.chapters.isEmpty ? candidate.chapters : existing.chapters
                    )
                    .withDeclarativeSourceURL(mangaURL)
                } else {
                    mangaByURL[key] = candidate
                    orderedKeys.append(key)
                }

                if orderedKeys.count >= 64 { break }
            }

            let current = orderedKeys.compactMap { mangaByURL[$0] }
            SourceDebugTrace.log(
                "Parser",
                "source=\(id) LIST stage=\(stage) selector=\(selector.container) supported=\(SimpleHTMLDocument.supports(selector.container)) matched=\(selectedItems.count) results=\(current.count) covers=\(current.filter { $0.coverURL != nil }.count) rejectedURL=\(rejectedURLCount) rejectedTitle=\(rejectedTitleCount) scoped=\(selector.htmlScope != nil) url=\(url.absoluteString)"
            )

            if orderedKeys.count >= 64 { break }
        }

        return orderedKeys.compactMap { mangaByURL[$0] }
    }

    private func mergedAlternativeTitles(_ lhs: [String]?, _ rhs: [String]?) -> [String]? {
        var mergedValues: [String] = lhs ?? []
        if let rhs {
            mergedValues.append(contentsOf: rhs)
        }
        let merged = mergedValues.deduplicatedCaseInsensitive
        return merged.isEmpty ? nil : merged
    }

    private func scopedListDocument(
        _ document: YomuhonHTMLDocument,
        selector: DeclarativeListSelector
    ) -> YomuhonHTMLDocument {
        guard let scope = selector.htmlScope else {
            return document
        }

        var html = document.rawHTML
        if let afterRegex = scope.afterRegex {
            guard let suffix = htmlSuffix(afterFirstMatchOf: afterRegex, in: html) else {
                SourceDebugTrace.log(
                    "Parser",
                    "source=\(id) LIST_SCOPE missing afterRegex=\(afterRegex)"
                )
                return SimpleHTMLDocument(html: "")
            }
            html = suffix
        }

        if let beforeRegex = scope.beforeRegex,
           let prefix = htmlPrefix(beforeFirstMatchOf: beforeRegex, in: html) {
            html = prefix
        }

        return SimpleHTMLDocument(html: html)
    }

    private func htmlSuffix(afterFirstMatchOf pattern: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range, in: html)
        else {
            return nil
        }
        return String(html[range.upperBound...])
    }

    private func htmlPrefix(beforeFirstMatchOf pattern: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range, in: html)
        else {
            return nil
        }
        return String(html[..<range.lowerBound])
    }

    private func canonicalMangaURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var parts = components.path.split(separator: "/").map(String.init)
        if let last = parts.last, last.yomuhonIsChapterPathComponent {
            parts.removeLast()
        }

        components.path = "/" + parts.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }

    private func normalizedMangaTitle(_ rawTitle: String, mangaURL: URL, originalURL: URL) -> String {
        let cleaned = rawTitle
            .removingYomuhonSourceMarkers
            .yomuhonStripHTML()
            .yomuhonDecodeHTMLEntities()
            .yomuhonNormalizeWhitespace()
        let lowered = cleaned.lowercased()
        let blocked: Set<String> = ["[cover]", "cover", "image", "poster", "manga"]

        if cleaned.isEmpty || blocked.contains(lowered) || cleaned.yomuhonLooksLikeChapterTitle || mangaURL != originalURL {
            return mangaTitleFromURL(mangaURL)
        }

        return cleaned.removingTrailingSourceNumericIdentifier
    }

    private func mangaTitleFromURL(_ url: URL) -> String {
        let slug = url.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .last
            .map(String.init) ?? "untitled"

        return slug
            .replacingOccurrences(of: #"\.[0-9]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[-_]+"#, with: " ", options: .regularExpression)
            .yomuhonNormalizeWhitespace()
            .capitalized
    }

    // MARK: - Chapter parsing

    private func parseChapters(
        document: YomuhonHTMLDocument,
        manga: Manga,
        mangaURL: URL,
        selector: DeclarativeChapterSelector
    ) -> [Chapter] {
        var output: [Chapter] = []
        var seenURLs = Set<String>()
        var rejectedByNumberRule = 0
        let selectedItems = document.select(selector.container)
        SourceDebugTrace.log(
            "Parser",
            "source=\(id) CHAPTER_SELECTOR selector=\(selector.container) supported=\(SimpleHTMLDocument.supports(selector.container)) matched=\(selectedItems.count) mangaURL=\(mangaURL.absoluteString)"
        )

        for item in selectedItems {
            let rawURL = extractField(selector.url, from: item) ?? item.attr("href")
            guard let rawURL,
                  let chapterURL = resolveURL(rawURL, relativeTo: mangaURL, enforceAllowedHost: true)
            else {
                continue
            }

            let rawTitle = selector.title.flatMap { extractField($0, from: item) } ?? item.text
            guard isChapterCandidate(url: chapterURL, title: rawTitle) else { continue }

            let key = chapterURL.absoluteString
            guard seenURLs.insert(key).inserted else { continue }

            guard let number = chapterNumber(title: rawTitle, url: key, rule: selector.number) else {
                rejectedByNumberRule += 1
                continue
            }
            let title = cleanChapterTitle(rawTitle, mangaTitle: manga.title)

            let chapter = Chapter(
                id: "\(id)-\(key.yomuhonStableIdentifier)",
                mangaID: manga.id,
                number: number,
                title: title.isEmpty ? nil : title,
                pages: [],
                isDownloaded: false
            )
            .withDeclarativeSourceURL(chapterURL)

            output.append(chapter)
        }

        let ascending = output.sorted { lhs, rhs in
            if lhs.number != rhs.number { return lhs.number < rhs.number }
            return lhs.id < rhs.id
        }

        SourceDebugTrace.log(
            "Parser",
            "source=\(id) CHAPTER_RESULT accepted=\(ascending.count) rejectedNumberRule=\(rejectedByNumberRule) sample=\(ascending.prefix(3).map { $0.number })"
        )

        if selector.sort == "numberDescending" {
            return Array(ascending.reversed())
        }

        return ascending
    }

    private func isChapterCandidate(url: URL, title: String) -> Bool {
        let last = url.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .last
            .map(String.init) ?? ""
        let value = url.absoluteString.lowercased()

        return last.yomuhonIsChapterPathComponent
            || value.contains("/chapters/")
            || value.contains("/chapter/")
            || title.yomuhonLooksLikeChapterTitle
    }

    private func chapterNumber(title: String, url: String, rule: DeclarativeNumberRule?) -> Double? {
        if let rule {
            let source = rule.from == "url" ? url : title
            guard let value = source.yomuhonFirstRegexCapture(pattern: rule.regex),
                  let number = Double(value)
            else {
                // A declared number rule is part of the source contract. If the
                // candidate does not satisfy it, it is not a chapter for this
                // selector and must not fall through to generic heuristics.
                return nil
            }
            return number
        }

        let source = "\(title) \(url)"
        for pattern in [
            #"chapter[-\s_]*([0-9]+(?:\.[0-9]+)?)"#,
            #"ch\.?[-\s_]*([0-9]+(?:\.[0-9]+)?)"#,
            #"/c([0-9]+(?:\.[0-9]+)?)"#,
            #"([0-9]+(?:\.[0-9]+)?)"#
        ] {
            if let value = source.yomuhonFirstRegexCapture(pattern: pattern),
               let number = Double(value) {
                return number
            }
        }

        return 0
    }

    private func cleanChapterTitle(_ rawTitle: String, mangaTitle: String) -> String {
        var value = rawTitle
            .yomuhonStripHTML()
            .yomuhonDecodeHTMLEntities()
            .yomuhonNormalizeWhitespace()

        let foldedMangaTitle = mangaTitle
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .yomuhonNormalizeWhitespace()
        let foldedValue = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .yomuhonNormalizeWhitespace()

        if !foldedMangaTitle.isEmpty, foldedValue.hasPrefix(foldedMangaTitle) {
            value = String(value.dropFirst(min(value.count, mangaTitle.count))).yomuhonNormalizeWhitespace()
        }

        return value
            .replacingOccurrences(of: #"^read\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+online$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .yomuhonNormalizeWhitespace()
    }

    // MARK: - Page parsing

    private func parsePageURLs(
        document: YomuhonHTMLDocument,
        chapterURL: URL,
        selector: DeclarativePagesSelector
    ) -> [URL] {
        var output: [URL] = []
        var seenURLs = Set<String>()
        var rejectedHosts = Set<String>()
        var totalRawCandidates = 0
        var totalInvalidURLs = 0
        var totalRejectedByHost = 0
        var totalRejectedByFilter = 0

        func accept(_ rawCandidate: String) {
            totalRawCandidates += 1

            guard let url = resolveURL(
                rawCandidate,
                relativeTo: chapterURL,
                enforceAllowedHost: false
            ) else {
                totalInvalidURLs += 1
                return
            }

            guard isAllowedHost(url.host) else {
                totalRejectedByHost += 1
                if let host = url.host, rejectedHosts.count < 6 {
                    rejectedHosts.insert(host)
                }
                return
            }

            guard isAllowedImage(url, filters: selector.filters) else {
                totalRejectedByFilter += 1
                return
            }

            let key = url.absoluteString
            if seenURLs.insert(key).inserted {
                output.append(url)
            }
        }

        for (extractorIndex, extractor) in selector.extractors.enumerated() {
            let countBeforeExtractor = output.count
            let candidatesBeforeExtractor = totalRawCandidates

            switch extractor.type {
            case "css":
                guard let css = extractor.selector else { continue }
                let attrs = extractor.attrs ?? ["data-src", "data-original", "data-lazy-src", "srcset", "src"]
                let elements = document.select(css)

                for element in elements {
                    for attr in attrs {
                        guard let rawValue = element.attr(attr) else { continue }
                        for candidate in imageCandidates(rawValue) {
                            accept(candidate)
                        }
                    }
                }

                SourceDebugTrace.log(
                    "Parser",
                    "source=\(id) PAGE_EXTRACTOR index=\(extractorIndex) type=css selector=\(css) elements=\(elements.count) rawCandidates=\(totalRawCandidates - candidatesBeforeExtractor) accepted=\(output.count - countBeforeExtractor)"
                )

            case "regex":
                guard let pattern = extractor.pattern else { continue }
                let matches = document.rawHTML.yomuhonRegexMatches(pattern: pattern)
                for match in matches where match.count > 1 {
                    let candidate = match[1]
                        .yomuhonDecodeJavaScriptEscapes()
                        .replacingOccurrences(of: "&amp;", with: "&")
                    accept(candidate)
                }

                SourceDebugTrace.log(
                    "Parser",
                    "source=\(id) PAGE_EXTRACTOR index=\(extractorIndex) type=regex matches=\(matches.count) rawCandidates=\(totalRawCandidates - candidatesBeforeExtractor) accepted=\(output.count - countBeforeExtractor)"
                )

            default:
                SourceDebugTrace.log(
                    "Parser",
                    "source=\(id) PAGE_EXTRACTOR index=\(extractorIndex) unsupportedType=\(extractor.type)"
                )
            }
        }

        SourceDebugTrace.log(
            "Parser",
            "source=\(id) PAGE_RESULT accepted=\(output.count) rawCandidates=\(totalRawCandidates) invalidURL=\(totalInvalidURLs) rejectedHost=\(totalRejectedByHost) rejectedFilter=\(totalRejectedByFilter) rejectedHosts=\(Array(rejectedHosts).sorted())"
        )
        return output
    }

    private func imageCandidates(_ rawValue: String) -> [String] {
        rawValue.split(separator: ",").compactMap { item in
            item
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: { $0.isWhitespace })
                .first
                .map(String.init)?
                .yomuhonDecodeJavaScriptEscapes()
                .replacingOccurrences(of: "&amp;", with: "&")
        }
    }

    private func isAllowedImage(_ url: URL, filters: DeclarativeImageFilters?) -> Bool {
        let value = url.absoluteString.lowercased()
        let required = (filters?.mustContain ?? []).map { $0.lowercased() }
        if !required.isEmpty, !required.contains(where: value.contains) {
            return false
        }

        return !(filters?.blockContains ?? []).contains { value.contains($0.lowercased()) }
    }

    // MARK: - Field extraction

    private func extractField(_ field: DeclarativeFieldSelector, from scope: YomuhonHTMLScope) -> String? {
        if let regex = field.regex,
           let value = scope.html.yomuhonFirstRegexCapture(pattern: regex) {
            return cleanup(value, pipeline: field.cleanup)
        }

        let candidates: [YomuhonHTMLScope]
        if field.selectorCandidates.isEmpty {
            candidates = [scope]
        } else {
            candidates = field.selectorCandidates.compactMap { scope.first($0) }
        }

        for candidate in candidates {
            for attr in field.attrCandidates {
                if let value = candidate.attr(attr),
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return cleanup(value, pipeline: field.cleanup)
                }
            }
        }

        return nil
    }

    private func cleanup(_ value: String, pipeline: [String]?) -> String {
        var value = value

        if config.cleanup?.decodeHTMLEntities ?? true {
            value = value.yomuhonDecodeHTMLEntities()
        }

        for text in config.cleanup?.removeText ?? [] {
            value = value.replacingOccurrences(of: text, with: "")
        }

        for step in pipeline ?? [] {
            switch step {
            case "stripHTML":
                value = value.yomuhonStripHTML()
            case "decodeEntities":
                value = value.yomuhonDecodeHTMLEntities()
            case "normalizeWhitespace":
                value = value.yomuhonNormalizeWhitespace()
            case "trim":
                value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            default:
                continue
            }
        }

        if config.cleanup?.normalizeWhitespace ?? true {
            value = value.yomuhonNormalizeWhitespace()
        }

        return value
    }

    // MARK: - Requests / routes

    private func fetchDocument(at url: URL) throws -> YomuhonHTMLDocument {
        try validateAllowedURL(url)

        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 Yomuhon/1.0", forHTTPHeaderField: "User-Agent")

        for (key, value) in config.network?.headers ?? [:] {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let startedAt = Date()
        SourceDebugTrace.log("Runtime", "source=\(id) DOCUMENT request url=\(url.absoluteString)")
        let data: Data
        do {
            data = try dataLoader(request)
            SourceDebugTrace.log(
                "Runtime",
                "source=\(id) DOCUMENT response bytes=\(data.count) elapsed=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))s url=\(url.absoluteString)"
            )
        } catch {
            SourceDebugTrace.log(
                "Runtime",
                "source=\(id) DOCUMENT error=\(String(describing: error)) elapsed=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))s url=\(url.absoluteString)"
            )
            throw error
        }
        guard let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        else {
            throw DeclarativeSourceError.invalidResponse
        }

        guard html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") else {
            throw DeclarativeSourceError.invalidResponse
        }

        return SimpleHTMLDocument(html: html)
    }

    private func routeURLs(route: DeclarativeRoute, variables: [String: String]) -> [URL] {
        let start = route.pagination?.start ?? 1
        let maxPages = min(max(route.pagination?.maxPages ?? 1, 1), 5)
        return (start..<(start + maxPages)).compactMap { page in
            routeURL(route: route, variables: variables, page: page)
        }
    }

    private func routeURL(route: DeclarativeRoute, variables: [String: String], page: Int) -> URL? {
        var path = expandRouteTemplate(route.path, variables: variables)
        path = path.replacingOccurrences(of: "{page}", with: String(page))

        let base = config.baseURL.absoluteString.hasSuffix("/")
            ? config.baseURL
            : URL(string: config.baseURL.absoluteString + "/") ?? config.baseURL
        let relativePath = String(path.drop(while: { $0 == "/" }))

        // `URL(string: "", relativeTo:)` returns nil on the Swift/Foundation
        // version used by Xcode 14.2. Treat the repository root explicitly.
        let routeBaseURL: URL
        if relativePath.isEmpty {
            routeBaseURL = base
        } else if let resolvedURL = URL(string: relativePath, relativeTo: base)?.absoluteURL {
            routeBaseURL = resolvedURL
        } else {
            SourceDebugTrace.log(
                "Runtime",
                "source=\(id) ROUTE invalid path=\(route.path) variables=\(variables)"
            )
            return nil
        }

        guard var components = URLComponents(
            url: routeBaseURL,
            resolvingAgainstBaseURL: false
        ) else {
            SourceDebugTrace.log(
                "Runtime",
                "source=\(id) ROUTE components failed url=\(routeBaseURL.absoluteString)"
            )
            return nil
        }

        var queryItems = components.queryItems ?? []
        for (key, rawValue) in route.query ?? [:] {
            let value = expandRouteTemplate(rawValue, variables: variables)
                .replacingOccurrences(of: "{page}", with: String(page))
            queryItems.append(URLQueryItem(name: key, value: value))
        }

        if let pagination = route.pagination,
           pagination.type == "query",
           let param = pagination.param,
           !queryItems.contains(where: { $0.name == param }) {
            queryItems.append(URLQueryItem(name: param, value: String(page)))
        }

        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let resolved = components.url else {
            SourceDebugTrace.log(
                "Runtime",
                "source=\(id) ROUTE URLComponents produced nil path=\(route.path)"
            )
            return nil
        }
        guard isAllowedHost(resolved.host) else {
            SourceDebugTrace.log(
                "Runtime",
                "source=\(id) ROUTE blocked host=\(resolved.host ?? "nil") url=\(resolved.absoluteString)"
            )
            return nil
        }
        return resolved
    }

    private func expandRouteTemplate(_ template: String, variables: [String: String]) -> String {
        variables.reduce(template) { result, pair in
            result
                .replacingOccurrences(of: "{{\(pair.key)}}", with: pair.value)
                .replacingOccurrences(of: "{\(pair.key)}", with: pair.value)
        }
    }

    private func resolveURL(_ rawValue: String, relativeTo contextURL: URL, enforceAllowedHost: Bool) -> URL? {
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .yomuhonDecodeJavaScriptEscapes()
            .replacingOccurrences(of: "&amp;", with: "&")

        guard !value.isEmpty, !value.lowercased().hasPrefix("data:") else { return nil }

        let url: URL?
        if value.hasPrefix("//") {
            url = URL(string: "https:\(value)")
        } else if let absolute = URL(string: value), absolute.scheme != nil {
            url = absolute
        } else {
            url = URL(string: value, relativeTo: contextURL)?.absoluteURL
        }

        guard let url else { return nil }
        if enforceAllowedHost, !isAllowedHost(url.host) { return nil }
        return url
    }

    private func validateAllowedURL(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", isAllowedHost(url.host) else {
            throw DeclarativeSourceError.invalidURL(url.absoluteString)
        }
    }

    private func isAllowedHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) else {
            return false
        }

        return config.allowedDomains.contains { allowedDomain in
            let allowed = allowedDomain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == allowed || host.hasSuffix(".\(allowed)")
        }
    }
}

private extension Array where Element == String {
    var deduplicatedCaseInsensitive: [String] {
        var seen = Set<String>()
        return filter { value in
            let key = value
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }
    }
}

/// Compatibility name retained so existing diagnostics and tests do not need to
/// know that the old regex scraper was replaced by the repository runtime.
typealias DeclarativeHTMLSource = DeclarativeSourceRuntime

extension Manga {
    var declarativeSourceURL: URL? {
        synopsis?
            .components(separatedBy: "\n")
            .first(where: { $0.hasPrefix("yomuhon-declarative-source-url:") })
            .map { $0.replacingOccurrences(of: "yomuhon-declarative-source-url:", with: "") }
            .flatMap(URL.init(string:))
    }

    var declarativeCleanSynopsis: String? {
        synopsis?
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("yomuhon-declarative-source-url:") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func withDeclarativeSourceURL(_ url: URL?) -> Manga {
        guard let url else { return self }

        let marker = "yomuhon-declarative-source-url:\(url.absoluteString)"
        let synopsis = [marker, declarativeCleanSynopsis]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return Manga(
            id: id,
            sourceID: sourceID,
            title: title,
            coverURL: coverURL,
            synopsis: synopsis,
            alternativeTitles: alternativeTitles,
            author: author,
            releaseYear: releaseYear,
            chapters: chapters
        )
    }
}

extension Chapter {
    var declarativeSourceURL: URL? {
        title?
            .components(separatedBy: "\n")
            .first(where: { $0.hasPrefix("yomuhon-declarative-source-url:") })
            .map { $0.replacingOccurrences(of: "yomuhon-declarative-source-url:", with: "") }
            .flatMap(URL.init(string:))
    }

    func withDeclarativeSourceURL(_ url: URL?) -> Chapter {
        guard let url else { return self }

        let marker = "yomuhon-declarative-source-url:\(url.absoluteString)"
        let cleanTitle = title?
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("yomuhon-declarative-source-url:") }
            .joined(separator: "\n")
        let title = [cleanTitle, marker]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return Chapter(
            id: id,
            mangaID: mangaID,
            number: number,
            title: title,
            pages: pages,
            isDownloaded: isDownloaded
        )
    }
}

private extension String {
    var yomuhonLooksLikeChapterTitle: Bool {
        let value = removingYomuhonSourceMarkers
            .yomuhonStripHTML()
            .yomuhonDecodeHTMLEntities()
            .yomuhonNormalizeWhitespace()

        return value.range(
            of: #"^(?:chapter|ch\.?)\s*[0-9]+(?:\.[0-9]+)?(?:\s|:|-|$)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    var yomuhonIsChapterPathComponent: Bool {
        range(
            of: #"^(?:c|ch(?:apter)?[-_ ]?)[0-9]+(?:\.[0-9]+)?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    var yomuhonStableIdentifier: String {
        let allowed = CharacterSet.alphanumerics
        let normalized = unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar).lowercased() : "-"
        }
        .joined()
        .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return normalized.isEmpty ? UUID().uuidString : normalized
    }

    func yomuhonDecodeJavaScriptEscapes() -> String {
        var output = replacingOccurrences(of: "\\/", with: "/")
        guard let regex = try? NSRegularExpression(pattern: #"\\u([0-9A-Fa-f]{4})"#) else {
            return output
        }

        let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output)).reversed()
        for match in matches {
            guard let fullRange = Range(match.range(at: 0), in: output),
                  let valueRange = Range(match.range(at: 1), in: output),
                  let value = UInt32(output[valueRange], radix: 16),
                  let scalar = UnicodeScalar(value)
            else {
                continue
            }
            output.replaceSubrange(fullRange, with: String(Character(scalar)))
        }

        return output
    }
}


// MARK: - Generic declarative JSON API runtime

private struct JSONAPISourceExecutor {
    let config: DeclarativeSourceConfig
    let dataLoader: (URLRequest) throws -> Data

    func search(query: String) throws -> [Manga] {
        guard let operation = config.api?.search else {
            throw DeclarativeSourceError.missingRoute("api.search")
        }
        return try list(operation: operation, variables: ["query": query])
    }

    func list(
        operation: DeclarativeAPISearchOperation,
        variables: [String: String]
    ) throws -> [Manga] {
        let root = try load(operation.request, variables: variables)
        let items = JSONPath.value(operation.itemsPath, in: root) as? [Any] ?? []
        return items.compactMap { item in
            guard let id = JSONPath.string(operation.idPath, in: item) else { return nil }
            let title = operation.titlePaths.lazy
                .compactMap { JSONPath.string($0, in: item) }
                .first(where: { !$0.isEmpty }) ?? ""
            guard !title.isEmpty else { return nil }
            let synopsis = operation.synopsisPaths?.lazy
                .compactMap { JSONPath.string($0, in: item) }
                .first(where: { !$0.isEmpty })
            let alternativeTitles = operation.alternativeTitlePaths?
                .flatMap { JSONPath.strings($0, in: item) }
                .flatMap { parseDeclarativeAlternativeTitles($0) }
                .deduplicatedCaseInsensitive
            let author = operation.authorPaths?.lazy
                .flatMap { JSONPath.strings($0, in: item) }
                .first(where: { !$0.isEmpty })
            let releaseYear = operation.yearPath
                .flatMap { JSONPath.string($0, in: item) }
                .flatMap { parseDeclarativeReleaseYear($0) }
            var coverURL: URL?
            if let type = operation.coverRelationshipType,
               let filePath = operation.coverFilePath,
               let template = operation.coverTemplate,
               let relationships = JSONPath.value("relationships", in: item) as? [Any],
               let relation = relationships.first(where: { JSONPath.string("type", in: $0) == type }),
               let file = JSONPath.string(filePath, in: relation) {
                coverURL = URL(
                    string: expand(
                        template,
                        variables: variables.merging(["mangaID": id, "value": file]) { _, new in new }
                    )
                )
            }
            return Manga(
                id: id,
                sourceID: config.id,
                title: title,
                coverURL: coverURL,
                synopsis: synopsis,
                alternativeTitles: alternativeTitles?.isEmpty == false ? alternativeTitles : nil,
                author: author,
                releaseYear: releaseYear,
                chapters: []
            )
        }
    }

    func chapters(for manga: Manga) throws -> [Chapter] {
        guard let operation = config.api?.chapters else { throw DeclarativeSourceError.missingRoute("api.chapters") }
        var variables = ["mangaID": manga.id]
        let preferred = SourceLanguagePreferenceStore.shared.exactLanguageOverride(mangaID: manga.id, sourceID: config.id)
            .map { [$0] } ?? SourceLanguagePreferenceStore.shared.languageCodes(for: config.id)
        variables["languages"] = preferred.joined(separator: ",")
        var allItems: [Any] = []
        if let pagination = operation.pagination {
            let itemLimit = min(max(pagination.maxItems ?? 10_000, 1), 100_000)
            let legacyPageLimit = pagination.maxPages.map { min(max($0, 1), 1_000) }
            var seenIDs = Set<String>()
            var seenPageSignatures = Set<String>()
            var offset = 0
            var pageCount = 0

            while allItems.count < itemLimit {
                if let legacyPageLimit, pageCount >= legacyPageLimit { break }

                let requestedOffset = offset
                let root = try load(
                    operation.request,
                    variables: variables,
                    arrayVariables: ["languages": preferred],
                    extraQueryItems: [
                        URLQueryItem(name: pagination.offsetParam, value: String(requestedOffset)),
                        URLQueryItem(name: pagination.limitParam, value: String(pagination.limit))
                    ]
                )
                let pageItems = JSONPath.value(operation.itemsPath, in: root) as? [Any] ?? []
                if pageItems.isEmpty { break }

                let pageIDs = pageItems.compactMap { JSONPath.string(operation.idPath, in: $0) }
                let signature = pageIDs.joined(separator: "|")
                if !signature.isEmpty, !seenPageSignatures.insert(signature).inserted { break }

                var newItems = 0
                for item in pageItems {
                    guard let id = JSONPath.string(operation.idPath, in: item), !id.isEmpty else { continue }
                    guard seenIDs.insert(id).inserted else { continue }
                    allItems.append(item)
                    newItems += 1
                    if allItems.count >= itemLimit { break }
                }

                // A repeated page, an API that ignores offset, or a malformed mapping
                // must never keep the detail screen spinning forever.
                if newItems == 0 { break }

                if let totalPath = pagination.totalPath,
                   let total = JSONPath.int(totalPath, in: root),
                   seenIDs.count >= total {
                    break
                }

                if pageItems.count < pagination.limit { break }

                pageCount += 1
                let nextOffset = requestedOffset + pagination.limit
                guard nextOffset > requestedOffset else { break }
                offset = nextOffset
            }
        } else {
            let root = try load(operation.request, variables: variables, arrayVariables: ["languages": preferred])
            allItems = JSONPath.value(operation.itemsPath, in: root) as? [Any] ?? []
        }
        var chapters = allItems.compactMap { item -> Chapter? in
            guard let id = JSONPath.string(operation.idPath, in: item) else { return nil }
            if let languagePath = operation.languagePath, !preferred.isEmpty, let lang = JSONPath.string(languagePath, in: item), !preferred.contains(lang) { return nil }
            let number = JSONPath.string(operation.numberPath, in: item).flatMap(Double.init) ?? 0
            let title = operation.titlePath.flatMap { JSONPath.string($0, in: item) }
            return Chapter(id: id, mangaID: manga.id, number: number, title: title, pages: [], isDownloaded: false)
        }
        if operation.sort == "numberAscending" { chapters.sort { $0.number < $1.number } }
        return chapters
    }

    func pages(for chapter: Chapter, manga: Manga) throws -> [Page] {
        guard let operation = config.api?.pages else { throw DeclarativeSourceError.missingRoute("api.pages") }
        let root = try load(operation.request, variables: ["chapterID": chapter.id, "mangaID": manga.id])
        guard let base = JSONPath.string(operation.baseURLPath, in: root), let hash = JSONPath.string(operation.hashPath, in: root) else { throw DeclarativeSourceError.invalidResponse }
        let items = JSONPath.value(operation.itemsPath, in: root) as? [Any] ?? []
        let urls = items.compactMap { ($0 as? String).flatMap { URL(string: expand(operation.urlTemplate, variables: ["baseURL": base, "hash": hash, "item": $0])) } }
        guard !urls.isEmpty else { throw DeclarativeSourceError.noResults("pages") }
        return urls.enumerated().map { Page(id: "\(chapter.id)-\($0.offset)", index: $0.offset, imageURL: $0.element, localFileURL: nil) }
    }

    private func load(
        _ request: DeclarativeAPIRequest,
        variables: [String: String],
        arrayVariables: [String: [String]] = [:],
        extraQueryItems: [URLQueryItem] = []
    ) throws -> Any {
        let path = expand(request.path, variables: variables)
        guard let base = URL(string: path, relativeTo: config.baseURL)?.absoluteURL, var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw DeclarativeSourceError.invalidURL(path) }
        var queryItems = components.queryItems ?? []
        queryItems.append(contentsOf: extraQueryItems)
        for (key, value) in request.query ?? [:] {
            switch value {
            case .string(let raw):
                if raw == "{{languages}}", let values = arrayVariables["languages"] { queryItems += values.map { URLQueryItem(name: key, value: $0) } }
                else { queryItems.append(URLQueryItem(name: key, value: expand(raw, variables: variables))) }
            case .strings(let values): queryItems += values.map { URLQueryItem(name: key, value: expand($0, variables: variables)) }
            case .int(let value): queryItems.append(URLQueryItem(name: key, value: String(value)))
            case .bool(let value): queryItems.append(URLQueryItem(name: key, value: value ? "true" : "false"))
            }
        }
        components.queryItems = queryItems
        guard let url = components.url, isAllowed(url) else { throw DeclarativeSourceError.invalidURL(components.url?.absoluteString ?? path) }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method ?? "GET"
        for (key, value) in config.network?.headers ?? [:] { urlRequest.setValue(value, forHTTPHeaderField: key) }
        return try JSONSerialization.jsonObject(with: dataLoader(urlRequest))
    }

    private func isAllowed(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return config.allowedDomains.contains { host == $0.lowercased() || host.hasSuffix("." + $0.lowercased()) }
    }

    private func expand(_ template: String, variables: [String: String]) -> String {
        variables.reduce(template) { result, pair in result.replacingOccurrences(of: "{{\(pair.key)}}", with: pair.value).replacingOccurrences(of: "{\(pair.key)}", with: pair.value) }
    }
}

private enum JSONPath {
    static func value(_ path: String, in root: Any) -> Any? {
        values(path, in: root).first
    }

    static func values(_ path: String, in root: Any) -> [Any] {
        let components = pathComponents(path)
        guard !components.isEmpty else { return [root] }
        return descend(root, components: ArraySlice(components))
    }

    static func strings(_ path: String, in root: Any) -> [String] {
        values(path, in: root).compactMap { value in
            if let value = value as? String { return value }
            if let value = value as? NSNumber { return value.stringValue }
            return nil
        }
    }

    static func string(_ path: String, in root: Any) -> String? {
        strings(path, in: root).first
    }

    static func int(_ path: String, in root: Any) -> Int? {
        if let value = value(path, in: root) as? Int { return value }
        if let value = value(path, in: root) as? NSNumber { return value.intValue }
        if let value = string(path, in: root) { return Int(value) }
        return nil
    }

    private static func pathComponents(_ path: String) -> [String] {
        path
            .replacingOccurrences(of: "$.", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "$"))
            .split(separator: ".")
            .map(String.init)
    }

    private static func descend(
        _ current: Any,
        components: ArraySlice<String>
    ) -> [Any] {
        guard let component = components.first else { return [current] }
        let remaining = components.dropFirst()

        if component == "*" {
            if let dictionary = current as? [String: Any] {
                return dictionary.values.flatMap {
                    descend($0, components: remaining)
                }
            }
            if let array = current as? [Any] {
                return array.flatMap {
                    descend($0, components: remaining)
                }
            }
            return []
        }

        if let dictionary = current as? [String: Any],
           let next = dictionary[component] {
            return descend(next, components: remaining)
        }

        if let array = current as? [Any],
           let index = Int(component),
           array.indices.contains(index) {
            return descend(array[index], components: remaining)
        }

        return []
    }
}
