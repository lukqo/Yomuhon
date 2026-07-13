//
//  ReaderViewModel.swift
//  Yomuhon
//

import Combine
import Foundation
import SwiftUI
#if canImport(Network)
import Network
#endif

final class ReaderViewModel: ObservableObject {
    private(set) var manga: Manga
    @Published private(set) var chapter: Chapter

    @Published var currentPageIndex: Int {
        didSet {
            updateProgress()
        }
    }
    @Published var showsControls = true
    @Published var readingMode: ReadingMode = .paged
    @Published var fitMode: ReaderFitMode = .fitPage
    @Published var isDarkHUDEnabled = true
    @Published private(set) var chapterTransitionMessage: String?
    @Published private(set) var isAtEndOfSeries = false
    @Published private(set) var pages: [Page]
    @Published private(set) var prefetchedNextChapterPreviewPages: [Page] = []
    @Published private(set) var isLoadingPages = false
    @Published private(set) var errorMessage: String?

    private let updateReadingProgressUseCase: UpdateReadingProgressUseCase?
    private let sourceRepository: SourceRepository
    private var pageLoadGeneration = 0
    private var prefetchedChapterPages: [String: [Page]] = [:]
    private var chapterPreloadInFlight = Set<String>()
    private var automaticChapterAdvanceWorkItem: DispatchWorkItem?

    init(
        manga: Manga,
        chapter: Chapter,
        initialPageIndex: Int = 0,
        updateReadingProgressUseCase: UpdateReadingProgressUseCase? = nil,
        sourceRepository: SourceRepository
    ) {
        self.manga = manga
        self.chapter = chapter
        self.pages = chapter.pages
        // Keep the requested saved page even when pages are not loaded yet.
        // Once remote pages arrive, loadPagesIfNeeded clamps this value to the real page count.
        self.currentPageIndex = max(initialPageIndex, 0)
        self.updateReadingProgressUseCase = updateReadingProgressUseCase
        self.sourceRepository = sourceRepository
        self.readingMode = Self.storedReadingMode()
        self.fitMode = Self.storedFitMode()
        self.isDarkHUDEnabled = Self.storedDarkHUD()
    }

    var title: String {
        manga.title
    }

    var chapterTitle: String {
        if chapter.number > 0 {
            return String.localizedStringWithFormat(
                NSLocalizedString("chapter.displayTitle", comment: ""),
                chapter.formattedNumber
            )
        }

        return chapter.cleanTitleOrDisplayTitle
    }

    var currentPage: Page? {
        guard pages.indices.contains(currentPageIndex) else {
            return nil
        }

        return pages[currentPageIndex]
    }

    static func pageIndex(forProgressFraction fraction: Double, pageCount: Int) -> Int? {
        guard pageCount > 0 else { return nil }
        guard pageCount > 1 else { return 0 }

        let clampedFraction = min(max(fraction, 0), 1)
        return Int((clampedFraction * Double(pageCount - 1)).rounded())
    }

    func jumpToPage(at index: Int) {
        guard !pages.isEmpty else { return }
        currentPageIndex = min(max(index, 0), pages.count - 1)
    }

    var pageRefererURL: URL? {
        chapter.declarativeSourceURL ?? manga.declarativeSourceURL
    }

    var prefetchedNextChapterRefererURL: URL? {
        nextChapter?.declarativeSourceURL ?? manga.declarativeSourceURL
    }

    func pagesToPrefetch(radius: Int = 2) -> [Page] {
        Self.prefetchIndexes(
            currentIndex: currentPageIndex,
            pageCount: pages.count,
            radius: radius
        )
        .compactMap { index in
            pages.indices.contains(index) ? pages[index] : nil
        }
    }

    static func prefetchIndexes(
        currentIndex: Int,
        pageCount: Int,
        radius: Int = 2
    ) -> [Int] {
        guard pageCount > 0 else { return [] }

        let safeRadius = max(radius, 0)
        let safeCurrentIndex = min(max(currentIndex, 0), pageCount - 1)
        let lowerBound = max(0, safeCurrentIndex - safeRadius)
        let upperBound = min(pageCount - 1, safeCurrentIndex + safeRadius)

        return Array(lowerBound...upperBound)
            .sorted { lhs, rhs in
                let lhsDistance = abs(lhs - safeCurrentIndex)
                let rhsDistance = abs(rhs - safeCurrentIndex)
                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }
                return lhs < rhs
            }
    }

    var pageLabel: String {
        guard !pages.isEmpty else {
            return String(localized: "reader.noPages")
        }

        return String.localizedStringWithFormat(
            NSLocalizedString("reader.pageProgressFormat", comment: ""),
            currentPageIndex + 1,
            pages.count
        )
    }

    var progress: Double {
        guard pages.count > 1 else {
            return pages.isEmpty ? 0 : 1
        }

        return Double(currentPageIndex) / Double(pages.count - 1)
    }

    var canGoBackward: Bool {
        currentPageIndex > 0 || previousChapter != nil
    }

    var canGoForward: Bool {
        currentPageIndex < pages.count - 1 || nextChapter != nil
    }

    func goBackward(pageStep: Int = 1) {
        let step = max(pageStep, 1)
        if currentPageIndex > 0 {
            currentPageIndex = max(0, currentPageIndex - step)
            return
        }

        guard let previousChapter else {
            return
        }

        guard canOpenChapterInCurrentConnectivity(previousChapter) else {
            showOfflineChapterUnavailable()
            return
        }

        openChapter(previousChapter, preferredPageIndex: max(previousChapter.pages.count - step, 0))
    }

    func goForward(pageStep: Int = 1) {
        let step = max(pageStep, 1)
        if currentPageIndex < pages.count - 1 {
            currentPageIndex = min(currentPageIndex + step, pages.count - 1)
            return
        }

        guard let nextChapter else {
            showEndOfSeries()
            return
        }

        guard canOpenChapterInCurrentConnectivity(nextChapter) else {
            showOfflineChapterUnavailable()
            return
        }

        openChapter(nextChapter, preferredPageIndex: 0)
    }

    func setVisiblePage(_ page: Page) {
        guard let index = pages.firstIndex(where: { $0.id == page.id }),
              currentPageIndex != index
        else {
            return
        }

        currentPageIndex = index
    }

    private var currentChapterIndex: Int? {
        manga.chapters.firstIndex { $0.id == chapter.id }
    }

    private var previousChapter: Chapter? {
        guard let currentChapterIndex, currentChapterIndex > 0 else {
            return nil
        }

        return manga.chapters[currentChapterIndex - 1]
    }

    private var nextChapter: Chapter? {
        guard let currentChapterIndex,
              manga.chapters.indices.contains(currentChapterIndex + 1)
        else {
            return nil
        }

        return manga.chapters[currentChapterIndex + 1]
    }

    private func openChapter(_ newChapter: Chapter, preferredPageIndex: Int) {
        automaticChapterAdvanceWorkItem?.cancel()
        manga.updateChapter(chapter)

        var resolvedChapter = newChapter
        if resolvedChapter.pages.isEmpty,
           let prefetchedPages = prefetchedChapterPages.removeValue(forKey: resolvedChapter.id) {
            resolvedChapter.pages = prefetchedPages
        }

        chapter = resolvedChapter
        pages = resolvedChapter.pages
        prefetchedNextChapterPreviewPages = []
        currentPageIndex = min(max(preferredPageIndex, 0), max(pages.count - 1, 0))
        errorMessage = nil
        isAtEndOfSeries = false
        pageLoadGeneration += 1

        updateProgress()
        showChapterTransitionMessage(for: resolvedChapter)

        if pages.isEmpty {
            loadPagesIfNeeded()
        } else {
            preloadNextChapterIfNeeded()
        }
    }

    func toggleControls() {
        showsControls.toggle()
    }

    func handleReadingModeChange(_ mode: ReadingMode) {
        readingMode = mode
        showsControls = true
        Self.storeReadingMode(mode)

        if mode == .webtoon {
            currentPageIndex = min(currentPageIndex, max(pages.count - 1, 0))
        }
    }

    func setFitMode(_ mode: ReaderFitMode) {
        fitMode = mode
        Self.storeFitMode(mode)
        showsControls = true
    }

    func toggleDarkHUD() {
        isDarkHUDEnabled.toggle()
        Self.storeDarkHUD(isDarkHUDEnabled)
        showsControls = true
    }

    func handleReaderPositionChanged() {
        preloadNextChapterIfNeeded()

        guard readingMode == .webtoon,
              !pages.isEmpty,
              currentPageIndex == pages.count - 1
        else {
            automaticChapterAdvanceWorkItem?.cancel()
            automaticChapterAdvanceWorkItem = nil
            return
        }

        scheduleAutomaticChapterAdvance()
    }

    func preloadNextChapterIfNeeded() {
        guard !pages.isEmpty, progress >= 0.80, let nextChapter else {
            return
        }

        if !nextChapter.pages.isEmpty {
            prefetchedNextChapterPreviewPages = Array(nextChapter.pages.prefix(3))
            return
        }

        guard canOpenChapterInCurrentConnectivity(nextChapter),
              prefetchedChapterPages[nextChapter.id] == nil,
              chapterPreloadInFlight.insert(nextChapter.id).inserted
        else {
            return
        }

        let repository = sourceRepository
        let mangaSnapshot = manga
        let chapterToPrefetch = nextChapter

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result {
                try repository.fetchPages(for: chapterToPrefetch, manga: mangaSnapshot)
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.chapterPreloadInFlight.remove(chapterToPrefetch.id)
                guard case .success(let pages) = result, !pages.isEmpty else {
                    return
                }

                self.prefetchedChapterPages[chapterToPrefetch.id] = pages
                if self.nextChapter?.id == chapterToPrefetch.id {
                    self.prefetchedNextChapterPreviewPages = Array(pages.prefix(3))
                    SourceDebugTrace.log(
                        "Reader",
                        "NEXT_PRELOAD chapter=\(chapterToPrefetch.id) pages=\(pages.count) preview=\(min(pages.count, 3))"
                    )
                }
            }
        }
    }

    private func scheduleAutomaticChapterAdvance() {
        automaticChapterAdvanceWorkItem?.cancel()

        guard let nextChapter else {
            showEndOfSeries()
            return
        }

        let chapterID = chapter.id
        let nextChapterID = nextChapter.id
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.readingMode == .webtoon,
                  self.chapter.id == chapterID,
                  self.currentPageIndex == self.pages.count - 1,
                  self.nextChapter?.id == nextChapterID
            else {
                return
            }

            guard self.canOpenChapterInCurrentConnectivity(nextChapter) else {
                self.showOfflineChapterUnavailable()
                return
            }

            self.openChapter(nextChapter, preferredPageIndex: 0)
        }

        automaticChapterAdvanceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    private func canOpenChapterInCurrentConnectivity(_ chapter: Chapter) -> Bool {
        if Self.hasUsableLocalPages(chapter) {
            return true
        }

        return ReaderConnectivityMonitor.shared.isNetworkAvailable
    }

    static func hasUsableLocalPages(_ chapter: Chapter) -> Bool {
        guard chapter.isDownloaded, !chapter.pages.isEmpty else {
            return false
        }

        return chapter.pages.allSatisfy { page in
            guard let localFileURL = page.localFileURL else {
                return false
            }
            return FileManager.default.fileExists(atPath: localFileURL.path)
        }
    }

    private func showOfflineChapterUnavailable() {
        automaticChapterAdvanceWorkItem?.cancel()
        automaticChapterAdvanceWorkItem = nil
        isAtEndOfSeries = false
        chapterTransitionMessage = String(localized: "reader.nextChapter.offlineUnavailable")

        let chapterID = chapter.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            guard let self, self.chapter.id == chapterID else { return }
            if self.chapterTransitionMessage == String(localized: "reader.nextChapter.offlineUnavailable") {
                self.chapterTransitionMessage = nil
            }
        }
    }

    private func showEndOfSeries() {
        guard !isAtEndOfSeries else { return }
        isAtEndOfSeries = true
        chapterTransitionMessage = String(localized: "reader.endOfSeries")

        let chapterID = chapter.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self, self.chapter.id == chapterID, self.isAtEndOfSeries else {
                return
            }
            self.chapterTransitionMessage = nil
        }
    }

    func retryLoadingPages() {
        pageLoadGeneration += 1
        pages = []
        chapter.pages = []
        errorMessage = nil
        isLoadingPages = false
        loadPagesIfNeeded()
    }

    func markOpened() {
        updateProgress()
    }

    func flushProgress() {
        updateProgress()
    }

    func loadPagesIfNeeded() {
        guard pages.isEmpty, !isLoadingPages else {
            return
        }

        isLoadingPages = true
        errorMessage = nil
        pageLoadGeneration += 1

        let sourceRepository = sourceRepository
        let chapter = chapter
        let manga = manga
        let generation = pageLoadGeneration

        SourceDebugTrace.log(
            "Reader",
            "loadPages START source=\(manga.sourceID) manga=\(manga.id) chapter=\(chapter.id) number=\(chapter.number) chapterURL=\(chapter.declarativeSourceURL?.absoluteString ?? "nil") generation=\(generation)"
        )

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try sourceRepository.fetchPages(for: chapter, manga: manga)
            }

            switch result {
            case .success(let loadedPages):
                SourceDebugTrace.log(
                    "Reader",
                    "loadPages RESULT source=\(manga.sourceID) manga=\(manga.id) chapter=\(chapter.id) count=\(loadedPages.count) generation=\(generation)"
                )
            case .failure(let error):
                SourceDebugTrace.log(
                    "Reader",
                    "loadPages FAILURE source=\(manga.sourceID) manga=\(manga.id) chapter=\(chapter.id) chapterURL=\(chapter.declarativeSourceURL?.absoluteString ?? "nil") error=\(String(describing: error)) generation=\(generation)"
                )
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.pageLoadGeneration else {
                    return
                }

                self.isLoadingPages = false

                switch result {
                case .success(let pages):
                    guard !pages.isEmpty else {
                        self.pages = []
                        self.errorMessage = String(localized: "reader.pages.emptyFromSource")
                        return
                    }

                    self.pages = pages
                    self.chapter.pages = pages
                    self.manga.updateChapter(self.chapter)
                    self.currentPageIndex = min(self.currentPageIndex, max(pages.count - 1, 0))
                    self.updateProgress()
                    self.preloadNextChapterIfNeeded()
                case .failure(let error):
                    self.errorMessage = String(localized: "reader.pages.error")
                    SourceDebugTrace.log(
                        "Reader",
                        "loadPages UI_ERROR source=\(manga.sourceID) manga=\(manga.id) chapter=\(chapter.id) error=\(String(describing: error))"
                    )
                }
            }
        }
    }

    private static let darkHUDKey = "reader.darkHUD.global"

    private static func storedReadingMode() -> ReadingMode {
        let rawValue = UserDefaults.standard.string(forKey: ReaderPreferenceKeys.defaultReadingMode)
        return rawValue.flatMap(ReadingMode.init(rawValue:)) ?? .paged
    }

    private static func storeReadingMode(_ mode: ReadingMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: ReaderPreferenceKeys.defaultReadingMode)
    }

    private static func storedFitMode() -> ReaderFitMode {
        let rawValue = UserDefaults.standard.string(forKey: ReaderPreferenceKeys.defaultFitMode)
        return rawValue.flatMap(ReaderFitMode.init(rawValue:)) ?? .fitPage
    }

    private static func storeFitMode(_ mode: ReaderFitMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: ReaderPreferenceKeys.defaultFitMode)
    }

    private static func storedDarkHUD() -> Bool {
        guard UserDefaults.standard.object(forKey: darkHUDKey) != nil else {
            return true
        }

        return UserDefaults.standard.bool(forKey: darkHUDKey)
    }

    private static func storeDarkHUD(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: darkHUDKey)
    }

    private func showChapterTransitionMessage(for chapter: Chapter) {
        let title: String
        if chapter.number > 0 {
            title = String.localizedStringWithFormat(
                NSLocalizedString("reader.chapterChanged.format", comment: ""),
                chapter.formattedNumber
            )
        } else {
            title = chapter.cleanTitleOrDisplayTitle
        }

        chapterTransitionMessage = title

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) { [weak self] in
            guard self?.chapter.id == chapter.id else {
                return
            }

            self?.chapterTransitionMessage = nil
        }
    }

    private func updateProgress() {
        updateReadingProgressUseCase?.execute(
            manga: manga,
            chapter: chapter,
            pageIndex: currentPageIndex
        )
    }
}

#if canImport(Network)
private final class ReaderConnectivityMonitor {
    static let shared = ReaderConnectivityMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.yomuhon.reader-connectivity")
    private let lock = NSLock()
    private var networkAvailable = true

    var isNetworkAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return networkAvailable
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.networkAvailable = path.status == .satisfied
            self.lock.unlock()
            SourceDebugTrace.log("Reader", "NETWORK available=\(path.status == .satisfied)")
        }
        monitor.start(queue: queue)
    }
}
#else
private final class ReaderConnectivityMonitor {
    static let shared = ReaderConnectivityMonitor()
    let isNetworkAvailable = true
}
#endif

enum ReaderPreferenceKeys {
    static let defaultReadingMode = "reader.default.mode"
    static let defaultFitMode = "reader.default.fitMode"
    static let imageCacheMaximumMegabytes = "reader.imageCache.maximumMegabytes"
}

enum ReaderImageCacheSize: Int, CaseIterable, Identifiable {
    case compact = 512
    case standard = 1024
    case large = 2048

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .compact:
            return String(localized: "settings.cache.size.512")
        case .standard:
            return String(localized: "settings.cache.size.1024")
        case .large:
            return String(localized: "settings.cache.size.2048")
        }
    }
}

enum ReadingMode: String, CaseIterable, Identifiable {
    case paged
    case webtoon

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .paged:
            return String(localized: "reader.mode.paged")
        case .webtoon:
            return String(localized: "reader.mode.webtoon")
        }
    }
}


private extension Manga {
    mutating func updateChapter(_ chapter: Chapter) {
        guard let index = chapters.firstIndex(where: { $0.id == chapter.id }) else {
            return
        }

        chapters[index] = chapter
    }
}


enum ReaderFitMode: String, CaseIterable, Identifiable {
    case fitPage
    case fitWidth
    case fitHeight

    var id: String {
        rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .fitPage:
            return "reader.fit.page"
        case .fitWidth:
            return "reader.fit.width"
        case .fitHeight:
            return "reader.fit.height"
        }
    }

    var systemImage: String {
        switch self {
        case .fitPage:
            return "arrow.up.left.and.arrow.down.right"
        case .fitWidth:
            return "arrow.left.and.right"
        case .fitHeight:
            return "arrow.up.and.down"
        }
    }
}
