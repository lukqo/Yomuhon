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

    func hasAvailableSources() -> Bool {
        !repository.availableSources().isEmpty
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
        cancellationToken: RequestCancellationToken,
        progress: @escaping (SourceDiscoveryProgress) -> Void
    ) throws -> [Manga] {
        guard !cancellationToken.isCancelled else {
            throw HTTPClientError.cancelled
        }

        guard let progressiveRepository = repository as? ProgressiveDiscoveryRepository else {
            let mangas = try repository.popularManga()
            guard !cancellationToken.isCancelled else {
                throw HTTPClientError.cancelled
            }
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

        return try progressiveRepository.popularManga(
            cancellationToken: cancellationToken,
            progress: progress
        )
    }

    func manga(
        forGenreID genreID: String,
        cancellationToken: RequestCancellationToken,
        progress: @escaping (SourceDiscoveryProgress) -> Void
    ) throws -> [Manga] {
        guard !cancellationToken.isCancelled else {
            throw HTTPClientError.cancelled
        }

        guard let progressiveRepository = repository as? ProgressiveDiscoveryRepository else {
            let mangas = try repository.manga(forGenreID: genreID)
            guard !cancellationToken.isCancelled else {
                throw HTTPClientError.cancelled
            }
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
            cancellationToken: cancellationToken,
            progress: progress
        )
    }
}
