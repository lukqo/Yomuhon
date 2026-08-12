//
//  SourceCatalogUseCase.swift
//  Yomuhon
//
//  Backs the per-source catalog screen: unlike SearchMangaUseCase (which
//  fans a query out across every enabled source), everything here is scoped
//  to a single sourceID so the user can see exactly what one source offers.
//

struct SourceCatalogInfo {
    let sourceID: String
    let name: String
    let supportsPopular: Bool
    let supportsGenres: Bool
    let genres: [SourceDiscoveryGenre]
    let supportsTypes: Bool
    let types: [SourceDiscoveryType]
}

struct SourceCatalogUseCase {
    private let repository: SourceRepository

    init(repository: SourceRepository) {
        self.repository = repository
    }

    func info(forSourceID sourceID: String, fallbackName: String) -> SourceCatalogInfo? {
        guard let source = repository.source(forID: sourceID) else { return nil }

        return SourceCatalogInfo(
            sourceID: source.id,
            name: fallbackName.isEmpty ? source.name : fallbackName,
            supportsPopular: source.supportsPopularDiscovery,
            supportsGenres: source.supportsGenreDiscovery,
            genres: source.discoveryGenres,
            supportsTypes: source.supportsTypeDiscovery,
            types: source.discoveryTypes
        )
    }

    func popularManga(sourceID: String) throws -> [Manga] {
        guard let source = repository.source(forID: sourceID) else { return [] }
        return try source.popularManga()
    }

    /// One page of the popular shelf (1-based). Empty means no more pages.
    func popularManga(sourceID: String, page: Int) throws -> [Manga] {
        guard let source = repository.source(forID: sourceID) else { return [] }
        return try source.popularManga(page: page)
    }

    func manga(sourceID: String, genreID: String) throws -> [Manga] {
        guard let source = repository.source(forID: sourceID) else { return [] }
        return try source.manga(forGenreID: genreID)
    }

    func manga(sourceID: String, typeID: String) throws -> [Manga] {
        guard let source = repository.source(forID: sourceID) else { return [] }
        return try source.manga(forTypeID: typeID)
    }

    func search(sourceID: String, query: String) throws -> [Manga] {
        guard let source = repository.source(forID: sourceID) else { return [] }
        return try source.searchManga(query: query)
    }
}
