//
//  DownloadChapterUseCase.swift
//  Yomuhon
//

struct DownloadChapterUseCase {
    private let downloadRepository: DownloadRepository
    private let libraryRepository: LibraryRepository
    private let sourceRepository: SourceRepository

    init(
        downloadRepository: DownloadRepository,
        libraryRepository: LibraryRepository,
        sourceRepository: SourceRepository
    ) {
        self.downloadRepository = downloadRepository
        self.libraryRepository = libraryRepository
        self.sourceRepository = sourceRepository
    }

    func execute(
        chapter: Chapter,
        manga: Manga,
        progressHandler: ((Double) -> Void)? = nil,
        shouldCancel: (() -> Bool)? = nil
    ) throws -> Manga {
        let hydratedChapter = try chapterWithPages(chapter, manga: manga)
        let downloadedChapter = try downloadRepository.downloadChapter(
            hydratedChapter,
            from: manga,
            progressHandler: progressHandler,
            shouldCancel: shouldCancel
        )

        var updatedManga = manga

        if let index = updatedManga.chapters.firstIndex(where: { $0.id == chapter.id }) {
            updatedManga.chapters[index] = downloadedChapter
        }

        libraryRepository.saveManga(updatedManga)
        return updatedManga
    }

    func deleteDownloadedChapter(_ chapter: Chapter, manga: Manga) throws -> Manga {
        let updatedManga = try downloadRepository.deleteDownloadedChapter(chapter, from: manga)
        libraryRepository.saveManga(updatedManga)
        return updatedManga
    }

    func deleteDownloadedManga(_ manga: Manga) throws -> Manga {
        let updatedManga = try downloadRepository.deleteDownloadedManga(manga)
        libraryRepository.saveManga(updatedManga)
        return updatedManga
    }

    private func chapterWithPages(_ chapter: Chapter, manga: Manga) throws -> Chapter {
        guard chapter.pages.isEmpty else {
            return chapter
        }

        var hydratedChapter = chapter
        hydratedChapter.pages = try sourceRepository.fetchPages(for: chapter, manga: manga)
        return hydratedChapter
    }
}
