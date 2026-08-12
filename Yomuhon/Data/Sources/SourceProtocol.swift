//
//  SourceProtocol.swift
//  Yomuhon
//

import Foundation

/// Boundary between Yomuhon's domain layer and a source runtime.
///
/// Provider definitions are discovered from Yomuhon-Sources. The app ships
/// generic runtimes only; presentation code never parses provider HTML or JSON.
protocol Source {
    var id: String { get }
    var name: String { get }
    var supportsPopularDiscovery: Bool { get }
    var supportsGenreDiscovery: Bool { get }
    var discoveryGenres: [SourceDiscoveryGenre] { get }
    var supportsTypeDiscovery: Bool { get }
    var discoveryTypes: [SourceDiscoveryType] { get }

    func popularManga() throws -> [Manga]
    func manga(forGenreID genreID: String) throws -> [Manga]
    func manga(forTypeID typeID: String) throws -> [Manga]
    func searchManga(query: String) throws -> [Manga]

    /// Single-page variants for lazily-loaded (scroll-triggered) browsing.
    /// `page` is 1-based. An empty result means "no more pages" — either
    /// because the source has none left, or because it declares fewer pages
    /// than were requested. Defaulted below so existing conformers that only
    /// implement the bulk variants keep working unchanged (they simply have
    /// no "page 2" to offer).
    func popularManga(page: Int) throws -> [Manga]
    func manga(forGenreID genreID: String, page: Int) throws -> [Manga]
    func manga(forTypeID typeID: String, page: Int) throws -> [Manga]
    func fetchDetails(for manga: Manga) throws -> Manga
    func fetchChapters(for manga: Manga) throws -> [Chapter]
    func fetchPages(for chapter: Chapter, manga: Manga) throws -> [Page]
}

extension Source {
    var supportsPopularDiscovery: Bool { false }
    var supportsGenreDiscovery: Bool { false }
    var discoveryGenres: [SourceDiscoveryGenre] { [] }
    var supportsTypeDiscovery: Bool { false }
    var discoveryTypes: [SourceDiscoveryType] { [] }

    func popularManga() throws -> [Manga] {
        []
    }

    func manga(forGenreID genreID: String) throws -> [Manga] {
        []
    }

    func manga(forTypeID typeID: String) throws -> [Manga] {
        []
    }

    func popularManga(page: Int) throws -> [Manga] {
        page == 1 ? try popularManga() : []
    }

    func manga(forGenreID genreID: String, page: Int) throws -> [Manga] {
        page == 1 ? try manga(forGenreID: genreID) : []
    }

    func manga(forTypeID typeID: String, page: Int) throws -> [Manga] {
        page == 1 ? try manga(forTypeID: typeID) : []
    }

    func fetchDetails(for manga: Manga) throws -> Manga {
        var detailedManga = manga
        detailedManga.chapters = try fetchChapters(for: manga)
        return detailedManga
    }

    func fetchPages(for chapter: Chapter, manga: Manga) throws -> [Page] {
        chapter.pages
    }
}
