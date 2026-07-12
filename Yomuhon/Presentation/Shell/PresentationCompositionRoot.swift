//
//  PresentationCompositionRoot.swift
//  Yomuhon
//

import Foundation

struct PresentationCompositionRoot {
    static let live = PresentationCompositionRoot()

    static var application: PresentationCompositionRoot {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            return uiTesting
        }
        #endif
        return live
    }

    #if DEBUG
    private static let uiTesting: PresentationCompositionRoot = {
        let libraryRepository = YomuhonUITestLibraryRepository()
        return PresentationCompositionRoot(
            libraryRepository: libraryRepository,
            sourceRepository: YomuhonUITestSourceRepository(),
            downloadRepository: YomuhonUITestDownloadRepository(),
            sourceSettingsStore: YomuhonUITestSourceSettingsStore()
        )
    }()
    #endif

    private let libraryRepository: LibraryRepository
    private let sourceRepository: SourceRepository
    private let downloadRepository: DownloadRepository
    private let sourceSettingsStore: SourceSettingsStoring

    init(
        libraryRepository: LibraryRepository = LibraryRepositoryImpl(),
        sourceRepository: SourceRepository = SourceRepositoryImpl(),
        downloadRepository: DownloadRepository = DownloadRepositoryImpl(),
        sourceSettingsStore: SourceSettingsStoring = SourceSettingsStore.shared
    ) {
        self.libraryRepository = libraryRepository
        self.sourceRepository = sourceRepository
        self.downloadRepository = downloadRepository
        self.sourceSettingsStore = sourceSettingsStore

        DownloadCenter.shared.configure(
            downloadUseCase: DownloadChapterUseCase(
                downloadRepository: downloadRepository,
                libraryRepository: libraryRepository,
                sourceRepository: sourceRepository
            )
        )
    }

    func makeLibraryViewModel() -> LibraryViewModel {
        LibraryViewModel(getLibraryUseCase: makeGetLibraryUseCase())
    }

    func makeSearchViewModel() -> SearchViewModel {
        SearchViewModel(searchMangaUseCase: makeSearchMangaUseCase())
    }

    func makeSourcesViewModel() -> SourcesViewModel {
        SourcesViewModel(store: sourceSettingsStore)
    }

    func makeMangaDetailViewModel(
        manga: Manga,
        alternativeMangas: [Manga] = [],
        progress: ReadingProgress?
    ) -> MangaDetailViewModel {
        MangaDetailViewModel(
            manga: manga,
            alternativeMangas: alternativeMangas,
            progress: progress,
            getChapterListUseCase: makeGetChapterListUseCase(),
            downloadChapterUseCase: makeDownloadChapterUseCase(),
            updateReadingProgressUseCase: makeUpdateReadingProgressUseCase(),
            sourceRepository: sourceRepository,
            libraryRepository: libraryRepository
        )
    }

    func makeGetLibraryUseCase() -> GetLibraryUseCase {
        GetLibraryUseCase(repository: libraryRepository)
    }

    func makeSearchMangaUseCase() -> SearchMangaUseCase {
        SearchMangaUseCase(repository: sourceRepository)
    }

    func makeGetChapterListUseCase() -> GetChapterListUseCase {
        GetChapterListUseCase(repository: sourceRepository)
    }

    func makeDownloadChapterUseCase() -> DownloadChapterUseCase {
        DownloadChapterUseCase(
            downloadRepository: downloadRepository,
            libraryRepository: libraryRepository,
            sourceRepository: sourceRepository
        )
    }

    func makeUpdateReadingProgressUseCase() -> UpdateReadingProgressUseCase {
        UpdateReadingProgressUseCase(repository: libraryRepository)
    }
}


#if DEBUG
private enum YomuhonUITestFixtures {
    static let sourceID = "ui_test"

    static let pages: [Page] = (0..<3).map { index in
        Page(
            id: "ui-test-page-\(index)",
            index: index,
            imageURL: nil,
            localFileURL: nil
        )
    }

    static let chapters: [Chapter] = [
        Chapter(
            id: "ui-test-chapter-1",
            mangaID: "ui-test-manga",
            number: 1,
            title: "Chapter 1",
            pages: [],
            isDownloaded: false
        ),
        Chapter(
            id: "ui-test-chapter-2",
            mangaID: "ui-test-manga",
            number: 2,
            title: "Chapter 2",
            pages: [],
            isDownloaded: false
        )
    ]

    static var manga: Manga {
        Manga(
            id: "ui-test-manga",
            sourceID: sourceID,
            title: "Yomuhon Fixture Manga",
            coverURL: nil,
            synopsis: "Deterministic manga used by Yomuhon UI tests.",
            alternativeTitles: ["Fixture Manga"],
            author: "Yomuhon Tests",
            releaseYear: 2026,
            chapters: chapters
        )
    }
}

private struct YomuhonUITestSource: Source {
    let id = YomuhonUITestFixtures.sourceID
    let name = "UI Test Source"
    var supportsPopularDiscovery: Bool { true }
    var supportsGenreDiscovery: Bool { true }
    var discoveryGenres: [SourceDiscoveryGenre] {
        [SourceDiscoveryGenre(id: "fixture", title: "Fixture")]
    }

    func popularManga() throws -> [Manga] { [YomuhonUITestFixtures.manga] }
    func manga(forGenreID genreID: String) throws -> [Manga] { [YomuhonUITestFixtures.manga] }
    func searchManga(query: String) throws -> [Manga] {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? []
            : [YomuhonUITestFixtures.manga]
    }
    func fetchDetails(for manga: Manga) throws -> Manga { YomuhonUITestFixtures.manga }
    func fetchChapters(for manga: Manga) throws -> [Chapter] { YomuhonUITestFixtures.chapters }
    func fetchPages(for chapter: Chapter, manga: Manga) throws -> [Page] { YomuhonUITestFixtures.pages }
}

private struct YomuhonUITestSourceRepository: SourceRepository {
    private let source = YomuhonUITestSource()

    func availableSources() -> [Source] { [source] }
    func availableDiscoveryGenres() -> [SourceDiscoveryGenre] { source.discoveryGenres }
    func popularManga() throws -> [Manga] { try source.popularManga() }
    func manga(forGenreID genreID: String) throws -> [Manga] { try source.manga(forGenreID: genreID) }
    func searchManga(query: String) throws -> [Manga] { try source.searchManga(query: query) }
    func fetchDetails(for manga: Manga) throws -> Manga { try source.fetchDetails(for: manga) }
    func fetchChapters(for manga: Manga) throws -> [Chapter] { try source.fetchChapters(for: manga) }
    func fetchPages(for chapter: Chapter, manga: Manga) throws -> [Page] {
        try source.fetchPages(for: chapter, manga: manga)
    }
}

final class YomuhonUITestLibraryRepository: LibraryRepository {
    private let lock = NSLock()
    private var mangas: [String: Manga] = [:]
    private var progress: [String: ReadingProgress] = [:]

    func fetchLibrary() -> [Manga] {
        lock.lock()
        defer { lock.unlock() }
        return Array(mangas.values)
    }

    func fetchReadingProgress() -> [ReadingProgress] {
        lock.lock()
        defer { lock.unlock() }
        return Array(progress.values)
    }

    func saveManga(_ manga: Manga) {
        lock.lock()
        mangas[manga.id] = manga
        lock.unlock()
    }

    func saveReadingProgress(_ readingProgress: ReadingProgress) {
        lock.lock()
        progress[readingProgress.mangaID] = readingProgress
        lock.unlock()
    }

    func deleteManga(id: String) {
        lock.lock()
        mangas.removeValue(forKey: id)
        lock.unlock()
    }

    func deleteReadingProgress(mangaID: String) {
        lock.lock()
        progress.removeValue(forKey: mangaID)
        lock.unlock()
    }
}

private struct YomuhonUITestDownloadRepository: DownloadRepository {
    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    func downloadChapter(
        _ chapter: Chapter,
        from manga: Manga,
        progressHandler: ((Double) -> Void)?,
        shouldCancel: (() -> Bool)?
    ) throws -> Chapter {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YomuhonUITests", isDirectory: true)
            .appendingPathComponent(chapter.id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var downloaded = chapter
        let sourcePages = chapter.pages.isEmpty ? YomuhonUITestFixtures.pages : chapter.pages
        downloaded.pages = try sourcePages.enumerated().map { offset, page in
            if shouldCancel?() == true {
                throw DownloadRepositoryError.cancelled
            }

            let fileURL = directory.appendingPathComponent("page-\(offset).png")
            try Self.onePixelPNG.write(to: fileURL, options: .atomic)
            progressHandler?(Double(offset + 1) / Double(max(sourcePages.count, 1)))
            return Page(id: page.id, index: page.index, imageURL: page.imageURL, localFileURL: fileURL)
        }
        downloaded.isDownloaded = true
        return downloaded
    }

    func deleteDownloadedChapter(_ chapter: Chapter, from manga: Manga) throws -> Manga {
        var updated = manga
        if let index = updated.chapters.firstIndex(where: { $0.id == chapter.id }) {
            updated.chapters[index].isDownloaded = false
            updated.chapters[index].pages = updated.chapters[index].pages.map {
                Page(id: $0.id, index: $0.index, imageURL: $0.imageURL, localFileURL: nil)
            }
        }
        return updated
    }

    func deleteDownloadedManga(_ manga: Manga) throws -> Manga {
        var updated = manga
        for index in updated.chapters.indices {
            updated.chapters[index].isDownloaded = false
            updated.chapters[index].pages = updated.chapters[index].pages.map {
                Page(id: $0.id, index: $0.index, imageURL: $0.imageURL, localFileURL: nil)
            }
        }
        return updated
    }
}

final class YomuhonUITestSourceSettingsStore: SourceSettingsStoring {
    private let lock = NSLock()
    private var repositories: [SourceRepositoryConfiguration] = [
        SourceRepositoryConfiguration(
            id: YomuhonUITestFixtures.sourceID,
            name: "UI Test Source",
            isEnabled: true,
            isBundled: true,
            installedSources: [
                InstalledSourceConfiguration(
                    id: YomuhonUITestFixtures.sourceID,
                    name: "UI Test Source",
                    language: "en",
                    healthStatus: .available,
                    mangas: [],
                    isInstalled: true
                )
            ],
            statusMessage: nil
        )
    ]

    func loadRepositories() -> [SourceRepositoryConfiguration] {
        lock.lock()
        defer { lock.unlock() }
        return repositories
    }

    func saveRepositories(_ repositories: [SourceRepositoryConfiguration]) {
        lock.lock()
        self.repositories = repositories
        lock.unlock()
    }
}
#endif
