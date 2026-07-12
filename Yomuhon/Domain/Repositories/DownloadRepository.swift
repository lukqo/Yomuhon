//
//  DownloadRepository.swift
//  Yomuhon
//

protocol DownloadRepository {
    func downloadChapter(_ chapter: Chapter, from manga: Manga, progressHandler: ((Double) -> Void)?, shouldCancel: (() -> Bool)?) throws -> Chapter
    func deleteDownloadedChapter(_ chapter: Chapter, from manga: Manga) throws -> Manga
    func deleteDownloadedManga(_ manga: Manga) throws -> Manga
}
