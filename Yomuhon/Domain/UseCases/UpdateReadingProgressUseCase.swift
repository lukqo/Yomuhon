//
//  UpdateReadingProgressUseCase.swift
//  Yomuhon
//

import Foundation

struct UpdateReadingProgressUseCase {
    private let repository: LibraryRepository

    init(repository: LibraryRepository) {
        self.repository = repository
    }

    func execute(manga: Manga, chapter: Chapter, pageIndex: Int) {
        // Reading is an explicit library action in Yomuhon. Keep manual shelf
        // membership in sync with the reading-progress store so Detail and the
        // Library sidebar immediately agree after the reader opens.
        LibraryMembershipStore.shared.add(manga.id)

        var updatedManga = manga

        if let chapterIndex = updatedManga.chapters.firstIndex(where: { $0.id == chapter.id }) {
            updatedManga.chapters[chapterIndex] = chapter
        } else {
            updatedManga.chapters.append(chapter)
        }

        repository.saveManga(updatedManga)

        let progress = ReadingProgress(
            id: "progress-\(manga.id)",
            mangaID: manga.id,
            sourceID: manga.sourceID,
            currentChapterID: chapter.id,
            currentPage: pageIndex,
            lastReadAt: Date(),
            status: .reading
        )

        repository.saveReadingProgress(progress)
        NotificationCenter.default.post(
            name: .yomuhonLibraryDidChange,
            object: nil,
            userInfo: ["mangaID": manga.id]
        )
    }

    func addToLibrary(manga: Manga) {
        LibraryMembershipStore.shared.add(manga.id)
        repository.saveManga(manga)

        let progress = ReadingProgress(
            id: "progress-\(manga.id)",
            mangaID: manga.id,
            sourceID: manga.sourceID,
            currentChapterID: manga.chapters.first?.id ?? "",
            currentPage: 0,
            lastReadAt: Date(),
            status: .planToRead
        )

        repository.saveReadingProgress(progress)
        NotificationCenter.default.post(
            name: .yomuhonLibraryDidChange,
            object: nil,
            userInfo: ["mangaID": manga.id]
        )
    }
}


extension Notification.Name {
    static let yomuhonLibraryDidChange = Notification.Name("yomuhon.library.didChange")
}

// MARK: - Library Membership

final class LibraryMembershipStore {
    static let shared = LibraryMembershipStore()

    private let key = "yomuhon.library.manualShelfMangaIDs.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var ids: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    func contains(_ mangaID: String) -> Bool {
        ids.contains(mangaID)
    }

    func add(_ mangaID: String) {
        var values = ids
        let inserted = values.insert(mangaID).inserted
        guard inserted else { return }

        defaults.set(Array(values).sorted(), forKey: key)
        NotificationCenter.default.post(
            name: .yomuhonLibraryDidChange,
            object: nil,
            userInfo: ["mangaID": mangaID]
        )
    }

    func remove(_ mangaID: String) {
        var values = ids
        guard values.remove(mangaID) != nil else { return }

        defaults.set(Array(values).sorted(), forKey: key)
        NotificationCenter.default.post(
            name: .yomuhonLibraryDidChange,
            object: nil,
            userInfo: ["mangaID": mangaID]
        )
    }
}
