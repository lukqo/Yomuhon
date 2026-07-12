//
//  PresentationCompositionRoot.swift
//  Yomuhon
//

import Foundation

struct PresentationCompositionRoot {
    static let live = PresentationCompositionRoot()

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
        SearchViewModel(
            searchMangaUseCase: makeSearchMangaUseCase(),
            getLibraryUseCase: makeGetLibraryUseCase(),
            sourceSettingsStore: sourceSettingsStore
        )
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
