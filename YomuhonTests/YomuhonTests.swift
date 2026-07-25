//
//  YomuhonTests.swift
//  YomuhonTests
//
//  Created by Lucas Salas on 29-06-26.
//

import XCTest
@testable import Yomuhon


private enum TestSourceFixtures {
    static let mangaPillJSON = #"""
        {
          "schemaVersion": 1,
          "id": "mangapill_json",
          "name": "MangaPill JSON",
          "version": 3,
          "language": "en",
          "baseURL": "https://mangapill.com",
          "engineMode": "html",
          "enabledByDefault": false,
          "experimental": true,
          "allowedDomains": [
            "mangapill.com",
            "cdn.mangapill.com",
            "cdn.readdetectiveconan.com"
          ],
          "supports": {
            "search": true,
            "popular": false,
            "details": true,
            "chapters": true,
            "pages": true
          },
          "network": {
            "headers": {
              "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
              "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 12_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Yomuhon/1.0",
              "Referer": "https://mangapill.com/"
            }
          },
          "routes": {
            "search": {
              "path": "/search",
              "query": {
                "q": "{{query}}"
              }
            }
          },
          "selectors": {
            "search": {
              "container": "a[href*='/manga/']",
              "title": {
                "attrs": [
                  "title",
                  "text"
                ],
                "cleanup": [
                  "decodeEntities",
                  "normalizeWhitespace"
                ]
              },
              "url": {
                "attrs": [
                  "href"
                ],
                "required": true
              },
              "cover": {
                "selectors": [
                  "img"
                ],
                "attrs": [
                  "data-src",
                  "data-original",
                  "data-lazy-src",
                  "src"
                ]
              }
            },
            "details": {
              "title": {
                "selectors": [
                  "h1",
                  "meta[property='og:title']"
                ],
                "attrs": [
                  "text",
                  "content"
                ],
                "cleanup": [
                  "decodeEntities",
                  "normalizeWhitespace"
                ]
              },
              "synopsis": {
                "selectors": [
                  "meta[name='description']",
                  "meta[property='og:description']"
                ],
                "attrs": [
                  "content"
                ],
                "cleanup": [
                  "stripHTML",
                  "decodeEntities",
                  "normalizeWhitespace"
                ]
              },
              "cover": {
                "selectors": [
                  "meta[property='og:image']",
                  "img"
                ],
                "attrs": [
                  "content",
                  "data-src",
                  "data-original",
                  "data-lazy-src",
                  "src"
                ]
              }
            },
            "chapters": {
              "container": "a[href*='/chapters/']",
              "title": {
                "attrs": [
                  "text",
                  "title"
                ],
                "cleanup": [
                  "decodeEntities",
                  "normalizeWhitespace"
                ]
              },
              "url": {
                "attrs": [
                  "href"
                ],
                "required": true
              },
              "number": {
                "from": "url",
                "regex": "chapter-([0-9]+(?:\\.[0-9]+)?)"
              },
              "sort": "numberAscending"
            },
            "pages": {
              "extractors": [
                {
                  "type": "css",
                  "selector": "img[alt*='Page'], img[src*='cdn.mangapill.com'], img[src*='cdn.readdetectiveconan.com'], img[data-src*='cdn.readdetectiveconan.com']",
                  "attrs": [
                    "data-src",
                    "data-original",
                    "data-lazy-src",
                    "srcset",
                    "src"
                  ]
                },
                {
                  "type": "regex",
                  "pattern": "(https?:\\\\?/\\\\?/[^\"']+?\\.(?:jpg|jpeg|png|webp)(?:\\?[^\"']*)?)"
                }
              ],
              "filters": {
                "mustContain": [
                  ".jpg",
                  ".jpeg",
                  ".png",
                  ".webp"
                ],
                "blockContains": [
                  "logo",
                  "avatar",
                  "placeholder",
                  "banner",
                  "ads/",
                  "icon",
                  "favicon",
                  "sprite",
                  "doubleclick",
                  "analytics"
                ]
              }
            }
          },
          "cleanup": {
            "decodeHTMLEntities": true,
            "normalizeWhitespace": true,
            "removeText": [
              "Read Manga Online",
              "Advertisement"
            ]
          },
          "tests": {
            "query": "hime no dameshi",
            "minSearchResults": 1,
            "minChapters": 1,
            "minPages": 1
          }
        }
        """#

}

private struct PreviewLibraryRepository: LibraryRepository {
    func fetchLibrary() -> [Manga] {
        [
            Manga(
                id: "blue-period",
                sourceID: "local.preview",
                title: "Blue Period",
                coverURL: nil,
                synopsis: "Preview",
                chapters: makeChapters(mangaID: "blue-period", count: 8, downloadedThrough: 3)
            ),
            Manga(
                id: "witch-hat",
                sourceID: "source.preview",
                title: "Witch Hat Atelier",
                coverURL: nil,
                synopsis: "Preview",
                chapters: makeChapters(mangaID: "witch-hat", count: 12, downloadedThrough: 5)
            ),
            Manga(
                id: "frieren",
                sourceID: "source.preview",
                title: "Frieren",
                coverURL: nil,
                synopsis: "Preview",
                chapters: makeChapters(mangaID: "frieren", count: 10, downloadedThrough: 2)
            ),
            Manga(
                id: "yotsuba",
                sourceID: "local.preview",
                title: "Yotsuba&!",
                coverURL: nil,
                synopsis: "Preview",
                chapters: makeChapters(mangaID: "yotsuba", count: 6, downloadedThrough: 0)
            )
        ]
    }

    func fetchReadingProgress() -> [ReadingProgress] {
        [
            ReadingProgress(
                id: "progress-blue-period",
                mangaID: "blue-period",
                sourceID: "local.preview",
                currentChapterID: "blue-period-3",
                currentPage: 18,
                lastReadAt: Date(),
                status: .reading
            ),
            ReadingProgress(
                id: "progress-witch-hat",
                mangaID: "witch-hat",
                sourceID: "source.preview",
                currentChapterID: "witch-hat-1",
                currentPage: 6,
                lastReadAt: Date().addingTimeInterval(-86_400),
                status: .reading
            ),
            ReadingProgress(
                id: "progress-frieren",
                mangaID: "frieren",
                sourceID: "source.preview",
                currentChapterID: "frieren-10",
                currentPage: 24,
                lastReadAt: Date().addingTimeInterval(-172_800),
                status: .completed
            ),
            ReadingProgress(
                id: "progress-yotsuba",
                mangaID: "yotsuba",
                sourceID: "local.preview",
                currentChapterID: "yotsuba-1",
                currentPage: 0,
                lastReadAt: Date().addingTimeInterval(-259_200),
                status: .planToRead
            )
        ]
    }

    func saveManga(_ manga: Manga) {}
    func saveReadingProgress(_ progress: ReadingProgress) {}
    func deleteManga(id: String) {}
    func deleteReadingProgress(mangaID: String) {}

    private func makeChapters(mangaID: String, count: Int, downloadedThrough: Int) -> [Chapter] {
        (1...count).map { index in
            Chapter(
                id: "\(mangaID)-\(index)",
                mangaID: mangaID,
                number: Double(index),
                title: "Chapter \(index)",
                pages: (0..<(22 + (index % 7))).map { pageIndex in
                    Page(
                        id: "\(mangaID)-\(index)-page-\(pageIndex)",
                        index: pageIndex,
                        imageURL: nil,
                        localFileURL: nil
                    )
                },
                isDownloaded: index <= downloadedThrough
            )
        }
    }
}

final class YomuhonTests: XCTestCase {

    func testShellLayoutKeepsIPhoneCompactAtWideViewport() {
        XCTAssertEqual(
            YomuhonShellLayoutResolver.resolve(
                viewportWidth: 932,
                isPad: false,
                currentLayout: .regular
            ),
            .compact
        )
    }

    func testShellLayoutUsesCompactIPadLayoutBelowExitBreakpoint() {
        XCTAssertEqual(
            YomuhonShellLayoutResolver.resolve(
                viewportWidth: 834,
                isPad: true,
                currentLayout: .regular
            ),
            .compact
        )
    }

    func testShellLayoutHysteresisKeepsCompactLayoutInsideStableBand() {
        XCTAssertEqual(
            YomuhonShellLayoutResolver.resolve(
                viewportWidth: 900,
                isPad: true,
                currentLayout: .compact
            ),
            .compact
        )
    }

    func testShellLayoutHysteresisKeepsRegularLayoutInsideStableBand() {
        XCTAssertEqual(
            YomuhonShellLayoutResolver.resolve(
                viewportWidth: 900,
                isPad: true,
                currentLayout: .regular
            ),
            .regular
        )
    }

    func testShellLayoutEntersRegularAtUpperBreakpoint() {
        XCTAssertEqual(
            YomuhonShellLayoutResolver.resolve(
                viewportWidth: YomuhonLayout.regularShellEnterBreakpoint,
                isPad: true,
                currentLayout: .compact
            ),
            .regular
        )
    }

    func testShellLayoutExitsRegularBelowLowerBreakpoint() {
        XCTAssertEqual(
            YomuhonShellLayoutResolver.resolve(
                viewportWidth: YomuhonLayout.regularShellExitBreakpoint - 1,
                isPad: true,
                currentLayout: .regular
            ),
            .compact
        )
    }

    func testShellLayoutUsesRegularIPadLayoutAtWideViewport() {
        XCTAssertEqual(
            YomuhonShellLayoutResolver.resolve(
                viewportWidth: 1194,
                isPad: true,
                currentLayout: .compact
            ),
            .regular
        )
    }

    func testNavigationKeepsTheSameDetailViewModelAcrossShellChanges() {
        let sourceRepository = TestSourceRepository()
        let libraryRepository = PreviewLibraryRepository()
        let manga = Manga(
            id: "navigation-detail",
            sourceID: "source.preview",
            title: "Navigation Detail",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )
        let detailViewModel = MangaDetailViewModel(
            manga: manga,
            progress: nil,
            getChapterListUseCase: GetChapterListUseCase(repository: sourceRepository),
            downloadChapterUseCase: DownloadChapterUseCase(
                downloadRepository: TestDownloadRepository(),
                libraryRepository: libraryRepository,
                sourceRepository: sourceRepository
            ),
            updateReadingProgressUseCase: UpdateReadingProgressUseCase(repository: libraryRepository),
            sourceRepository: sourceRepository,
            libraryRepository: libraryRepository
        )
        let navigation = AppNavigationModel(selectedSection: .search, shellLayout: .compact)

        navigation.openMangaDetail(detailViewModel)
        navigation.updateShellLayout(viewportWidth: 1194, isPad: true)
        navigation.updateShellLayout(viewportWidth: 834, isPad: true)

        guard case .mangaDetail(let retainedViewModel)? = navigation.currentRoute else {
            return XCTFail("Expected manga detail route")
        }

        XCTAssertTrue(retainedViewModel === detailViewModel)
        XCTAssertEqual(navigation.selectedSection, .search)
        XCTAssertEqual(navigation.shellLayout, .compact)
    }

    func testReaderSessionSurvivesShellChangesWithTheSamePage() throws {
        let sourceRepository = TestSourceRepository()
        let pages = (0..<8).map { index in
            Page(
                id: "navigation-reader-page-\(index)",
                index: index,
                imageURL: nil,
                localFileURL: nil
            )
        }
        let chapter = Chapter(
            id: "navigation-reader-chapter",
            mangaID: "navigation-reader",
            number: 1,
            title: "Chapter 1",
            pages: pages,
            isDownloaded: true
        )
        let manga = Manga(
            id: "navigation-reader",
            sourceID: "source.preview",
            title: "Navigation Reader",
            coverURL: nil,
            synopsis: nil,
            chapters: [chapter]
        )
        let readerViewModel = ReaderViewModel(
            manga: manga,
            chapter: chapter,
            initialPageIndex: 5,
            sourceRepository: sourceRepository
        )
        let navigation = AppNavigationModel(shellLayout: .compact)

        navigation.openReader(readerViewModel, from: nil)
        let sessionID = try XCTUnwrap(navigation.activeReaderSession?.id)

        navigation.updateShellLayout(viewportWidth: 1194, isPad: true)
        navigation.updateShellLayout(viewportWidth: 834, isPad: true)

        let retainedSession = try XCTUnwrap(navigation.activeReaderSession)
        XCTAssertEqual(retainedSession.id, sessionID)
        XCTAssertTrue(retainedSession.viewModel === readerViewModel)
        XCTAssertEqual(retainedSession.viewModel.currentPageIndex, 5)
    }

    func testPreviewLibraryContainsInitialManga() throws {
        let repository = PreviewLibraryRepository()

        let mangas = repository.fetchLibrary()

        XCTAssertEqual(mangas.count, 4)
        XCTAssertTrue(mangas.contains { $0.title == "Blue Period" })
        XCTAssertTrue(mangas.allSatisfy { !$0.sourceID.isEmpty })
    }

    func testLibraryViewModelFiltersBySource() throws {
        let viewModel = LibraryViewModel(
            getLibraryUseCase: GetLibraryUseCase(repository: PreviewLibraryRepository())
        )

        viewModel.searchText = "local.preview"

        XCTAssertEqual(viewModel.filteredMangas.map(\.title), ["Blue Period", "Yotsuba&!"])
    }

    func testLibraryViewModelFiltersByReadingStatus() throws {
        let viewModel = LibraryViewModel(
            getLibraryUseCase: GetLibraryUseCase(repository: PreviewLibraryRepository())
        )

        viewModel.selectedCategory = .completed

        XCTAssertEqual(viewModel.filteredMangas.map(\.title), ["Frieren"])
    }

    func testLibraryViewModelCountsDownloadedChapters() throws {
        let viewModel = LibraryViewModel(
            getLibraryUseCase: GetLibraryUseCase(repository: PreviewLibraryRepository())
        )

        XCTAssertEqual(viewModel.downloadedChapterCount, 10)
    }

    func testMangaDetailViewModelBuildsReaderViewModel() throws {
        let repository = PreviewLibraryRepository()
        let sourceRepository = TestSourceRepository()
        let manga = try XCTUnwrap(repository.fetchLibrary().first)
        let chapter = try XCTUnwrap(manga.chapters.first)
        let progress = repository.fetchReadingProgress().first { $0.mangaID == manga.id }
        let viewModel = MangaDetailViewModel(
            manga: manga,
            progress: progress,
            getChapterListUseCase: GetChapterListUseCase(repository: sourceRepository),
            downloadChapterUseCase: DownloadChapterUseCase(
                downloadRepository: TestDownloadRepository(),
                libraryRepository: repository,
                sourceRepository: sourceRepository
            ),
            updateReadingProgressUseCase: UpdateReadingProgressUseCase(repository: repository),
            sourceRepository: sourceRepository,
            libraryRepository: repository
        )

        let readerViewModel = viewModel.readerViewModel(for: chapter)

        XCTAssertEqual(readerViewModel.title, manga.title)
        XCTAssertEqual(readerViewModel.chapterTitle, chapter.displayTitle)
    }

    func testMangaDetailPrefersReadableSourceWithKnownChaptersOverEmptyPrimarySource() throws {
        let sourceRepository = TestSourceRepository()
        let libraryRepository = PreviewLibraryRepository()
        let emptyPrimary = Manga(
            id: "mangapill-empty",
            sourceID: "mangapill",
            title: "Recommended Source Test",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )
        let mangaDexAlternative = Manga(
            id: "mangadex-readable",
            sourceID: "mangadex",
            title: "Recommended Source Test",
            coverURL: nil,
            synopsis: nil,
            chapters: [
                Chapter(
                    id: "mangadex-chapter-1",
                    mangaID: "mangadex-readable",
                    number: 1,
                    title: nil,
                    pages: [],
                    isDownloaded: false
                )
            ]
        )

        let viewModel = MangaDetailViewModel(
            manga: emptyPrimary,
            alternativeMangas: [mangaDexAlternative],
            progress: nil,
            getChapterListUseCase: GetChapterListUseCase(repository: sourceRepository),
            downloadChapterUseCase: DownloadChapterUseCase(
                downloadRepository: TestDownloadRepository(),
                libraryRepository: libraryRepository,
                sourceRepository: sourceRepository
            ),
            updateReadingProgressUseCase: UpdateReadingProgressUseCase(repository: libraryRepository),
            sourceRepository: sourceRepository,
            libraryRepository: libraryRepository
        )

        XCTAssertEqual(viewModel.recommendedSourceID, "mangadex")
        XCTAssertEqual(viewModel.selectedSourceID, "mangadex")
        XCTAssertEqual(viewModel.manga.sourceID, "mangadex")
        XCTAssertEqual(viewModel.chapters.count, 1)
    }

    func testMangaDetailPrefersMangaDexWhenAllGroupedSourcesStillHaveUnknownChapterCounts() throws {
        let sourceRepository = TestSourceRepository()
        let libraryRepository = PreviewLibraryRepository()
        let mangaKatanaPrimary = Manga(
            id: "mangakatana-empty",
            sourceID: "mangakatana",
            title: "Trust Rank Test",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )
        let mangaDexAlternative = Manga(
            id: "mangadex-empty",
            sourceID: "mangadex",
            title: "Trust Rank Test",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )

        let viewModel = MangaDetailViewModel(
            manga: mangaKatanaPrimary,
            alternativeMangas: [mangaDexAlternative],
            progress: nil,
            getChapterListUseCase: GetChapterListUseCase(repository: sourceRepository),
            downloadChapterUseCase: DownloadChapterUseCase(
                downloadRepository: TestDownloadRepository(),
                libraryRepository: libraryRepository,
                sourceRepository: sourceRepository
            ),
            updateReadingProgressUseCase: UpdateReadingProgressUseCase(repository: libraryRepository),
            sourceRepository: sourceRepository,
            libraryRepository: libraryRepository
        )

        XCTAssertNil(viewModel.recommendedSourceID)
        XCTAssertEqual(viewModel.selectedSourceID, "mangadex")
        XCTAssertEqual(viewModel.manga.sourceID, "mangadex")
    }

    func testCrossSourceTitleKeyIgnoresTrailingScraperNumericIdentifier() throws {
        let mangaKatanaTitle = Manga(
            id: "mangakatana-title",
            sourceID: "mangakatana",
            title: "After Coincidentally Saving The New Transfer Students Little Sister We Gradually Grew Closer.27493",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )
        let mangaDexTitle = Manga(
            id: "mangadex-title",
            sourceID: "mangadex",
            title: "After Coincidentally Saving The New Transfer Students Little Sister We Gradually Grew Closer",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )

        XCTAssertEqual(mangaKatanaTitle.crossSourceTitleKey, mangaDexTitle.crossSourceTitleKey)
    }

    func testMangaDetailKeepsProgressSourceAheadOfAutomaticRecommendation() throws {
        let sourceRepository = TestSourceRepository()
        let libraryRepository = PreviewLibraryRepository()
        let progressSource = Manga(
            id: "mangapill-progress",
            sourceID: "mangapill",
            title: "Progress Source Test",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )
        let mangaDexAlternative = Manga(
            id: "mangadex-recommended",
            sourceID: "mangadex",
            title: "Progress Source Test",
            coverURL: nil,
            synopsis: nil,
            chapters: [
                Chapter(
                    id: "mangadex-progress-chapter-1",
                    mangaID: "mangadex-recommended",
                    number: 1,
                    title: nil,
                    pages: [],
                    isDownloaded: false
                )
            ]
        )
        let progress = ReadingProgress(
            id: "progress-source-test",
            mangaID: progressSource.id,
            sourceID: progressSource.sourceID,
            currentChapterID: "mangapill-chapter-10",
            currentPage: 4,
            lastReadAt: Date(),
            status: .reading
        )

        let viewModel = MangaDetailViewModel(
            manga: progressSource,
            alternativeMangas: [mangaDexAlternative],
            progress: progress,
            getChapterListUseCase: GetChapterListUseCase(repository: sourceRepository),
            downloadChapterUseCase: DownloadChapterUseCase(
                downloadRepository: TestDownloadRepository(),
                libraryRepository: libraryRepository,
                sourceRepository: sourceRepository
            ),
            updateReadingProgressUseCase: UpdateReadingProgressUseCase(repository: libraryRepository),
            sourceRepository: sourceRepository,
            libraryRepository: libraryRepository
        )

        XCTAssertEqual(viewModel.recommendedSourceID, "mangadex")
        XCTAssertEqual(viewModel.selectedSourceID, "mangapill")
        XCTAssertEqual(viewModel.manga.sourceID, "mangapill")
    }

    func testReaderViewModelMovesBetweenPages() throws {
        let manga = try XCTUnwrap(PreviewLibraryRepository().fetchLibrary().first)
        let chapter = try XCTUnwrap(manga.chapters.first)
        let viewModel = ReaderViewModel(
            manga: manga,
            chapter: chapter,
            sourceRepository: TestSourceRepository()
        )

        viewModel.goForward()
        viewModel.goForward()
        viewModel.goBackward()

        XCTAssertEqual(viewModel.currentPageIndex, 1)
        XCTAssertTrue(viewModel.canGoForward)
        XCTAssertTrue(viewModel.canGoBackward)
    }

    func testPublishedSourcesDoNotRequireDiagnosticVerification() throws {
        let store = makeSourceStore(operationalSourceIDs: ["mangadex"])
        let repository = SourceRepositoryImpl(
            sources: [ProbeSource(id: "mangadex"), ProbeSource(id: "mangapill")],
            settingsStore: store
        )

        XCTAssertEqual(Set(repository.availableSources().map(\.id)), Set(["mangadex", "mangapill"]))
    }

    func testOperationalSourceRecoveryPersistsAcrossReloads() throws {
        let suiteName = "YomuhonTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = SourceSettingsStore(userDefaults: defaults)
        var repositories = store.loadRepositories()

        let index = try XCTUnwrap(repositories.firstIndex { $0.id == "mangapill_json" })
        repositories[index].isEnabled = true
        repositories[index].installedSources = repositories[index].installedSources.map { source in
            var source = source
            source.healthStatus = .available
            return source
        }
        store.saveRepositories(repositories)

        let reloaded = try XCTUnwrap(store.loadRepositories().first { $0.id == "mangapill_json" })
        XCTAssertTrue(NativeSourceCatalog.isOperational(reloaded))
    }

    func testPersistedDiagnosticHealthDoesNotGatePublishedSources() throws {
        let store = makeSourceStore(operationalSourceIDs: ["mangadex", "mangapill"])
        var repositories = store.loadRepositories()
        if let index = repositories.firstIndex(where: { $0.id == "mangapill" }) {
            repositories[index].isEnabled = false
            repositories[index].installedSources = repositories[index].installedSources.map { source in
                var source = source
                source.healthStatus = .unavailable
                return source
            }
            store.saveRepositories(repositories)
        }

        let repository = SourceRepositoryImpl(
            sources: [ProbeSource(id: "mangadex"), ProbeSource(id: "mangapill")],
            settingsStore: store
        )

        XCTAssertEqual(Set(repository.availableSources().map(\.id)), Set(["mangadex", "mangapill"]))
    }

    func testSearchRunsPublishedSourcesInParallelAndPublishesProgress() throws {
        SourceSearchCache.shared.removeAll()
        let gate = ParallelSearchGate(expectedCount: 2)
        let store = makeSourceStore(operationalSourceIDs: ["mangadex", "mangapill"])
        let repository = SourceRepositoryImpl(
            sources: [
                ProbeSource(id: "mangadex", gate: gate),
                ProbeSource(id: "mangapill", gate: gate)
            ],
            settingsStore: store
        )
        let token = RequestCancellationToken()
        let query = "parallel-\(UUID().uuidString)"
        var progressSourceIDs = Set<String>()
        let lock = NSLock()

        let results = try repository.searchManga(
            query: query,
            cancellationToken: token
        ) { progress in
            lock.lock()
            progressSourceIDs.insert(progress.sourceID)
            lock.unlock()
        }

        XCTAssertEqual(Set(results.map(\.sourceID)), Set(["mangadex", "mangapill"]))
        XCTAssertEqual(progressSourceIDs, Set(["mangadex", "mangapill"]))
        XCTAssertTrue(gate.didReleaseAllSources)
    }

    func testSearchCancellationStopsCooperativeSourceWork() throws {
        SourceSearchCache.shared.removeAll()
        let store = makeSourceStore(operationalSourceIDs: ["mangadex"])
        let repository = SourceRepositoryImpl(
            sources: [CancellableProbeSource()],
            settingsStore: store
        )
        let token = RequestCancellationToken()
        let finished = expectation(description: "cancelled search finishes")
        let startedAt = Date()
        var receivedCancellation = false

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try repository.searchManga(
                    query: "cancel-\(UUID().uuidString)",
                    cancellationToken: token
                ) { _ in }
            } catch let error as HTTPClientError {
                receivedCancellation = error.isCancellation
            } catch {
                receivedCancellation = false
            }
            finished.fulfill()
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.12) {
            token.cancel()
        }

        wait(for: [finished], timeout: 1.5)
        XCTAssertTrue(receivedCancellation)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1.5)
    }

    func testSearchCacheAvoidsRepeatingTheSameSourceRequest() throws {
        SourceSearchCache.shared.removeAll()
        let counter = CallCounter()
        let store = makeSourceStore(operationalSourceIDs: ["mangadex"])
        let repository = SourceRepositoryImpl(
            sources: [ProbeSource(id: "mangadex", counter: counter)],
            settingsStore: store
        )
        let query = "cache-\(UUID().uuidString)"

        _ = try repository.searchManga(query: query)
        _ = try repository.searchManga(query: query)

        XCTAssertEqual(counter.value, 1)
    }

    func testSearchCacheReplaysPerSourceProgressForRanking() throws {
        SourceSearchCache.shared.removeAll()
        let store = makeSourceStore(operationalSourceIDs: ["mangadex", "mangapill"])
        let repository = SourceRepositoryImpl(
            sources: [
                ProbeSource(id: "mangadex"),
                ProbeSource(id: "mangapill")
            ],
            settingsStore: store
        )
        let query = "cache-ranking-\(UUID().uuidString)"

        _ = try repository.searchManga(query: query)
        var progressSourceIDs: [String] = []
        _ = try repository.searchManga(
            query: query,
            cancellationToken: RequestCancellationToken()
        ) { progress in
            progressSourceIDs.append(progress.sourceID)
        }

        XCTAssertEqual(Set(progressSourceIDs), Set(["mangadex", "mangapill"]))
        XCTAssertFalse(progressSourceIDs.contains("cache"))
    }

    func testSourceContentCacheAvoidsDuplicateDetailAndPageRequests() throws {
        SourceContentCache.shared.removeAll()
        let counter = ContentCacheCounter()
        let source = ContentCacheProbeSource(counter: counter)
        let suiteName = "YomuhonTests.ContentCache.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let repository = SourceRepositoryImpl(
            sources: [source],
            settingsStore: SourceSettingsStore(userDefaults: defaults)
        )
        let manga = Manga(
            id: "content-cache-\(UUID().uuidString)",
            sourceID: source.id,
            title: "Content Cache Probe",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )

        let firstDetail = try repository.fetchDetails(for: manga)
        let secondDetail = try repository.fetchDetails(for: manga)
        XCTAssertEqual(firstDetail.chapters.count, 1)
        XCTAssertEqual(secondDetail.chapters.count, 1)
        XCTAssertEqual(counter.detailCount, 1)

        let chapter = try XCTUnwrap(firstDetail.chapters.first)
        let firstPages = try repository.fetchPages(for: chapter, manga: firstDetail)
        let secondPages = try repository.fetchPages(for: chapter, manga: firstDetail)
        XCTAssertEqual(firstPages.count, 2)
        XCTAssertEqual(secondPages.count, 2)
        XCTAssertEqual(counter.pageCount, 1)
    }

    func testDetailFailureTriesEachFallbackOnlyOnceAndStopsLoading() throws {
        let sourceRepository = FailingDetailSourceRepository()
        let libraryRepository = PreviewLibraryRepository()
        let primary = Manga(
            id: "primary",
            sourceID: "mangadex",
            title: "Fallback Test",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )
        let alternative = Manga(
            id: "alternative",
            sourceID: "mangapill",
            title: "Fallback Test",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )
        let viewModel = MangaDetailViewModel(
            manga: primary,
            alternativeMangas: [alternative],
            progress: nil,
            getChapterListUseCase: GetChapterListUseCase(repository: sourceRepository),
            downloadChapterUseCase: DownloadChapterUseCase(
                downloadRepository: TestDownloadRepository(),
                libraryRepository: libraryRepository,
                sourceRepository: sourceRepository
            ),
            updateReadingProgressUseCase: UpdateReadingProgressUseCase(repository: libraryRepository),
            sourceRepository: sourceRepository,
            libraryRepository: libraryRepository
        )
        let finished = expectation(description: "fallback chain finishes")

        viewModel.loadDetailsIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            XCTAssertFalse(viewModel.isLoadingDetails)
            XCTAssertNotNil(viewModel.errorMessage)
            XCTAssertEqual(sourceRepository.fetchCount(for: "mangadex"), 1)
            XCTAssertEqual(sourceRepository.fetchCount(for: "mangapill"), 1)
            finished.fulfill()
        }

        wait(for: [finished], timeout: 1.5)
    }



    func testSearchCacheDropsSourcesThatAreNoLongerAvailable() throws {
        SourceSearchCache.shared.removeAll()
        let store = makeSourceStore(operationalSourceIDs: ["mangadex", "mangapill"])
        let repository = SourceRepositoryImpl(
            sources: [ProbeSource(id: "mangadex"), ProbeSource(id: "mangapill")],
            settingsStore: store
        )
        let query = "health-cache-\(UUID().uuidString)"

        let initial = try repository.searchManga(query: query)
        XCTAssertEqual(Set(initial.map(\.sourceID)), Set(["mangadex", "mangapill"]))

        var repositories = store.loadRepositories()
        let mangaPillIndex = try XCTUnwrap(repositories.firstIndex { $0.id == "mangapill" })
        repositories[mangaPillIndex].isEnabled = false
        repositories[mangaPillIndex].installedSources = repositories[mangaPillIndex].installedSources.map { source in
            var source = source
            source.healthStatus = .unavailable
            return source
        }
        store.saveRepositories(repositories)

        let filtered = try repository.searchManga(query: query)
        XCTAssertEqual(filtered.map(\.sourceID), ["mangadex"])
    }

    func testDeclarativeDetailParsesMetadataAndChaptersFromOneDocumentRequest() throws {
        let config = try JSONDecoder().decode(
            DeclarativeSourceConfig.self,
            from: Data(TestSourceFixtures.mangaPillJSON.utf8)
        )
        let counter = CallCounter()
        let html = #"""
        <html>
          <head>
            <meta name="description" content="A useful synopsis.">
          </head>
          <body>
            <h1>Single Fetch Manga</h1>
            <a href="/chapters/8347-10002000/single-fetch-manga-chapter-2">Chapter 2</a>
            <a href="/chapters/8347-10001000/single-fetch-manga-chapter-1">Chapter 1</a>
          </body>
        </html>
        """#
        let source = DeclarativeHTMLSource(config: config) { _ in
            counter.increment()
            return Data(html.utf8)
        }
        let manga = Manga(
            id: "mangapill-json-single-fetch",
            sourceID: "mangapill_json",
            title: "Single Fetch Manga",
            coverURL: nil,
            synopsis: "yomuhon-declarative-source-url:https://mangapill.com/manga/8347/single-fetch-manga",
            chapters: []
        )

        let detailed = try source.fetchDetails(for: manga)

        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(detailed.title, "Single Fetch Manga")
        XCTAssertEqual(detailed.chapters.map(\.number), [1, 2])
    }

    func testAppShipsNoBundledProviderDefinitions() throws {
        // Production provider definitions are obtained from the remote repository
        // or its last successfully downloaded cache, never from the app bundle.
        XCTAssertTrue(SourceRepositoryImpl.defaultSources.isEmpty)
    }

    func testDetailInitialLoadIsIdempotentAcrossRepeatedAppearances() throws {
        let sourceRepository = DelayedDetailSourceRepository(delay: 0.12)
        let libraryRepository = PreviewLibraryRepository()
        let manga = Manga(
            id: "repeat-appear",
            sourceID: "mangapill",
            title: "Repeated Appearance",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )
        let viewModel = MangaDetailViewModel(
            manga: manga,
            progress: nil,
            getChapterListUseCase: GetChapterListUseCase(repository: sourceRepository),
            downloadChapterUseCase: DownloadChapterUseCase(
                downloadRepository: TestDownloadRepository(),
                libraryRepository: libraryRepository,
                sourceRepository: sourceRepository
            ),
            updateReadingProgressUseCase: UpdateReadingProgressUseCase(repository: libraryRepository),
            sourceRepository: sourceRepository,
            libraryRepository: libraryRepository,
            detailLoadTimeout: 0.5,
            detailSessionTimeout: 0.7
        )
        let finished = expectation(description: "detail finishes once")

        viewModel.loadDetailsIfNeeded()
        viewModel.loadDetailsIfNeeded()
        viewModel.loadDetailsIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            XCTAssertEqual(sourceRepository.fetchCount, 1)
            XCTAssertEqual(viewModel.chapters.count, 1)
            XCTAssertFalse(viewModel.isLoadingDetails)
            XCTAssertNil(viewModel.errorMessage)
            finished.fulfill()
        }

        wait(for: [finished], timeout: 1.0)
    }

    func testDetailWatchdogAlwaysLeavesLoadingState() throws {
        let sourceRepository = DelayedDetailSourceRepository(delay: 1.5)
        let libraryRepository = PreviewLibraryRepository()
        let manga = Manga(
            id: "watchdog",
            sourceID: "mangapill",
            title: "Watchdog",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )
        let viewModel = MangaDetailViewModel(
            manga: manga,
            progress: nil,
            getChapterListUseCase: GetChapterListUseCase(repository: sourceRepository),
            downloadChapterUseCase: DownloadChapterUseCase(
                downloadRepository: TestDownloadRepository(),
                libraryRepository: libraryRepository,
                sourceRepository: sourceRepository
            ),
            updateReadingProgressUseCase: UpdateReadingProgressUseCase(repository: libraryRepository),
            sourceRepository: sourceRepository,
            libraryRepository: libraryRepository,
            detailLoadTimeout: 0.12,
            detailSessionTimeout: 0.2
        )
        let finished = expectation(description: "watchdog exits loading")

        viewModel.loadDetailsIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            XCTAssertFalse(viewModel.isLoadingDetails)
            XCTAssertNotNil(viewModel.errorMessage)
            finished.fulfill()
        }

        wait(for: [finished], timeout: 1.0)
    }

    func testReadableDetailsReturnBeforeOptionalMetadataEnrichment() throws {
        let slowMetadataSource = SlowMetadataProbeSource(delay: 1.0)
        let repository = SourceRepositoryImpl(
            sources: [ReadableDetailProbeSource()],
            settingsStore: makeSourceStore(operationalSourceIDs: []),
            metadataEnrichmentService: MangaMetadataEnrichmentService(
                providers: [slowMetadataSource]
            )
        )
        let manga = Manga(
            id: "detail-fast",
            sourceID: "detail_probe",
            title: "Fast Chapters",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )
        let startedAt = Date()

        let detailed = try repository.fetchDetails(for: manga)

        XCTAssertEqual(detailed.chapters.count, 1)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.5)
        XCTAssertEqual(slowMetadataSource.searchCount, 0)
    }

    func testSimpleHTMLSelectorEngineSupportsRepositorySubset() throws {
        let html = #"""
        <html>
          <head>
            <meta property="og:title" content="Selector Fixture">
          </head>
          <body>
            <section id="chapters">
              <div class="title card"><a href="/manga/1/demo">Demo Manga</a></div>
              <a class="chapter" href="/chapters/1/demo-chapter-1">Chapter 1</a>
              <a href="/chapters/1/demo-chapter-2">Chapter 2</a>
            </section>
            <img alt="Page 1" src="https://cdn.mangapill.com/demo/1.jpg">
            <img src="https://cdn.mangapill.com/demo/2.webp">
          </body>
        </html>
        """#
        let document = SimpleHTMLDocument(html: html)

        XCTAssertEqual(document.select("a[href*='/chapters/']").count, 2)
        XCTAssertEqual(document.select("#chapters a[href*='/chapters/']").count, 2)
        XCTAssertEqual(document.first(".title a")?.text, "Demo Manga")
        XCTAssertEqual(document.first("meta[property='og:title']")?.attr("content"), "Selector Fixture")
        XCTAssertEqual(
            document.select("img[alt*='Page'], img[src*='cdn.mangapill.com']").count,
            2
        )

        let tableHTML = #"""
        <table>
          <tr><td class="chapter"><a href="/manga/demo.1/c1">Chapter 1</a></td></tr>
          <tr><td><a href="/manga/related.2/c7">Related chapter</a></td></tr>
          <tr><td class="chapter"><a href="/manga/demo.1/c2">Chapter 2</a></td></tr>
        </table>
        """#
        let tableDocument = SimpleHTMLDocument(html: tableHTML)
        XCTAssertTrue(SimpleHTMLDocument.supports("tr:has(.chapter)"))
        XCTAssertEqual(tableDocument.select("tr:has(.chapter)").count, 2)
    }

    func testDeclarativeChapterNumberRuleRejectsCandidatesThatDoNotMatchDeclaredRegex() throws {
        let configJSON = #"""
        {
          "schemaVersion": 1,
          "id": "chapter_rule_fixture",
          "name": "Chapter Rule Fixture",
          "version": 1,
          "language": "en",
          "baseURL": "https://example.com",
          "engineMode": "html",
          "enabledByDefault": false,
          "experimental": true,
          "allowedDomains": ["example.com"],
          "supports": {
            "search": false,
            "popular": false,
            "details": true,
            "chapters": true,
            "pages": false
          },
          "selectors": {
            "details": {
              "title": {"selectors": ["h1"], "attrs": ["text"]}
            },
            "chapters": {
              "container": "a[href*='/manga/']",
              "title": {"attrs": ["text"]},
              "url": {"attrs": ["href"], "required": true},
              "number": {"from": "url", "regex": "/manga/demo\.1/c([0-9]+(?:\\.[0-9]+)?)"},
              "sort": "numberAscending"
            }
          }
        }
        """#
        let config = try JSONDecoder().decode(
            DeclarativeSourceConfig.self,
            from: Data(configJSON.utf8)
        )
        let source = DeclarativeSourceRuntime(config: config) { _ in
            Data(#"""
            <h1>Demo</h1>
            <a href="/manga/related.2/c7">Chapter 7 from another manga</a>
            <a href="/manga/demo.1/c1">Chapter 1</a>
            <a href="/manga/demo.1/c2">Chapter 2</a>
            """#.utf8)
        }
        let manga = Manga(
            id: "chapter-rule-demo",
            sourceID: "chapter_rule_fixture",
            title: "Demo",
            coverURL: nil,
            synopsis: "yomuhon-declarative-source-url:https://example.com/manga/demo.1",
            chapters: []
        )

        let detailed = try source.fetchDetails(for: manga)

        XCTAssertEqual(detailed.chapters.map(\.number), [1, 2])
        XCTAssertEqual(detailed.chapters.count, 2)
    }

    func testDeclarativeMangaPillRuntimeParsesThirtyChaptersAndPagesFromRepositorySelectors() throws {
        let config = try JSONDecoder().decode(
            DeclarativeSourceConfig.self,
            from: Data(TestSourceFixtures.mangaPillJSON.utf8)
        )
        let counter = CallCounter()
        let source = DeclarativeSourceRuntime(config: config) { request in
            counter.increment()
            let path = try XCTUnwrap(request.url?.path)

            if path == "/search" {
                XCTAssertEqual(
                    URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                        .queryItems?
                        .first(where: { $0.name == "q" })?
                        .value,
                    "hime no dameshi"
                )
                return Data(#"""
                <main>
                  <a href="/manga/1714/hime-no-dameshi" title="Hime no Dameshi">
                    <img src="https://cdn.mangapill.com/manga/1714/cover.jpg">
                    Hime no Dameshi
                  </a>
                </main>
                """#.utf8)
            }

            if path == "/manga/1714/hime-no-dameshi" {
                let links = (1...30).reversed().map { chapter in
                    "<a href=\"/chapters/1714-100\(String(format: "%02d", chapter))000/hime-no-dameshi-chapter-\(chapter)\">Chapter \(chapter)</a>"
                }.joined(separator: "\n")

                return Data("""
                <html>
                  <head>
                    <meta name="description" content="A manga used by the declarative runtime regression test.">
                    <meta property="og:image" content="https://cdn.mangapill.com/manga/1714/cover.jpg">
                  </head>
                  <body>
                    <h1>Hime no Dameshi</h1>
                    <div id="chapters">\(links)</div>
                  </body>
                </html>
                """.utf8)
            }

            if path.contains("/chapters/") {
                return Data(#"""
                <div class="reader">
                  <picture><img alt="Page 1" src="https://cdn.mangapill.com/1714/chapter/1.jpg"></picture>
                  <picture><img alt="Page 2" data-src="https://cdn.mangapill.com/1714/chapter/2.webp"></picture>
                  <img src="https://mangapill.com/logo.png">
                </div>
                """#.utf8)
            }

            XCTFail("Unexpected runtime request: \(request.url?.absoluteString ?? "nil")")
            return Data()
        }

        let search = try source.searchManga(query: "hime no dameshi")
        let manga = try XCTUnwrap(search.first)
        let detailed = try source.fetchDetails(for: manga)
        let firstChapter = try XCTUnwrap(detailed.chapters.first)
        let pages = try source.fetchPages(for: firstChapter, manga: detailed)

        XCTAssertEqual(search.count, 1)
        XCTAssertEqual(manga.title, "Hime no Dameshi")
        XCTAssertEqual(detailed.chapters.count, 30)
        XCTAssertEqual(detailed.chapters.first?.number, 1)
        XCTAssertEqual(detailed.chapters.last?.number, 30)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages.first?.imageURL?.host, "cdn.mangapill.com")
        XCTAssertEqual(counter.value, 3)
    }

    func testDeclarativeRuntimeAllowsUnexpectedPublicImageHost() throws {
        var configObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(TestSourceFixtures.mangaPillJSON.utf8)
            ) as? [String: Any]
        )
        configObject["allowedDomains"] = ["mangapill.com", "cdn.mangapill.com"]
        let config = try JSONDecoder().decode(
            DeclarativeSourceConfig.self,
            from: JSONSerialization.data(withJSONObject: configObject)
        )
        let source = DeclarativeSourceRuntime(config: config) { request in
            let path = try XCTUnwrap(request.url?.path)

            if path == "/manga/1714/hime-no-dameshi" {
                return Data(#"""
                <h1>Hime no Dameshi</h1>
                <a href="/chapters/1714-10001000/hime-no-dameshi-chapter-1">Chapter 1</a>
                """#.utf8)
            }

            return Data(#"""
            <img alt="Page 1" src="https://cdn.readdetectiveconan.com/file/mangap/1714/10001000/1.jpg">
            """#.utf8)
        }
        let manga = Manga(
            id: "mangapill-json-domain-guard",
            sourceID: "mangapill_json",
            title: "Hime no Dameshi",
            coverURL: nil,
            synopsis: "yomuhon-declarative-source-url:https://mangapill.com/manga/1714/hime-no-dameshi",
            chapters: []
        )

        XCTAssertEqual(manga.declarativeSourceURL?.query, "title_no=123")

        let detailed = try source.fetchDetails(for: manga)
        XCTAssertEqual(detailed.declarativeSourceURL?.query, "title_no=123")
        let chapter = try XCTUnwrap(detailed.chapters.first)
        let pages = try source.fetchPages(for: chapter, manga: detailed)

        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages.first?.imageURL?.host, "cdn.readdetectiveconan.com")
    }

    func testDeclarativeNetworkPolicyAllowsPublicHTTPSAndDynamicCDNs() throws {
        let dynamicCDN = try XCTUnwrap(URL(string: "https://cdxmd98sb0x3yprd.mangadex.network/data/page.jpg"))
        let unexpectedPublicCDN = try XCTUnwrap(URL(string: "https://images.example.net/page.webp"))

        XCTAssertTrue(DeclarativeNetworkURLPolicy.permits(dynamicCDN))
        XCTAssertTrue(
            DeclarativeNetworkURLPolicy.isExpectedHost(
                dynamicCDN.host,
                allowedDomains: ["mangadex.network"]
            )
        )

        XCTAssertTrue(DeclarativeNetworkURLPolicy.permits(unexpectedPublicCDN))
        XCTAssertFalse(
            DeclarativeNetworkURLPolicy.isExpectedHost(
                unexpectedPublicCDN.host,
                allowedDomains: ["mangadex.network"]
            )
        )
    }

    func testDeclarativeNetworkPolicyBlocksLocalPrivateAndNonHTTPSURLs() throws {
        let blockedValues = [
            "https://localhost/page.jpg",
            "https://reader.local/page.jpg",
            "https://127.0.0.1/page.jpg",
            "https://10.0.0.1/page.jpg",
            "https://172.16.0.1/page.jpg",
            "https://192.168.1.1/page.jpg",
            "https://169.254.169.254/latest/meta-data/",
            "https://[::1]/page.jpg",
            "https://[fd00::1]/page.jpg",
            "http://example.com/page.jpg"
        ]

        for value in blockedValues {
            let url = try XCTUnwrap(URL(string: value), value)
            XCTAssertFalse(DeclarativeNetworkURLPolicy.permits(url), value)
        }
    }

    func testRemoteConfigValidatorRejectsVersionAndDomainMismatch() throws {
        let config = try JSONDecoder().decode(
            DeclarativeSourceConfig.self,
            from: Data(TestSourceFixtures.mangaPillJSON.utf8)
        )
        let matchingEntry = DeclarativeSourceIndexEntry(
            id: config.id,
            name: config.name,
            version: config.version,
            language: config.language,
            kind: "declarative-html",
            url: try XCTUnwrap(URL(string: "https://raw.githubusercontent.com/lukqo/Yomuhon-Sources/main/sources/mangapill.json")),
            enabled: true,
            experimental: true,
            status: "testing",
            allowedDomains: config.allowedDomains,
            notes: nil
        )
        let wrongVersionEntry = DeclarativeSourceIndexEntry(
            id: matchingEntry.id,
            name: matchingEntry.name,
            version: matchingEntry.version + 1,
            language: matchingEntry.language,
            kind: matchingEntry.kind,
            url: matchingEntry.url,
            enabled: matchingEntry.enabled,
            experimental: matchingEntry.experimental,
            status: matchingEntry.status,
            allowedDomains: matchingEntry.allowedDomains,
            notes: matchingEntry.notes
        )

        XCTAssertTrue(DeclarativeSourceConfigurationValidator.validate(config: config, against: matchingEntry))
        XCTAssertFalse(DeclarativeSourceConfigurationValidator.validate(config: config, against: wrongVersionEntry))

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(TestSourceFixtures.mangaPillJSON.utf8)) as? [String: Any]
        )
        object["allowedDomains"] = ["mangapill.com", "evil.example"]
        let mismatchedDomainConfig = try JSONDecoder().decode(
            DeclarativeSourceConfig.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertFalse(
            DeclarativeSourceConfigurationValidator.validate(
                config: mismatchedDomainConfig,
                against: matchingEntry
            )
        )
    }



    func testRemoteCatalogDiscoversCompatibleSourceWithoutHardCodedAdapter() throws {
        var configObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(TestSourceFixtures.mangaPillJSON.utf8)
            ) as? [String: Any]
        )
        configObject["id"] = "fixture_source"
        configObject["name"] = "Fixture Source"
        configObject["version"] = 7
        configObject["language"] = "en"
        configObject["baseURL"] = "https://fixture.example"
        configObject["allowedDomains"] = ["fixture.example"]
        configObject.removeValue(forKey: "tests")
        let configData = try JSONSerialization.data(withJSONObject: configObject)
        let testData = try JSONSerialization.data(withJSONObject: [
            "sourceID": "fixture_source",
            "queries": ["fallback fixture query"],
            "probe": [
                "query": "fixture manga",
                "expectedTitleContains": "Fixture",
                "mangaPathContains": "/manga/",
                "chapterPathContains": "/chapters/"
            ],
            "expected": [
                "minSearchResults": 1,
                "minChapters": 2,
                "minPages": 3
            ]
        ])

        let configURL = try XCTUnwrap(
            URL(string: "https://catalog.example/sources/fixture_source.json")
        )
        let indexObject: [String: Any] = [
            "schemaVersion": 1,
            "updatedAt": "2026-07-11",
            "minimumAppVersion": "1.0.0",
            "sources": [[
                "id": "fixture_source",
                "name": "Fixture Source",
                "version": 7,
                "language": "en",
                "kind": "declarative-html",
                "url": configURL.absoluteString,
                "enabled": true,
                "experimental": true,
                "status": "testing",
                "allowedDomains": ["fixture.example"]
            ]]
        ]
        let indexData = try JSONSerialization.data(withJSONObject: indexObject)

        let configs = try DeclarativeRemoteConfigLoader.resolveConfigs(
            indexData: indexData,
            configDataLoader: { url in
                if url == configURL {
                    return configData
                }

                XCTAssertEqual(
                    url.absoluteString,
                    "https://catalog.example/tests/fixture_source.test.json"
                )
                return testData
            }
        )

        XCTAssertEqual(configs.map(\.id), ["fixture_source"])
        XCTAssertEqual(configs.first?.version, 7)
        XCTAssertEqual(configs.first?.baseURL.host, "fixture.example")
        XCTAssertEqual(configs.first?.tests?.query, "fixture manga")
        XCTAssertEqual(configs.first?.tests?.minChapters, 2)
        XCTAssertEqual(configs.first?.tests?.minPages, 3)
    }

    func testRemoteCatalogKeepsLastKnownGoodConfigWhenOneDefinitionFetchFails() throws {
        let cachedConfig = try JSONDecoder().decode(
            DeclarativeSourceConfig.self,
            from: Data(TestSourceFixtures.mangaPillJSON.utf8)
        )
        let configURL = try XCTUnwrap(
            URL(string: "https://catalog.example/sources/mangapill_json.json")
        )
        let indexObject: [String: Any] = [
            "schemaVersion": 1,
            "updatedAt": "2026-07-12",
            "minimumAppVersion": "1.0.0",
            "sources": [[
                "id": "mangapill_json",
                "name": "MangaPill JSON",
                "version": cachedConfig.version + 1,
                "language": "en",
                "kind": "declarative-html",
                "url": configURL.absoluteString,
                "enabled": true,
                "experimental": true,
                "status": "testing",
                "allowedDomains": cachedConfig.allowedDomains
            ]]
        ]
        let indexData = try JSONSerialization.data(withJSONObject: indexObject)

        let configs = try DeclarativeRemoteConfigLoader.resolveConfigs(
            indexData: indexData,
            fallbackCurrent: [cachedConfig],
            configDataLoader: { _ in
                throw ProbeError.forcedFailure
            }
        )

        XCTAssertEqual(configs.map(\.id), ["mangapill_json"])
        XCTAssertEqual(configs.first?.version, cachedConfig.version)
    }

    func testRemoteCatalogStillDropsLastKnownGoodConfigWhenIndexDisablesSource() throws {
        let cachedConfig = try JSONDecoder().decode(
            DeclarativeSourceConfig.self,
            from: Data(TestSourceFixtures.mangaPillJSON.utf8)
        )
        let configURL = try XCTUnwrap(
            URL(string: "https://catalog.example/sources/mangapill_json.json")
        )
        let indexObject: [String: Any] = [
            "schemaVersion": 1,
            "updatedAt": "2026-07-12",
            "minimumAppVersion": "1.0.0",
            "sources": [[
                "id": "mangapill_json",
                "name": "MangaPill JSON",
                "version": cachedConfig.version + 1,
                "language": "en",
                "kind": "declarative-html",
                "url": configURL.absoluteString,
                "enabled": false,
                "experimental": true,
                "status": "disabled",
                "allowedDomains": cachedConfig.allowedDomains
            ]]
        ]
        let indexData = try JSONSerialization.data(withJSONObject: indexObject)

        let configs = try DeclarativeRemoteConfigLoader.resolveConfigs(
            indexData: indexData,
            fallbackCurrent: [cachedConfig],
            configDataLoader: { _ in
                throw ProbeError.forcedFailure
            }
        )

        XCTAssertTrue(configs.isEmpty)
    }

    func testRemoteConfigAcceptsMissingLegacyEnabledByDefault() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(TestSourceFixtures.mangaPillJSON.utf8)
            ) as? [String: Any]
        )
        object.removeValue(forKey: "enabledByDefault")

        let config = try JSONDecoder().decode(
            DeclarativeSourceConfig.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(config.enabledByDefault)
        XCTAssertTrue(DeclarativeSourceConfigurationValidator.validateStandalone(config))
    }

    func testRemoteConfigRejectsLegacyEnabledByDefaultTrue() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(TestSourceFixtures.mangaPillJSON.utf8)
            ) as? [String: Any]
        )
        object["enabledByDefault"] = true

        let config = try JSONDecoder().decode(
            DeclarativeSourceConfig.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(config.enabledByDefault, true)
        XCTAssertFalse(DeclarativeSourceConfigurationValidator.validateStandalone(config))
    }

    func testLiveFiftyMangaReadabilitySmokeMatrix() throws {
        guard ProcessInfo.processInfo.environment["YOMUHON_RUN_LIVE_SMOKE_TESTS"] == "1" else {
            throw XCTSkip("Set YOMUHON_RUN_LIVE_SMOKE_TESTS=1 to run the 50-title source smoke matrix.")
        }

        let titles = [
            "One Piece", "Naruto", "Bleach", "Berserk", "Chainsaw Man",
            "Jujutsu Kaisen", "Demon Slayer", "My Hero Academia", "Attack on Titan", "Frieren",
            "Blue Lock", "Blue Box", "Dandadan", "Spy x Family", "Oshi no Ko",
            "Kagurabachi", "Sakamoto Days", "Kaiju No. 8", "Dr. Stone", "Black Clover",
            "Hunter x Hunter", "JoJo's Bizarre Adventure", "Death Note", "Fullmetal Alchemist", "Vagabond",
            "Vinland Saga", "Kingdom", "Tokyo Ghoul", "Monster", "20th Century Boys",
            "Pluto", "Slam Dunk", "Haikyuu", "Kuroko's Basketball", "Gintama",
            "Fairy Tail", "Fire Force", "Soul Eater", "Tokyo Revengers", "The Promised Neverland",
            "Mob Psycho 100", "One Punch Man", "Mashle", "Hell's Paradise", "Noragami",
            "Komi Can't Communicate", "Kaguya-sama: Love Is War", "Horimiya", "The Apothecary Diaries", "Claymore"
        ]

        let sources: [Source] = DeclarativeRemoteConfigLoader
            .availableConfigs()
            .filter { config in
                config.supports.search
                    && config.supports.chapters
                    && config.supports.pages
            }
            .map { DeclarativeSourceRuntime(config: $0) }

        XCTAssertFalse(sources.isEmpty, "The remote source catalog did not expose a readable source.")

        var successes: [String] = []
        var failures: [String] = []

        for title in titles {
            var lastFailure = "No source returned a readable candidate."
            var didOpenFirstPage = false

            sourceLoop: for source in sources {
                do {
                    let results = try source.searchManga(query: title)
                    let candidates = results
                        .sorted { lhs, rhs in
                            let lhsMatch = MangaIdentityResolver.sameWork(lhsTitle: title, rhsTitle: lhs.title)
                            let rhsMatch = MangaIdentityResolver.sameWork(lhsTitle: title, rhsTitle: rhs.title)
                            if lhsMatch != rhsMatch { return lhsMatch && !rhsMatch }
                            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                        }
                        .prefix(8)

                    for candidate in candidates {
                        let detailed = try source.fetchDetails(for: candidate)
                        guard let firstChapter = detailed.chapters.first else {
                            continue
                        }

                        let pages = try source.fetchPages(for: firstChapter, manga: detailed)
                        guard pages.contains(where: { $0.imageURL != nil || $0.localFileURL != nil }) else {
                            continue
                        }

                        successes.append(title)
                        didOpenFirstPage = true
                        break sourceLoop
                    }

                    lastFailure = "\(source.id) returned no detail with chapters and real pages."
                } catch {
                    lastFailure = "\(source.id): \(error)"
                }
            }

            if !didOpenFirstPage {
                failures.append("\(title) — \(lastFailure)")
            }
        }

        XCTAssertGreaterThanOrEqual(
            successes.count,
            40,
            "Only \(successes.count)/50 titles completed search → detail → chapters → pages. Failures: \(failures.joined(separator: " | "))"
        )
    }

    func testReaderUsesGlobalDefaultsForANewManga() {
        let defaults = UserDefaults.standard
        let previousMode = defaults.object(forKey: ReaderPreferenceKeys.defaultReadingMode)
        let previousFit = defaults.object(forKey: ReaderPreferenceKeys.defaultFitMode)

        defer {
            if let previousMode {
                defaults.set(previousMode, forKey: ReaderPreferenceKeys.defaultReadingMode)
            } else {
                defaults.removeObject(forKey: ReaderPreferenceKeys.defaultReadingMode)
            }

            if let previousFit {
                defaults.set(previousFit, forKey: ReaderPreferenceKeys.defaultFitMode)
            } else {
                defaults.removeObject(forKey: ReaderPreferenceKeys.defaultFitMode)
            }
        }

        defaults.set(ReadingMode.webtoon.rawValue, forKey: ReaderPreferenceKeys.defaultReadingMode)
        defaults.set(ReaderFitMode.fitWidth.rawValue, forKey: ReaderPreferenceKeys.defaultFitMode)

        let mangaID = "reader-defaults-\(UUID().uuidString)"
        let chapter = Chapter(
            id: "reader-defaults-chapter",
            mangaID: mangaID,
            number: 1,
            title: "Chapter 1",
            pages: [],
            isDownloaded: false
        )
        let manga = Manga(
            id: mangaID,
            sourceID: "fixture_source",
            title: "Reader Defaults",
            coverURL: nil,
            synopsis: nil,
            chapters: [chapter]
        )

        let viewModel = ReaderViewModel(
            manga: manga,
            chapter: chapter,
            sourceRepository: TestSourceRepository()
        )

        XCTAssertEqual(viewModel.readingMode, .webtoon)
        XCTAssertEqual(viewModel.fitMode, .fitWidth)
    }

    func testReaderModeChangesAreGlobalAcrossMangas() {
        let defaults = UserDefaults.standard
        let previousMode = defaults.object(forKey: ReaderPreferenceKeys.defaultReadingMode)

        defer {
            if let previousMode {
                defaults.set(previousMode, forKey: ReaderPreferenceKeys.defaultReadingMode)
            } else {
                defaults.removeObject(forKey: ReaderPreferenceKeys.defaultReadingMode)
            }
        }

        defaults.set(ReadingMode.paged.rawValue, forKey: ReaderPreferenceKeys.defaultReadingMode)

        let firstChapter = Chapter(id: "global-reader-1", mangaID: "global-reader-a", number: 1, title: nil, pages: [], isDownloaded: false)
        let firstManga = Manga(id: "global-reader-a", sourceID: "fixture", title: "A", coverURL: nil, synopsis: nil, chapters: [firstChapter])
        let first = ReaderViewModel(manga: firstManga, chapter: firstChapter, sourceRepository: TestSourceRepository())
        first.handleReadingModeChange(.webtoon)

        let secondChapter = Chapter(id: "global-reader-2", mangaID: "global-reader-b", number: 1, title: nil, pages: [], isDownloaded: false)
        let secondManga = Manga(id: "global-reader-b", sourceID: "fixture", title: "B", coverURL: nil, synopsis: nil, chapters: [secondChapter])
        let second = ReaderViewModel(manga: secondManga, chapter: secondChapter, sourceRepository: TestSourceRepository())

        XCTAssertEqual(second.readingMode, .webtoon)
    }

    func testSourceDisplayNameHidesRuntimeSuffixWithoutProviderHardcoding() {
        XCTAssertEqual(
            NativeSourceCatalog.displayName(for: "sample_reader_json"),
            "Sample Reader"
        )
    }

    func testMangaIdentityResolverGroupsHarmlessDescriptorSuffix() {
        XCTAssertTrue(
            MangaIdentityResolver.sameWork(
                lhsTitle: "Blue Box",
                rhsTitle: "Blue Box Manga"
            )
        )
    }

    func testMangaIdentityResolverDoesNotMergeDifferentShortTitles() {
        XCTAssertFalse(
            MangaIdentityResolver.sameWork(
                lhsTitle: "Blue Lock",
                rhsTitle: "Blue Box"
            )
        )
    }

    func testReaderPrefetchIndexesClampToBoundsAndPrioritizeCurrentPage() {
        XCTAssertEqual(
            ReaderViewModel.prefetchIndexes(
                currentIndex: 0,
                pageCount: 5,
                radius: 2
            ),
            [0, 1, 2]
        )

        XCTAssertEqual(
            ReaderViewModel.prefetchIndexes(
                currentIndex: 3,
                pageCount: 5,
                radius: 2
            ),
            [3, 2, 4, 1]
        )

        XCTAssertEqual(
            ReaderViewModel.prefetchIndexes(
                currentIndex: 0,
                pageCount: 0,
                radius: 2
            ),
            []
        )
    }

    func testDeclarativeHTMLRootSearchRouteBuildsRequest() throws {
        let configJSON = #"""
        {
          "schemaVersion": 1,
          "id": "root_route_fixture",
          "name": "Root Route Fixture",
          "version": 1,
          "language": "en",
          "baseURL": "https://example.com",
          "engineMode": "html",
          "enabledByDefault": false,
          "experimental": true,
          "allowedDomains": ["example.com"],
          "supports": {
            "search": true,
            "popular": false,
            "details": false,
            "chapters": false,
            "pages": false
          },
          "routes": {
            "search": {
              "path": "/",
              "query": {
                "search": "{{query}}",
                "search_by": "book_name"
              }
            }
          },
          "selectors": {
            "search": {
              "container": "a[href*='/manga/']",
              "title": { "attrs": ["text"] },
              "url": { "attrs": ["href"], "required": true }
            }
          }
        }
        """#

        let config = try JSONDecoder().decode(
            DeclarativeSourceConfig.self,
            from: Data(configJSON.utf8)
        )
        var requestedURL: URL?
        let source = DeclarativeSourceRuntime(config: config) { request in
            requestedURL = request.url
            return Data(#"<html><body><a href="/manga/one-piece.49">One Piece</a></body></html>"#.utf8)
        }

        let results = try source.searchManga(query: "one piece")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(requestedURL?.host, "example.com")
        XCTAssertEqual(requestedURL?.path, "/")
        let components = URLComponents(url: try XCTUnwrap(requestedURL), resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        XCTAssertEqual(query["search"], "one piece")
        XCTAssertEqual(query["search_by"], "book_name")
    }

    func testLegacyDeclarativeConfigWithoutGenresRemainsDecodable() throws {
        let config = try JSONDecoder().decode(
            DeclarativeSourceConfig.self,
            from: Data(TestSourceFixtures.mangaPillJSON.utf8)
        )

        XCTAssertFalse(config.supports.supportsGenres)
        XCTAssertNil(config.discover)
    }

    func testDeclarativeGenreDiscoveryUsesDeclaredCategoryRouteInsteadOfSearch() throws {
        let configJSON = #"""
        {
          "schemaVersion": 1,
          "id": "genre_fixture",
          "name": "Genre Fixture",
          "version": 1,
          "language": "en",
          "baseURL": "https://example.com",
          "engineMode": "html",
          "enabledByDefault": false,
          "experimental": true,
          "allowedDomains": ["example.com"],
          "supports": {
            "search": false,
            "popular": false,
            "details": false,
            "chapters": false,
            "pages": false,
            "genres": true
          },
          "routes": {},
          "selectors": {},
          "discover": {
            "genres": {
              "items": [
                {"id": "action", "title": "Action", "value": "action"}
              ],
              "operation": {
                "route": {
                  "path": "/genre/{{genre}}/page/{page}",
                  "pagination": {"type": "path", "start": 1, "maxPages": 1}
                },
                "selector": {
                  "container": "div#book_list div.item",
                  "title": {"selectors": ["div.text h3 a"], "attrs": ["text"]},
                  "url": {"selectors": ["div.text h3 a"], "attrs": ["href"], "required": true},
                  "cover": {"selectors": ["img"], "attrs": ["src"]}
                }
              }
            }
          }
        }
        """#

        let config = try JSONDecoder().decode(
            DeclarativeSourceConfig.self,
            from: Data(configJSON.utf8)
        )
        var requestedURL: URL?
        let source = DeclarativeSourceRuntime(config: config) { request in
            requestedURL = request.url
            return Data(#"""
            <html><body>
              <div id="book_list">
                <div class="item">
                  <img src="/cover.jpg">
                  <div class="text"><h3><a href="/manga/action-hero.1">Action Hero</a></h3></div>
                </div>
              </div>
            </body></html>
            """#.utf8)
        }

        let mangas = try source.manga(forGenreID: "action")

        XCTAssertEqual(source.discoveryGenres, [SourceDiscoveryGenre(id: "action", title: "Action")])
        XCTAssertEqual(mangas.map(\.title), ["Action Hero"])
        XCTAssertEqual(requestedURL?.path, "/genre/action/page/1")
        XCTAssertNil(URLComponents(url: try XCTUnwrap(requestedURL), resolvingAgainstBaseURL: false)?.query)
    }

    func testPopularDiscoveryScopesNamedShelfAndMergesCoverWithTitleAnchor() throws {
        let configJSON = #"""
        {
          "schemaVersion": 1,
          "id": "popular_scope_fixture",
          "name": "Popular Scope Fixture",
          "version": 1,
          "language": "en",
          "baseURL": "https://example.com",
          "engineMode": "html",
          "enabledByDefault": false,
          "experimental": true,
          "allowedDomains": ["example.com", "cdn.example.com"],
          "supports": {
            "search": false,
            "popular": true,
            "details": false,
            "chapters": false,
            "pages": false
          },
          "routes": {},
          "selectors": {},
          "discover": {
            "popular": {
              "route": {"path": "/"},
              "selector": {
                "container": "a[href*=\"/manga/\"]",
                "title": {"attrs": ["text"]},
                "url": {"attrs": ["href"], "required": true},
                "cover": {"selectors": ["img"], "attrs": ["src"]},
                "htmlScope": {
                  "afterRegex": ">\\s*Hot Manga\\s*<",
                  "beforeRegex": "<footer\\b"
                }
              }
            }
          }
        }
        """#

        let config = try JSONDecoder().decode(
            DeclarativeSourceConfig.self,
            from: Data(configJSON.utf8)
        )
        let source = DeclarativeSourceRuntime(config: config) { _ in
            Data(#"""
            <html><body>
              <a href="/manga/not-popular.1"><img src="https://cdn.example.com/not-popular.jpg">Not Popular</a>
              <aside><h3>Hot Manga</h3>
                <a href="/manga/actual-hot-title.42"><img src="https://cdn.example.com/hot.jpg"></a>
                <h4><a href="/manga/actual-hot-title.42">Actual Hot Title</a></h4>
                <a href="/manga/actual-hot-title.42/c12">Chapter 12</a>
              </aside>
              <footer><a href="/manga/footer-title.8">Footer Title</a></footer>
            </body></html>
            """#.utf8)
        }

        let mangas = try source.popularManga()

        XCTAssertEqual(mangas.count, 1)
        XCTAssertEqual(mangas.first?.title, "Actual Hot Title")
        XCTAssertEqual(mangas.first?.coverURL?.absoluteString, "https://cdn.example.com/hot.jpg")
        XCTAssertEqual(mangas.first?.declarativeSourceURL?.path, "/manga/actual-hot-title.42")
    }

    func testPopularDiscoveryPublishesProgressAndSurvivesOneSourceFailure() throws {
        let goodID = "discover_good_\(UUID().uuidString)"
        let badID = "discover_bad_\(UUID().uuidString)"
        let repository = SourceRepositoryImpl(
            sources: [
                PopularDiscoveryProbeSource(id: goodID, shouldFail: false),
                PopularDiscoveryProbeSource(id: badID, shouldFail: true)
            ]
        )
        let lock = NSLock()
        var progressSourceIDs = Set<String>()

        let mangas = try repository.popularManga { progress in
            lock.lock()
            progressSourceIDs.insert(progress.sourceID)
            lock.unlock()
        }

        XCTAssertEqual(mangas.map(\.sourceID), [goodID])
        XCTAssertEqual(progressSourceIDs, Set([goodID, badID]))
    }

    func testPopularDiscoveryCancellationStopsInFlightSourceWork() throws {
        let source = CancellableDiscoveryProbeSource()
        let repository = SourceRepositoryImpl(sources: [source])
        let token = RequestCancellationToken()
        let finished = expectation(description: "discovery cancellation finishes")
        let lock = NSLock()
        var capturedError: Error?

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try repository.popularManga(
                    cancellationToken: token,
                    progress: { _ in }
                )
            } catch {
                lock.lock()
                capturedError = error
                lock.unlock()
            }
            finished.fulfill()
        }

        XCTAssertTrue(source.waitUntilStarted(timeout: 1.0))
        token.cancel()
        wait(for: [finished], timeout: 1.5)

        lock.lock()
        let error = capturedError
        lock.unlock()

        guard case HTTPClientError.cancelled? = error else {
            return XCTFail("Expected discovery cancellation, got \(String(describing: error))")
        }
        XCTAssertTrue(source.didObserveCancellation)
    }

    func testSearchRankingKeepsExactTitleAboveProviderRank() throws {
        let exact = Manga(
            id: "exact",
            sourceID: "ranking_source_exact",
            title: "Berserk",
            coverURL: URL(string: "https://example.com/berserk.jpg"),
            synopsis: nil,
            chapters: []
        )
        let providerFavorite = Manga(
            id: "provider-favorite",
            sourceID: "ranking_source_favorite",
            title: "Berserk of Gluttony",
            coverURL: URL(string: "https://example.com/gluttony.jpg"),
            synopsis: nil,
            chapters: []
        )
        let positions = [
            "ranking_source_exact|exact": 40,
            "ranking_source_favorite|provider-favorite": 1
        ]

        let exactScore = SearchResultRanker.score(
            query: "berserk",
            manga: exact,
            sourcePositions: positions
        )
        let providerFavoriteScore = SearchResultRanker.score(
            query: "berserk",
            manga: providerFavorite,
            sourcePositions: positions
        )

        XCTAssertGreaterThan(exactScore, providerFavoriteScore)
    }

    func testSearchRankingUsesFuzzyTitleSimilarityForTypos() throws {
        let intended = Manga(
            id: "intended",
            sourceID: "ranking_source_a",
            title: "Berserk",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )
        let unrelatedPrefix = Manga(
            id: "unrelated",
            sourceID: "ranking_source_b",
            title: "Berserk of Gluttony",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )

        XCTAssertGreaterThan(
            SearchResultRanker.titleScore(query: "bersrk", title: intended.title),
            SearchResultRanker.titleScore(query: "bersrk", title: unrelatedPrefix.title)
        )
    }

    func testSearchRankingPrefersClosestTitleForPartialTypo() throws {
        XCTAssertGreaterThan(
            SearchResultRanker.titleScore(query: "one piec", title: "One Piece"),
            SearchResultRanker.titleScore(query: "one piec", title: "One Piece Party")
        )
    }

    func testPopularConsensusAcrossSourcesBeatsSingleSourceFirstPlace() throws {
        let onePieceA = Manga(
            id: "one-piece-a",
            sourceID: "ranking_source_a",
            title: "One Piece",
            coverURL: URL(string: "https://example.com/a.jpg"),
            synopsis: nil,
            chapters: []
        )
        let onePieceB = Manga(
            id: "one-piece-b",
            sourceID: "ranking_source_b",
            title: "One Piece",
            coverURL: URL(string: "https://example.com/b.jpg"),
            synopsis: nil,
            chapters: []
        )
        let onePieceC = Manga(
            id: "one-piece-c",
            sourceID: "ranking_source_c",
            title: "One Piece",
            coverURL: URL(string: "https://example.com/c.jpg"),
            synopsis: nil,
            chapters: []
        )
        let soloLeveling = Manga(
            id: "solo",
            sourceID: "ranking_source_d",
            title: "Solo Leveling",
            coverURL: URL(string: "https://example.com/solo.jpg"),
            synopsis: nil,
            chapters: []
        )
        let positions = [
            "ranking_source_a|one-piece-a": 2,
            "ranking_source_b|one-piece-b": 5,
            "ranking_source_c|one-piece-c": 8,
            "ranking_source_d|solo": 1
        ]

        let onePieceScore = DiscoveryRanker.score(
            for: [onePieceA, onePieceB, onePieceC],
            sourcePositions: positions
        )
        let soloScore = DiscoveryRanker.score(
            for: [soloLeveling],
            sourcePositions: positions
        )

        XCTAssertGreaterThan(onePieceScore, soloScore)
    }

    func testDeclarativeHTMLIdentityMetadataIsProviderDeclared() throws {
        let configJSON = #"""
        {
          "schemaVersion": 1,
          "id": "identity_html_fixture",
          "name": "Identity HTML Fixture",
          "version": 1,
          "language": "en",
          "baseURL": "https://example.com",
          "engineMode": "html",
          "enabledByDefault": false,
          "experimental": true,
          "allowedDomains": ["example.com"],
          "supports": {
            "search": true,
            "popular": false,
            "details": false,
            "chapters": false,
            "pages": false
          },
          "routes": {
            "search": {"path": "/search", "query": {"q": "{{query}}"}}
          },
          "selectors": {
            "search": {
              "container": ".item",
              "title": {"selectors": [".title"], "attrs": ["text"]},
              "url": {"selectors": [".title"], "attrs": ["href"], "required": true},
              "alternativeTitles": {"selectors": [".alt"], "attrs": ["text"]},
              "author": {"selectors": [".author"], "attrs": ["text"]},
              "year": {"selectors": [".year"], "attrs": ["text"]}
            }
          }
        }
        """#

        let config = try JSONDecoder().decode(
            DeclarativeSourceConfig.self,
            from: Data(configJSON.utf8)
        )
        let source = DeclarativeSourceRuntime(config: config) { _ in
            Data(#"""
            <div class="item">
              <a class="title" href="/manga/hero">Boku no Hero Academia</a>
              <span class="alt">My Hero Academia | 僕のヒーローアカデミア</span>
              <span class="author">Kohei Horikoshi</span>
              <span class="year">First published 2014</span>
            </div>
            """#.utf8)
        }

        let manga = try XCTUnwrap(source.searchManga(query: "hero").first)
        XCTAssertEqual(Set(manga.alternativeTitles ?? []), Set(["My Hero Academia", "僕のヒーローアカデミア"]))
        XCTAssertEqual(manga.author, "Kohei Horikoshi")
        XCTAssertEqual(manga.releaseYear, 2014)
    }

    func testDeclarativeJSONIdentityMetadataSupportsWildcardPaths() throws {
        let configJSON = #"""
        {
          "schemaVersion": 1,
          "id": "identity_api_fixture",
          "name": "Identity API Fixture",
          "version": 1,
          "language": "multi",
          "baseURL": "https://api.example.com",
          "engineMode": "json-api",
          "enabledByDefault": false,
          "experimental": true,
          "allowedDomains": ["api.example.com"],
          "supports": {
            "search": true,
            "popular": false,
            "details": false,
            "chapters": false,
            "pages": false
          },
          "routes": {},
          "selectors": {},
          "api": {
            "search": {
              "request": {
                "method": "GET",
                "path": "/manga",
                "query": {"title": "{{query}}"}
              },
              "itemsPath": "data",
              "idPath": "id",
              "titlePaths": ["attributes.title.en"],
              "alternativeTitlePaths": ["attributes.altTitles.*.*"],
              "authorPaths": ["attributes.authors.0.name"],
              "yearPath": "attributes.year"
            }
          }
        }
        """#
        let responseJSON = #"""
        {
          "data": [
            {
              "id": "hero",
              "attributes": {
                "title": {"en": "Boku no Hero Academia"},
                "altTitles": [
                  {"en": "My Hero Academia"},
                  {"ja": "僕のヒーローアカデミア"}
                ],
                "authors": [{"name": "Kohei Horikoshi"}],
                "year": 2014
              }
            }
          ]
        }
        """#

        let config = try JSONDecoder().decode(
            DeclarativeSourceConfig.self,
            from: Data(configJSON.utf8)
        )
        let source = DeclarativeSourceRuntime(config: config) { _ in
            Data(responseJSON.utf8)
        }

        let manga = try XCTUnwrap(source.searchManga(query: "hero").first)
        XCTAssertEqual(Set(manga.alternativeTitles ?? []), Set(["My Hero Academia", "僕のヒーローアカデミア"]))
        XCTAssertEqual(manga.author, "Kohei Horikoshi")
        XCTAssertEqual(manga.releaseYear, 2014)
    }

    func testMangaIdentityResolverUsesDeclaredAlternativeTitles() {
        let japaneseTitle = Manga(
            id: "hero-jp",
            sourceID: "identity_a",
            title: "Boku no Hero Academia",
            coverURL: nil,
            synopsis: nil,
            alternativeTitles: ["My Hero Academia"],
            author: "Kohei Horikoshi",
            releaseYear: 2014,
            chapters: []
        )
        let englishTitle = Manga(
            id: "hero-en",
            sourceID: "identity_b",
            title: "My Hero Academia",
            coverURL: nil,
            synopsis: nil,
            author: "Kohei Horikoshi",
            releaseYear: 2014,
            chapters: []
        )

        XCTAssertTrue(MangaIdentityResolver.sameWork(japaneseTitle, englishTitle))
    }

    func testMangaIdentityResolverRefusesConflictingYears() {
        let original = Manga(
            id: "same-title-a",
            sourceID: "identity_a",
            title: "Shared Title",
            coverURL: nil,
            synopsis: nil,
            author: "Author One",
            releaseYear: 2014,
            chapters: []
        )
        let differentWork = Manga(
            id: "same-title-b",
            sourceID: "identity_b",
            title: "Shared Title",
            coverURL: nil,
            synopsis: nil,
            author: "Author Two",
            releaseYear: 2020,
            chapters: []
        )

        XCTAssertFalse(MangaIdentityResolver.sameWork(original, differentWork))
    }

    func testSearchRankingUsesAlternativeTitleForExactMatch() {
        let aliased = Manga(
            id: "aliased",
            sourceID: "ranking_alias",
            title: "Boku no Hero Academia",
            coverURL: nil,
            synopsis: nil,
            alternativeTitles: ["My Hero Academia"],
            chapters: []
        )
        let looseMatch = Manga(
            id: "loose",
            sourceID: "ranking_loose",
            title: "My Hero Academia Side Story",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )

        XCTAssertGreaterThan(
            SearchResultRanker.score(query: "my hero academia", manga: aliased, sourcePositions: [:]),
            SearchResultRanker.score(query: "my hero academia", manga: looseMatch, sourcePositions: [:])
        )
    }

    func testStableRankingDoesNotSwapNearTiesWhileLoading() {
        let order = StableRankingReconciler.reconcile(
            previous: ["a", "b", "c"],
            rankedIDs: ["b", "a", "c"],
            scores: ["a": 1_000, "b": 1_010, "c": 500],
            dominantIDs: [],
            minimumPromotionDelta: 450,
            relativePromotionDelta: 0.04,
            settle: false
        )

        XCTAssertEqual(order, ["a", "b", "c"])
    }

    func testStableRankingLetsDominantExactMatchJumpImmediately() {
        let order = StableRankingReconciler.reconcile(
            previous: ["a", "b", "c"],
            rankedIDs: ["b", "a", "c"],
            scores: ["a": 1_000, "b": 9_500, "c": 500],
            dominantIDs: ["b"],
            minimumPromotionDelta: 450,
            relativePromotionDelta: 0.04,
            settle: false
        )

        XCTAssertEqual(order, ["b", "a", "c"])
    }

    func testSourceMetricsTracksSuccessRateAndLatencyPercentiles() throws {
        let suiteName = "YomuhonMetricsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SourceMetricsStore(userDefaults: defaults)

        store.recordSuccess(sourceID: "metrics", operation: .search, latency: 0.1)
        store.recordSuccess(sourceID: "metrics", operation: .search, latency: 0.2)
        store.recordSuccess(sourceID: "metrics", operation: .search, latency: 1.0)
        store.recordFailure(sourceID: "metrics", operation: .search)

        let snapshot = store.snapshot(sourceID: "metrics", operation: .search)
        XCTAssertEqual(snapshot.successCount, 3)
        XCTAssertEqual(snapshot.failureCount, 1)
        XCTAssertEqual(snapshot.successRate, 0.75, accuracy: 0.0001)
        XCTAssertEqual(snapshot.p50Latency, 0.2, accuracy: 0.0001)
        XCTAssertEqual(snapshot.p95Latency, 1.0, accuracy: 0.0001)

        for _ in 0..<40 {
            store.recordFailure(sourceID: "recovering", operation: .search)
        }
        for _ in 0..<40 {
            store.recordSuccess(sourceID: "recovering", operation: .search, latency: 0.15)
        }
        XCTAssertEqual(
            store.snapshot(sourceID: "recovering", operation: .search).successRate,
            1,
            accuracy: 0.0001
        )
    }

    func testSourceQuerySchedulerBoundsSourceConcurrency() {
        let scheduler = SourceQueryScheduler.shared
        XCTAssertEqual(scheduler.maximumConcurrentSources, 5)
        let queue = scheduler.makeQueue(
            qualityOfService: .userInitiated,
            sourceCount: 40
        )
        XCTAssertEqual(queue.maxConcurrentOperationCount, 5)

        let group = DispatchGroup()
        let lock = NSLock()
        var active = 0
        var maximumObserved = 0

        for _ in 0..<12 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                _ = try? scheduler.withExecutionSlot(priority: .interactive) {
                    lock.lock()
                    active += 1
                    maximumObserved = max(maximumObserved, active)
                    lock.unlock()

                    Thread.sleep(forTimeInterval: 0.04)

                    lock.lock()
                    active -= 1
                    lock.unlock()
                }
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 3), .success)
        XCTAssertLessThanOrEqual(maximumObserved, 5)
    }

    func testMangaKatanaReaderRegexAcceptsPlainAndJavaScriptEscapedPageURLs() throws {
        let configJSON = #"""
        {
          "schemaVersion": 1,
          "id": "mangakatana_reader_fixture",
          "name": "MangaKatana Reader Fixture",
          "version": 7,
          "language": "en",
          "baseURL": "https://mangakatana.com",
          "engineMode": "html",
          "enabledByDefault": false,
          "experimental": true,
          "allowedDomains": [
            "mangakatana.com",
            "i.mkklcdnv6tempv2.com",
            "i.mkklcdnv6.com"
          ],
          "supports": {
            "search": false,
            "popular": false,
            "details": false,
            "chapters": false,
            "pages": true
          },
          "routes": {},
          "selectors": {
            "pages": {
              "extractors": [
                {
                  "type": "regex",
                  "pattern": "(https?:(?:\\\\/\\\\/|//)[^\"'\\\\\\s]+?\\.(?:jpg|jpeg|png|webp)(?:\\?[^\"'\\\\\\s]*)?)"
                }
              ],
              "filters": {
                "mustContain": [".jpg", ".jpeg", ".png", ".webp"],
                "blockContains": ["logo", "avatar", "placeholder", "banner", "ads/", "icon"]
              }
            }
          }
        }
        """#

        let config = try JSONDecoder().decode(
            DeclarativeSourceConfig.self,
            from: Data(configJSON.utf8)
        )
        let source = DeclarativeSourceRuntime(config: config) { _ in
            Data(#"""
            <script>
              const serverOne = ["https:\/\/i.mkklcdnv6.com/title/chapter/1.jpg"];
              const serverTwo = ["https://i.mkklcdnv6tempv2.com/title/chapter/2.webp?token=abc"];
            </script>
            """#.utf8)
        }
        let manga = Manga(
            id: "reader-regex-manga",
            sourceID: config.id,
            title: "Reader Regex Manga",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )
        let chapter = Chapter(
            id: "reader-regex-chapter",
            mangaID: manga.id,
            number: 1,
            title: "Chapter 1",
            pages: [],
            isDownloaded: false
        )
        .withDeclarativeSourceURL(URL(string: "https://mangakatana.com/manga/reader-regex.1/c1"))

        let pages = try source.fetchPages(for: chapter, manga: manga)

        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].imageURL?.absoluteString, "https://i.mkklcdnv6.com/title/chapter/1.jpg")
        XCTAssertEqual(pages[1].imageURL?.absoluteString, "https://i.mkklcdnv6tempv2.com/title/chapter/2.webp?token=abc")
    }

    func testOpeningReaderAddsMangaToLibraryMembership() throws {
        let mangaID = "reader-membership-\(UUID().uuidString)"
        defer { LibraryMembershipStore.shared.remove(mangaID) }
        LibraryMembershipStore.shared.remove(mangaID)

        let repository = PreviewLibraryRepository()
        let manga = Manga(
            id: mangaID,
            sourceID: "membership-probe",
            title: "Membership Probe",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )
        let chapter = Chapter(
            id: "membership-chapter",
            mangaID: mangaID,
            number: 1,
            title: "Chapter 1",
            pages: [],
            isDownloaded: false
        )

        UpdateReadingProgressUseCase(repository: repository)
            .execute(manga: manga, chapter: chapter, pageIndex: 0)

        XCTAssertTrue(LibraryMembershipStore.shared.contains(mangaID))
        XCTAssertEqual(
            repository.fetchReadingProgress().first(where: { $0.mangaID == mangaID })?.status,
            .reading
        )
    }

    func testDetailReaderDestinationUsesTappedChapterInsteadOfSavedProgressChapter() throws {
        let sourceRepository = TestSourceRepository()
        let libraryRepository = PreviewLibraryRepository()
        let chapterOne = Chapter(
            id: "chapter-one",
            mangaID: "chapter-destination-manga",
            number: 1,
            title: "Chapter 1",
            pages: [],
            isDownloaded: false
        )
        let chapterTwo = Chapter(
            id: "chapter-two",
            mangaID: "chapter-destination-manga",
            number: 2,
            title: "Chapter 2",
            pages: [],
            isDownloaded: false
        )
        let manga = Manga(
            id: "chapter-destination-manga",
            sourceID: "chapter-destination-source",
            title: "Chapter Destination",
            coverURL: nil,
            synopsis: nil,
            chapters: [chapterOne, chapterTwo]
        )
        let progress = ReadingProgress(
            id: "progress-chapter-destination",
            mangaID: manga.id,
            sourceID: manga.sourceID,
            currentChapterID: chapterTwo.id,
            currentPage: 5,
            lastReadAt: Date(),
            status: .reading
        )
        let viewModel = MangaDetailViewModel(
            manga: manga,
            progress: progress,
            getChapterListUseCase: GetChapterListUseCase(repository: sourceRepository),
            downloadChapterUseCase: DownloadChapterUseCase(
                downloadRepository: TestDownloadRepository(),
                libraryRepository: libraryRepository,
                sourceRepository: sourceRepository
            ),
            updateReadingProgressUseCase: UpdateReadingProgressUseCase(repository: libraryRepository),
            sourceRepository: sourceRepository,
            libraryRepository: libraryRepository
        )

        let reader = viewModel.readerViewModel(for: chapterOne)

        XCTAssertEqual(reader.chapterTitle, chapterOne.displayTitle)
        XCTAssertNotEqual(reader.chapterTitle, chapterTwo.displayTitle)
    }

    func testLanguageCanonicalizationSupportsRegionalCodesForPerTitleRouting() {
        XCTAssertEqual(NativeSourceCatalog.canonicalLanguageCode("es-419"), "es")
        XCTAssertEqual(NativeSourceCatalog.canonicalLanguageCode("es_CL"), "es")
        XCTAssertEqual(NativeSourceCatalog.canonicalLanguageCode("en-US"), "en")
        XCTAssertEqual(NativeSourceCatalog.canonicalLanguageCode("multi"), "multi")
    }

    func testLibraryOverviewAndCollectionsHaveDistinctMembershipSemantics() throws {
        let viewModel = LibraryViewModel(
            getLibraryUseCase: GetLibraryUseCase(repository: PreviewLibraryRepository())
        )

        XCTAssertEqual(viewModel.categoryCount(.all), viewModel.allLibraryMangas.count)
        XCTAssertEqual(viewModel.categoryCount(.reading), viewModel.readingMangas.count)
        XCTAssertEqual(viewModel.categoryCount(.completed), viewModel.completedMangas.count)
        XCTAssertEqual(viewModel.categoryCount(.planToRead), viewModel.planToReadMangas.count)

        viewModel.selectedCategory = .completed
        XCTAssertEqual(viewModel.visibleMangas.map(\.id), viewModel.completedMangas.map(\.id))
    }


    func testReaderAdvancesToNextChapterAndPersistsExactPosition() throws {
        let mangaID = "reader-transition-\(UUID().uuidString)"
        defer { LibraryMembershipStore.shared.remove(mangaID) }

        let chapterOne = Chapter(
            id: "reader-transition-c1",
            mangaID: mangaID,
            number: 1,
            title: "Chapter 1",
            pages: [
                Page(id: "c1-p1", index: 0, imageURL: URL(string: "https://example.com/c1-1.jpg"), localFileURL: nil),
                Page(id: "c1-p2", index: 1, imageURL: URL(string: "https://example.com/c1-2.jpg"), localFileURL: nil)
            ],
            isDownloaded: false
        )
        let chapterTwo = Chapter(
            id: "reader-transition-c2",
            mangaID: mangaID,
            number: 2,
            title: "Chapter 2",
            pages: [
                Page(id: "c2-p1", index: 0, imageURL: URL(string: "https://example.com/c2-1.jpg"), localFileURL: nil),
                Page(id: "c2-p2", index: 1, imageURL: URL(string: "https://example.com/c2-2.jpg"), localFileURL: nil)
            ],
            isDownloaded: false
        )
        let manga = Manga(
            id: mangaID,
            sourceID: "reader-transition-source",
            title: "Reader Transition",
            coverURL: nil,
            synopsis: nil,
            chapters: [chapterOne, chapterTwo]
        )
        let library = InMemoryLibraryRepository()
        let progressUseCase = UpdateReadingProgressUseCase(repository: library)
        let reader = ReaderViewModel(
            manga: manga,
            chapter: chapterOne,
            initialPageIndex: 1,
            updateReadingProgressUseCase: progressUseCase,
            sourceRepository: TestSourceRepository()
        )

        reader.goForward()
        XCTAssertEqual(reader.chapter.id, chapterTwo.id)
        XCTAssertEqual(reader.currentPageIndex, 0)

        reader.currentPageIndex = 1
        reader.flushProgress()
        let persisted = try XCTUnwrap(library.fetchReadingProgress().first { $0.mangaID == mangaID })
        XCTAssertEqual(persisted.currentChapterID, chapterTwo.id)
        XCTAssertEqual(persisted.currentPage, 1)

        let restored = ReaderViewModel(
            manga: manga,
            chapter: chapterTwo,
            initialPageIndex: persisted.currentPage,
            updateReadingProgressUseCase: progressUseCase,
            sourceRepository: TestSourceRepository()
        )
        XCTAssertEqual(restored.chapter.id, chapterTwo.id)
        XCTAssertEqual(restored.currentPageIndex, 1)
    }

    func testDownloadedChapterIsRecognizedAsOfflineReadableOnlyWithLocalPages() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yomuhon-offline-\(UUID().uuidString).img")
        try Data([1, 2, 3, 4]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let readable = Chapter(
            id: "offline-c1",
            mangaID: "offline-manga",
            number: 1,
            title: nil,
            pages: [Page(id: "offline-p1", index: 0, imageURL: nil, localFileURL: fileURL)],
            isDownloaded: true
        )
        let missingLocalFile = Chapter(
            id: "offline-c2",
            mangaID: "offline-manga",
            number: 2,
            title: nil,
            pages: [Page(id: "offline-p2", index: 0, imageURL: nil, localFileURL: fileURL.appendingPathExtension("missing"))],
            isDownloaded: true
        )

        XCTAssertTrue(ReaderViewModel.hasUsableLocalPages(readable))
        XCTAssertFalse(ReaderViewModel.hasUsableLocalPages(missingLocalFile))
    }

    func testPausedDownloadDoesNotAdvanceProgressAndResumeReusesPartialPage() throws {
        let sourceFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("yomuhon-download-source-\(UUID().uuidString).img")
        try Data(repeating: 7, count: 4096).write(to: sourceFile)
        defer { try? FileManager.default.removeItem(at: sourceFile) }

        let mangaID = "download-pause-\(UUID().uuidString)"
        let chapter = Chapter(
            id: "download-pause-c1",
            mangaID: mangaID,
            number: 1,
            title: "Chapter 1",
            pages: [
                Page(id: "download-pause-p1", index: 0, imageURL: nil, localFileURL: sourceFile)
            ],
            isDownloaded: false
        )
        let manga = Manga(
            id: mangaID,
            sourceID: "download-pause-source",
            title: "Download Pause",
            coverURL: nil,
            synopsis: nil,
            chapters: [chapter]
        )
        let repository = DownloadRepositoryImpl()
        var cancellationChecks = 0
        var pausedProgress: [Double] = []

        XCTAssertThrowsError(
            try repository.downloadChapter(
                chapter,
                from: manga,
                progressHandler: { pausedProgress.append($0) },
                shouldCancel: {
                    cancellationChecks += 1
                    return cancellationChecks >= 3
                }
            )
        ) { error in
            guard case DownloadRepositoryError.cancelled = error else {
                return XCTFail("Expected pause cancellation, got \(error)")
            }
        }
        XCTAssertTrue(pausedProgress.isEmpty)

        // The third cancellation check happens after the atomic page write but
        // before progress publication. Remove the original source page: resume
        // can only finish if it reuses the deterministic partial page on disk.
        try FileManager.default.removeItem(at: sourceFile)
        var resumedProgress: [Double] = []
        let resumed = try repository.downloadChapter(
            chapter,
            from: manga,
            progressHandler: { resumedProgress.append($0) },
            shouldCancel: { false }
        )

        XCTAssertTrue(resumed.isDownloaded)
        XCTAssertEqual(resumedProgress.last, 1)
        XCTAssertNotNil(resumed.pages.first?.localFileURL)
        _ = try repository.deleteDownloadedChapter(resumed, from: manga)
    }

    func testLanguageCandidateRoutingKeepsOnlySameWorkSourcesThatCanServeRequestedLanguage() throws {
        let current = Manga(
            id: "language-en",
            sourceID: "english-source",
            title: "My Hero Academia",
            coverURL: nil,
            synopsis: nil,
            alternativeTitles: ["Boku no Hero Academia"],
            author: "Kohei Horikoshi",
            releaseYear: 2014,
            chapters: []
        )
        let spanish = Manga(
            id: "language-es",
            sourceID: "spanish-source",
            title: "Boku no Hero Academia",
            coverURL: nil,
            synopsis: nil,
            alternativeTitles: ["My Hero Academia"],
            author: "Kohei Horikoshi",
            releaseYear: 2014,
            chapters: [
                Chapter(id: "es-c1", mangaID: "language-es", number: 1, title: nil, pages: [], isDownloaded: false)
            ]
        )
        let unrelated = Manga(
            id: "language-unrelated",
            sourceID: "spanish-source-2",
            title: "My Hero",
            coverURL: nil,
            synopsis: nil,
            author: "Someone Else",
            releaseYear: 2025,
            chapters: []
        )

        let candidates = MangaDetailViewModel.languageCandidates(
            currentManga: current,
            existingCandidates: [],
            searchedCandidates: [spanish, unrelated],
            targetLanguageCode: "es-419",
            canServeLanguage: { language, sourceID in
                language == "es" && sourceID == "spanish-source"
            }
        )

        XCTAssertEqual(candidates.map(\.id), [spanish.id])
    }

    func testSuccessfulDetailLoadCancelsAllScheduledWatchdogs() throws {
        let sourceRepository = DelayedDetailSourceRepository(delay: 0.04)
        let libraryRepository = InMemoryLibraryRepository()
        let manga = Manga(
            id: "watchdog-success",
            sourceID: "mangapill",
            title: "Watchdog Success",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )
        let viewModel = MangaDetailViewModel(
            manga: manga,
            progress: nil,
            getChapterListUseCase: GetChapterListUseCase(repository: sourceRepository),
            downloadChapterUseCase: DownloadChapterUseCase(
                downloadRepository: TestDownloadRepository(),
                libraryRepository: libraryRepository,
                sourceRepository: sourceRepository
            ),
            updateReadingProgressUseCase: UpdateReadingProgressUseCase(repository: libraryRepository),
            sourceRepository: sourceRepository,
            libraryRepository: libraryRepository,
            detailLoadTimeout: 0.5,
            detailSessionTimeout: 0.8
        )
        let finished = expectation(description: "successful detail cancels watchdogs")

        viewModel.loadDetailsIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(viewModel.chapters.count, 1)
            XCTAssertFalse(viewModel.isLoadingDetails)
#if DEBUG
            XCTAssertEqual(viewModel.activeDetailWatchdogCountForTesting, 0)
#endif
            finished.fulfill()
        }

        wait(for: [finished], timeout: 1.0)
    }


    func testReaderProgressFractionMapsToNearestPage() {
        XCTAssertEqual(ReaderViewModel.pageIndex(forProgressFraction: 0, pageCount: 9), 0)
        XCTAssertEqual(ReaderViewModel.pageIndex(forProgressFraction: 0.5, pageCount: 9), 4)
        XCTAssertEqual(ReaderViewModel.pageIndex(forProgressFraction: 1, pageCount: 9), 8)
        XCTAssertEqual(ReaderViewModel.pageIndex(forProgressFraction: -1, pageCount: 9), 0)
        XCTAssertEqual(ReaderViewModel.pageIndex(forProgressFraction: 2, pageCount: 9), 8)
        XCTAssertEqual(ReaderViewModel.pageIndex(forProgressFraction: 0.8, pageCount: 1), 0)
        XCTAssertNil(ReaderViewModel.pageIndex(forProgressFraction: 0.5, pageCount: 0))
    }

    func testReaderJumpToPageClampsToLoadedPages() {
        let manga = Manga(
            id: "pencil-reader",
            sourceID: "probe",
            title: "Pencil Reader",
            coverURL: nil,
            synopsis: nil,
            chapters: []
        )
        let chapter = Chapter(
            id: "pencil-reader-c1",
            mangaID: manga.id,
            number: 1,
            title: "Chapter 1",
            pages: [
                Page(id: "p0", index: 0, imageURL: nil, localFileURL: nil),
                Page(id: "p1", index: 1, imageURL: nil, localFileURL: nil),
                Page(id: "p2", index: 2, imageURL: nil, localFileURL: nil)
            ],
            isDownloaded: false
        )
        let viewModel = ReaderViewModel(
            manga: manga,
            chapter: chapter,
            sourceRepository: TestSourceRepository()
        )

        viewModel.jumpToPage(at: 2)
        XCTAssertEqual(viewModel.currentPageIndex, 2)

        viewModel.jumpToPage(at: 99)
        XCTAssertEqual(viewModel.currentPageIndex, 2)

        viewModel.jumpToPage(at: -5)
        XCTAssertEqual(viewModel.currentPageIndex, 0)
    }

    private func makeSourceStore(operationalSourceIDs: Set<String>) -> SourceSettingsStore {
        let suiteName = "YomuhonTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SourceSettingsStore(userDefaults: defaults)
        var repositories = store.loadRepositories()

        for index in repositories.indices {
            let isOperational = operationalSourceIDs.contains(repositories[index].id)
            repositories[index].isEnabled = isOperational
            repositories[index].installedSources = repositories[index].installedSources.map { source in
                var source = source
                source.healthStatus = isOperational ? .available : .unavailable
                return source
            }
        }

        store.saveRepositories(repositories)
        return store
    }


    func testDeclarativeHybridSourceUsesHTMLForCatalogJSONForChaptersAndHTMLForPages() throws {
        let configJSON = #"""
        {
          "schemaVersion": 1,
          "id": "hybrid_fixture",
          "name": "Hybrid Fixture",
          "version": 1,
          "language": "en",
          "baseURL": "https://www.example.com",
          "engineMode": "html",
          "operationModes": {
            "chapters": "json-api"
          },
          "identity": {
            "preserveQueryItems": ["title_no"]
          },
          "enabledByDefault": false,
          "experimental": true,
          "allowedDomains": ["www.example.com", "m.example.com", "cdn.example.com"],
          "supports": {
            "search": true,
            "popular": false,
            "details": true,
            "chapters": true,
            "pages": true
          },
          "routes": {
            "search": {
              "path": "/en/search",
              "query": {"keyword": "{{query}}"}
            }
          },
          "selectors": {
            "search": {
              "container": ".series li a",
              "title": {"selectors": [".title"], "attrs": ["text"]},
              "url": {"attrs": ["href"], "required": true},
              "cover": {"selectors": ["img"], "attrs": ["src"]}
            },
            "details": {
              "title": {"selectors": ["h1.title"], "attrs": ["text"]},
              "synopsis": {"selectors": ["p.summary"], "attrs": ["text"]}
            },
            "pages": {
              "extractors": [
                {"type": "css", "selector": "div#images img", "attrs": ["data-url", "src"]}
              ]
            }
          },
          "api": {
            "chapters": {
              "request": {
                "method": "GET",
                "baseURL": "https://m.example.com",
                "path": "/api/v1/{{contentType}}/{{titleID}}/episodes",
                "query": {"pageSize": 99999}
              },
              "itemsPath": "result.episodeList",
              "idPath": "viewerLink",
              "numberPath": "episodeNo",
              "titlePath": "episodeTitle",
              "urlPath": "viewerLink",
              "variables": {
                "titleID": {
                  "from": "mangaURL",
                  "regex": "[?&]title_no=([0-9]+)"
                },
                "contentType": {
                  "from": "mangaURL",
                  "regex": "/(canvas)/",
                  "default": "webtoon"
                }
              },
              "sort": "numberAscending"
            }
          }
        }
        """#

        let config = try JSONDecoder().decode(
            DeclarativeSourceConfig.self,
            from: Data(configJSON.utf8)
        )
        XCTAssertTrue(DeclarativeSourceConfigurationValidator.validateStandalone(config))
        var requestedURLs: [URL] = []
        let source = DeclarativeSourceRuntime(config: config) { request in
            let url = try XCTUnwrap(request.url)
            requestedURLs.append(url)

            if url.host == "www.example.com", url.path == "/en/search" {
                return Data(#"""
                <ul class="series">
                  <li><a href="/en/canvas/demo/list?title_no=123"><span class="title">Demo</span><img src="https://cdn.example.com/cover.jpg"></a></li>
                </ul>
                """#.utf8)
            }

            if url.host == "www.example.com", url.path == "/en/canvas/demo/list" {
                return Data(#"""
                <h1 class="title">Demo</h1>
                <p class="summary">Hybrid source fixture.</p>
                """#.utf8)
            }

            if url.host == "m.example.com", url.path == "/api/v1/canvas/123/episodes" {
                return Data(#"""
                {
                  "result": {
                    "episodeList": [
                      {
                        "episodeNo": 2,
                        "episodeTitle": "Episode 2",
                        "viewerLink": "/en/canvas/demo/episode-2/viewer?title_no=123&episode_no=2"
                      },
                      {
                        "episodeNo": 1,
                        "episodeTitle": "Episode 1",
                        "viewerLink": "/en/canvas/demo/episode-1/viewer?title_no=123&episode_no=1"
                      }
                    ]
                  }
                }
                """#.utf8)
            }

            if url.host == "www.example.com", url.path.contains("/viewer") {
                return Data(#"""
                <div id="images">
                  <img data-url="https://cdn.example.com/page-1.jpg">
                  <img data-url="https://cdn.example.com/page-2.jpg">
                </div>
                """#.utf8)
            }

            XCTFail("Unexpected request: \(url.absoluteString)")
            return Data()
        }

        let manga = try XCTUnwrap(source.searchManga(query: "demo").first)
        let detailed = try source.fetchDetails(for: manga)
        let chapter = try XCTUnwrap(detailed.chapters.first)
        let pages = try source.fetchPages(for: chapter, manga: detailed)

        XCTAssertEqual(detailed.title, "Demo")
        XCTAssertEqual(detailed.chapters.map(\.number), [1, 2])
        XCTAssertEqual(chapter.declarativeSourceURL?.host, "www.example.com")
        XCTAssertEqual(chapter.declarativeSourceURL?.query, "title_no=123&episode_no=1")
        XCTAssertEqual(pages.count, 2)
        XCTAssertTrue(requestedURLs.contains { $0.host == "m.example.com" && $0.path == "/api/v1/canvas/123/episodes" })
    }

}

private final class InMemoryLibraryRepository: LibraryRepository {
    private var mangas: [String: Manga] = [:]
    private var progress: [String: ReadingProgress] = [:]
    private let lock = NSLock()

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

private struct TestSourceRepository: SourceRepository {
    func availableSources() -> [Source] {
        []
    }

    func popularManga() throws -> [Manga] {
        []
    }

    func searchManga(query: String) throws -> [Manga] {
        []
    }

    func fetchDetails(for manga: Manga) throws -> Manga {
        manga
    }

    func fetchChapters(for manga: Manga) throws -> [Chapter] {
        manga.chapters
    }

    func fetchPages(for chapter: Chapter, manga: Manga) throws -> [Page] {
        chapter.pages
    }
}

private struct TestDownloadRepository: DownloadRepository {
    func downloadChapter(
        _ chapter: Chapter,
        from manga: Manga,
        progressHandler: ((Double) -> Void)?,
        shouldCancel: (() -> Bool)?
    ) throws -> Chapter {
        var downloadedChapter = chapter
        downloadedChapter.isDownloaded = true
        progressHandler?(1)
        return downloadedChapter
    }

    func deleteDownloadedChapter(_ chapter: Chapter, from manga: Manga) throws -> Manga {
        var updated = manga
        if let index = updated.chapters.firstIndex(where: { $0.id == chapter.id }) {
            updated.chapters[index].isDownloaded = false
        }
        return updated
    }

    func deleteDownloadedManga(_ manga: Manga) throws -> Manga {
        var updated = manga
        for index in updated.chapters.indices {
            updated.chapters[index].isDownloaded = false
        }
        return updated
    }
}


private final class CancellableDiscoveryProbeSource: Source {
    let id = "cancellable_discovery_probe"
    let name = "Cancellable Discovery Probe"
    var supportsPopularDiscovery: Bool { true }

    private let condition = NSCondition()
    private var started = false
    private var observedCancellation = false

    var didObserveCancellation: Bool {
        condition.lock()
        defer { condition.unlock() }
        return observedCancellation
    }

    func waitUntilStarted(timeout: TimeInterval) -> Bool {
        condition.lock()
        defer { condition.unlock() }

        let deadline = Date().addingTimeInterval(timeout)
        while !started && Date() < deadline {
            condition.wait(until: deadline)
        }
        return started
    }

    func popularManga() throws -> [Manga] {
        condition.lock()
        started = true
        condition.broadcast()
        condition.unlock()

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if HTTPRequestCancellationContext.currentToken?.isCancelled == true {
                condition.lock()
                observedCancellation = true
                condition.unlock()
                throw HTTPClientError.cancelled
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return []
    }

    func searchManga(query: String) throws -> [Manga] { [] }
    func fetchChapters(for manga: Manga) throws -> [Chapter] { [] }
}

private struct PopularDiscoveryProbeSource: Source {
    let id: String
    let shouldFail: Bool
    var name: String { id }
    var supportsPopularDiscovery: Bool { true }

    func popularManga() throws -> [Manga] {
        if shouldFail {
            throw ProbeError.forcedFailure
        }

        return [
            Manga(
                id: "\(id)-popular",
                sourceID: id,
                title: "Popular Probe",
                coverURL: URL(string: "https://example.com/cover.jpg"),
                synopsis: nil,
                chapters: []
            )
        ]
    }

    func searchManga(query: String) throws -> [Manga] { [] }
    func fetchChapters(for manga: Manga) throws -> [Chapter] { [] }

}

private enum ProbeError: Error {
    case parallelSearchDidNotStart
    case forcedFailure
}

private final class CallCounter {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private final class ParallelSearchGate {
    private let condition = NSCondition()
    private let expectedCount: Int
    private var arrivedCount = 0
    private(set) var didReleaseAllSources = false

    init(expectedCount: Int) {
        self.expectedCount = expectedCount
    }

    func arriveAndWait() -> Bool {
        condition.lock()
        arrivedCount += 1

        if arrivedCount >= expectedCount {
            didReleaseAllSources = true
            condition.broadcast()
            condition.unlock()
            return true
        }

        let deadline = Date().addingTimeInterval(0.8)
        while arrivedCount < expectedCount && Date() < deadline {
            condition.wait(until: deadline)
        }

        let succeeded = arrivedCount >= expectedCount
        if succeeded { didReleaseAllSources = true }
        condition.unlock()
        return succeeded
    }
}

private final class ContentCacheCounter {
    private let lock = NSLock()
    private var details = 0
    private var pages = 0

    var detailCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return details
    }

    var pageCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pages
    }

    func incrementDetails() {
        lock.lock()
        details += 1
        lock.unlock()
    }

    func incrementPages() {
        lock.lock()
        pages += 1
        lock.unlock()
    }
}

private struct ContentCacheProbeSource: Source {
    let id = "content_cache_probe"
    let name = "Content Cache Probe"
    let counter: ContentCacheCounter

    func searchManga(query: String) throws -> [Manga] { [] }

    func fetchDetails(for manga: Manga) throws -> Manga {
        counter.incrementDetails()
        var detailed = manga
        detailed.chapters = [
            Chapter(
                id: "content-cache-chapter",
                mangaID: manga.id,
                number: 1,
                title: "Chapter 1",
                pages: [],
                isDownloaded: false
            )
        ]
        return detailed
    }

    func fetchChapters(for manga: Manga) throws -> [Chapter] {
        try fetchDetails(for: manga).chapters
    }

    func fetchPages(for chapter: Chapter, manga: Manga) throws -> [Page] {
        counter.incrementPages()
        return [
            Page(id: "page-1", index: 0, imageURL: URL(string: "https://example.com/1.jpg"), localFileURL: nil),
            Page(id: "page-2", index: 1, imageURL: URL(string: "https://example.com/2.jpg"), localFileURL: nil)
        ]
    }
}

private struct ProbeSource: Source {
    let id: String
    var name: String { id }
    var gate: ParallelSearchGate?
    var counter: CallCounter?

    init(id: String, gate: ParallelSearchGate? = nil, counter: CallCounter? = nil) {
        self.id = id
        self.gate = gate
        self.counter = counter
    }

    func searchManga(query: String) throws -> [Manga] {
        counter?.increment()

        if let gate, !gate.arriveAndWait() {
            throw ProbeError.parallelSearchDidNotStart
        }

        return [
            Manga(
                id: "\(id)-\(query)",
                sourceID: id,
                title: "One Piece",
                coverURL: nil,
                synopsis: nil,
                chapters: []
            )
        ]
    }

    func fetchChapters(for manga: Manga) throws -> [Chapter] {
        manga.chapters
    }
}

private struct CancellableProbeSource: Source {
    let id = "mangadex"
    let name = "MangaDex"

    func searchManga(query: String) throws -> [Manga] {
        let deadline = Date().addingTimeInterval(3)

        while Date() < deadline {
            if HTTPRequestCancellationContext.currentToken?.isCancelled == true {
                throw HTTPClientError.cancelled
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        return []
    }

    func fetchChapters(for manga: Manga) throws -> [Chapter] {
        []
    }
}

private final class FailingDetailSourceRepository: SourceRepository {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func availableSources() -> [Source] { [] }
    func popularManga() throws -> [Manga] { [] }
    func searchManga(query: String) throws -> [Manga] { [] }

    func fetchDetails(for manga: Manga) throws -> Manga {
        lock.lock()
        counts[manga.sourceID, default: 0] += 1
        lock.unlock()
        throw ProbeError.forcedFailure
    }

    func fetchChapters(for manga: Manga) throws -> [Chapter] { [] }
    func fetchPages(for chapter: Chapter, manga: Manga) throws -> [Page] { [] }

    func fetchCount(for sourceID: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[sourceID, default: 0]
    }
}

private final class DelayedDetailSourceRepository: SourceRepository {
    private let lock = NSLock()
    private let delay: TimeInterval
    private var count = 0

    init(delay: TimeInterval) {
        self.delay = delay
    }

    var fetchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func availableSources() -> [Source] { [] }
    func popularManga() throws -> [Manga] { [] }
    func searchManga(query: String) throws -> [Manga] { [] }

    func fetchDetails(for manga: Manga) throws -> Manga {
        lock.lock()
        count += 1
        lock.unlock()

        let deadline = Date().addingTimeInterval(delay)
        while Date() < deadline {
            if HTTPRequestCancellationContext.currentToken?.isCancelled == true {
                throw HTTPClientError.cancelled
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        var detailed = manga
        detailed.chapters = [
            Chapter(
                id: "chapter-1",
                mangaID: manga.id,
                number: 1,
                title: "Chapter 1",
                pages: [],
                isDownloaded: false
            )
        ]
        return detailed
    }

    func fetchChapters(for manga: Manga) throws -> [Chapter] { manga.chapters }
    func fetchPages(for chapter: Chapter, manga: Manga) throws -> [Page] { chapter.pages }
}

private struct ReadableDetailProbeSource: Source {
    let id = "detail_probe"
    let name = "Detail Probe"

    func searchManga(query: String) throws -> [Manga] { [] }

    func fetchDetails(for manga: Manga) throws -> Manga {
        var detailed = manga
        detailed.chapters = [
            Chapter(
                id: "probe-chapter",
                mangaID: manga.id,
                number: 1,
                title: "Chapter 1",
                pages: [],
                isDownloaded: false
            )
        ]
        return detailed
    }

    func fetchChapters(for manga: Manga) throws -> [Chapter] { manga.chapters }
}

private final class SlowMetadataProbeSource: Source {
    let id = "slow_metadata"
    let name = "Slow Metadata"
    private let delay: TimeInterval
    private let lock = NSLock()
    private var count = 0

    init(delay: TimeInterval) {
        self.delay = delay
    }

    var searchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func searchManga(query: String) throws -> [Manga] {
        lock.lock()
        count += 1
        lock.unlock()
        Thread.sleep(forTimeInterval: delay)
        return []
    }

    func fetchChapters(for manga: Manga) throws -> [Chapter] { [] }

}

