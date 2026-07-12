//
//  GetLibraryUseCase.swift
//  Yomuhon
//

struct GetLibraryUseCase {
    private let repository: LibraryRepository

    init(repository: LibraryRepository) {
        self.repository = repository
    }

    func execute() -> LibrarySnapshot {
        LibrarySnapshot(
            mangas: repository.fetchLibrary(),
            progress: repository.fetchReadingProgress()
        )
    }
    func saveManga(_ manga: Manga) {
        repository.saveManga(manga)
    }

    func deleteManga(_ manga: Manga) {
        repository.deleteManga(id: manga.id)
    }
}

struct LibrarySnapshot {
    let mangas: [Manga]
    let progress: [ReadingProgress]
}
