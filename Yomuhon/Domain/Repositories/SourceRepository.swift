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

/// Mirrors `SourceDiscoveryGenre`. Deliberately no cross-source aggregate
/// (no `availableDiscoveryTypes()` on `SourceRepository`) — a source's types
/// are only meaningful scoped to that source's own catalog, same as the
/// per-source-only intent behind genres (see the note on SearchView's
/// `availableDiscoveryGenres` fusion, which should not be replicated here).
struct SourceDiscoveryType: Identifiable, Hashable {
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
    func source(forID sourceID: String) -> Source?
    func availableDiscoveryGenres() -> [SourceDiscoveryGenre]
    func popularManga() throws -> [Manga]
    func manga(forGenreID genreID: String) throws -> [Manga]
    func searchManga(query: String) throws -> [Manga]
    func fetchDetails(for manga: Manga) throws -> Manga
    func fetchChapters(for manga: Manga) throws -> [Chapter]
    func fetchPages(for chapter: Chapter, manga: Manga) throws -> [Page]
}

extension SourceRepository {
    // Single-source lookup, used by SourceCatalogUseCase to browse or search
    // within exactly one source instead of aggregating across all of them.
    func source(forID sourceID: String) -> Source? {
        availableSources().first { $0.id == sourceID }
    }

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
        cancellationToken: RequestCancellationToken,
        progress: @escaping (SourceDiscoveryProgress) -> Void
    ) throws -> [Manga]

    func manga(
        forGenreID genreID: String,
        cancellationToken: RequestCancellationToken,
        progress: @escaping (SourceDiscoveryProgress) -> Void
    ) throws -> [Manga]
}
