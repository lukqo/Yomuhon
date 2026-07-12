//
//  SourceRepository.swift
//  Yomuhon
//

struct SourceSearchProgress {
    let sourceID: String
    let mangas: [Manga]
    let completedSourceCount: Int
    let totalSourceCount: Int
}

struct SourceDiscoveryGenre: Identifiable, Hashable {
    let id: String
    let title: String
}

struct SourceDiscoveryProgress {
    let sourceID: String
    let mangas: [Manga]
    let completedSourceCount: Int
    let totalSourceCount: Int
}

protocol SourceRepository {
    func availableSources() -> [Source]
    func availableDiscoveryGenres() -> [SourceDiscoveryGenre]
    func popularManga() throws -> [Manga]
    func manga(forGenreID genreID: String) throws -> [Manga]
    func searchManga(query: String) throws -> [Manga]
    func fetchDetails(for manga: Manga) throws -> Manga
    func fetchChapters(for manga: Manga) throws -> [Chapter]
    func fetchPages(for chapter: Chapter, manga: Manga) throws -> [Page]
}

extension SourceRepository {
    func availableDiscoveryGenres() -> [SourceDiscoveryGenre] { [] }
    func manga(forGenreID genreID: String) throws -> [Manga] { [] }
}

protocol ProgressiveSourceRepository: SourceRepository {
    func searchManga(
        query: String,
        cancellationToken: RequestCancellationToken,
        progress: @escaping (SourceSearchProgress) -> Void
    ) throws -> [Manga]
}

protocol ProgressiveDiscoveryRepository: SourceRepository {
    func popularManga(
        progress: @escaping (SourceDiscoveryProgress) -> Void
    ) throws -> [Manga]

    func manga(
        forGenreID genreID: String,
        progress: @escaping (SourceDiscoveryProgress) -> Void
    ) throws -> [Manga]
}
