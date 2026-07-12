//
//  SearchMangaUseCase.swift
//  Yomuhon
//

struct SearchMangaUseCase {
    private let repository: SourceRepository

    init(repository: SourceRepository) {
        self.repository = repository
    }

    func execute(query: String) throws -> [Manga] {
        try repository.searchManga(query: query)
    }

    func execute(
        query: String,
        cancellationToken: RequestCancellationToken,
        progress: @escaping (SourceSearchProgress) -> Void
    ) throws -> [Manga] {
        guard let progressiveRepository = repository as? ProgressiveSourceRepository else {
            let mangas = try repository.searchManga(query: query)
            progress(
                SourceSearchProgress(
                    sourceID: "all",
                    mangas: mangas,
                    completedSourceCount: 1,
                    totalSourceCount: 1
                )
            )
            return mangas
        }

        return try progressiveRepository.searchManga(
            query: query,
            cancellationToken: cancellationToken,
            progress: progress
        )
    }

    func discoveryGenres() -> [SourceDiscoveryGenre] {
        repository.availableDiscoveryGenres()
    }

    func popularManga() throws -> [Manga] {
        try repository.popularManga()
    }

    func popularManga(
        progress: @escaping (SourceDiscoveryProgress) -> Void
    ) throws -> [Manga] {
        guard let progressiveRepository = repository as? ProgressiveDiscoveryRepository else {
            let mangas = try repository.popularManga()
            progress(
                SourceDiscoveryProgress(
                    sourceID: "all",
                    mangas: mangas,
                    completedSourceCount: 1,
                    totalSourceCount: 1
                )
            )
            return mangas
        }

        return try progressiveRepository.popularManga(progress: progress)
    }

    func manga(
        forGenreID genreID: String,
        progress: @escaping (SourceDiscoveryProgress) -> Void
    ) throws -> [Manga] {
        guard let progressiveRepository = repository as? ProgressiveDiscoveryRepository else {
            let mangas = try repository.manga(forGenreID: genreID)
            progress(
                SourceDiscoveryProgress(
                    sourceID: "all",
                    mangas: mangas,
                    completedSourceCount: 1,
                    totalSourceCount: 1
                )
            )
            return mangas
        }

        return try progressiveRepository.manga(
            forGenreID: genreID,
            progress: progress
        )
    }
}
