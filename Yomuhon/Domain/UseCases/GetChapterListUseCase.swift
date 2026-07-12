//
//  GetChapterListUseCase.swift
//  Yomuhon
//

struct GetChapterListUseCase {
    private let repository: SourceRepository

    init(repository: SourceRepository) {
        self.repository = repository
    }

    func execute(manga: Manga) throws -> Manga {
        try repository.fetchDetails(for: manga)
    }
}
