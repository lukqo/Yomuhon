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

    func popularManga() throws -> [Manga]
    func manga(forGenreID genreID: String) throws -> [Manga]
    func searchManga(query: String) throws -> [Manga]
    func fetchDetails(for manga: Manga) throws -> Manga
    func fetchChapters(for manga: Manga) throws -> [Chapter]
    func fetchPages(for chapter: Chapter, manga: Manga) throws -> [Page]
}

extension Source {
    var supportsPopularDiscovery: Bool { false }
    var supportsGenreDiscovery: Bool { false }
    var discoveryGenres: [SourceDiscoveryGenre] { [] }

    func popularManga() throws -> [Manga] {
        []
    }

    func manga(forGenreID genreID: String) throws -> [Manga] {
        []
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
