//
//  MangaDetailViewModel.swift
//  Yomuhon
//

import Combine
import Foundation

struct MangaSourceOption: Identifiable, Equatable {
    let manga: Manga

    var id: String {
        manga.sourceID
    }

    var title: String {
        sourceDisplayName(for: manga.sourceID)
    }

    var chapterCount: Int {
        manga.chapters.count
    }

    var language: String {
        NativeSourceCatalog.language(for: manga.sourceID).uppercased()
    }

    var isReadable: Bool {
        NativeSourceCatalog.supportsReading(sourceID: manga.sourceID)
    }
}


struct MangaLanguageOption: Identifiable, Equatable {
    let code: String

    var id: String { code }

    var title: String {
        code.yomuhonLanguageDisplayName
    }

    var shortTitle: String {
        code.uppercased()
    }
}



enum SourceAvailabilityState: Equatable {
    case selected
    case ready
    case loading
    case empty
    case unavailable

    var titleKey: String {
        switch self {
        case .selected:
            return "source.state.selected"
        case .ready:
            return "source.state.ready"
        case .loading:
            return "source.state.loading"
        case .empty:
            return "source.state.empty"
        case .unavailable:
            return "source.state.unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .selected:
            return "checkmark.circle.fill"
        case .ready:
            return "bolt.circle"
        case .loading:
            return "clock"
        case .empty:
            return "tray"
        case .unavailable:
            return "exclamationmark.triangle"
        }
    }
}

struct MangaSourceAvailability: Identifiable, Equatable {
    let option: MangaSourceOption
    let state: SourceAvailabilityState
    let hasMostChapters: Bool
    let isRecommended: Bool

    var id: String { option.id }
}


final class MangaDetailViewModel: ObservableObject {
    @Published private(set) var manga: Manga
    @Published private(set) var selectedSourceID: String
    @Published private(set) var isLoadingDetails = false
    @Published private(set) var isDownloading = false
    @Published private(set) var isDownloadingManga = false
    @Published private(set) var mangaDownloadProgress: Double = 0
    @Published private(set) var downloadStatusMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedLanguagePreference: SourceLanguagePreference
    @Published private(set) var selectedExactLanguageCode: String?
    @Published private(set) var selectedReadingLanguageCode: String?
    @Published private(set) var isCheckingLanguage = false
    @Published private(set) var languageStatusMessage: String?
    @Published private(set) var isSavedInLibrary: Bool

    private(set) var availableMangas: [Manga]
    @Published private(set) var progress: ReadingProgress?
    private let getChapterListUseCase: GetChapterListUseCase
    private let downloadChapterUseCase: DownloadChapterUseCase
    private let updateReadingProgressUseCase: UpdateReadingProgressUseCase
    private let sourceRepository: SourceRepository
    private let libraryRepository: LibraryRepository
    private var loadedSourceIDs = Set<String>()
    private var loadingSourceIDs = Set<String>()
    private var detailLoadGenerationBySourceID: [String: Int] = [:]
    private var detailLoadTokens: [String: RequestCancellationToken] = [:]
    private var detailSessionWatchdog: DispatchWorkItem?
    private var detailRequestWatchdogs: [String: DispatchWorkItem] = [:]
    private var failedSourceIDs = Set<String>()
    private var emptyChapterRepairAttemptedSourceIDs = Set<String>()
    private var detailSessionGeneration = 0
    private var detailSessionDeadline: Date?
    private var detailSessionAttemptedSourceIDs = Set<String>()
    private var initialDetailLoadRequestedSourceIDs = Set<String>()
    private let detailLoadTimeout: TimeInterval
    private let detailSessionTimeout: TimeInterval
    private let maximumAutomaticSourceAttempts: Int
    private var cancellables = Set<AnyCancellable>()
    private var bulkDownloadIDs = Set<String>()
    private var languageSearchGeneration = 0
    private var languageSearchToken: RequestCancellationToken?

    init(
        manga: Manga,
        alternativeMangas: [Manga] = [],
        progress: ReadingProgress?,
        getChapterListUseCase: GetChapterListUseCase,
        downloadChapterUseCase: DownloadChapterUseCase,
        updateReadingProgressUseCase: UpdateReadingProgressUseCase,
        sourceRepository: SourceRepository,
        libraryRepository: LibraryRepository,
        detailLoadTimeout: TimeInterval = 12,
        detailSessionTimeout: TimeInterval = 24,
        maximumAutomaticSourceAttempts: Int = 2
    ) {
        self.manga = manga
        self.selectedSourceID = manga.sourceID
        self.availableMangas = Self.uniqueMangas(primary: manga, alternatives: alternativeMangas)
        self.selectedLanguagePreference = SourceLanguagePreferenceStore.shared.preference(for: manga.sourceID)
        self.selectedExactLanguageCode = SourceLanguagePreferenceStore.shared.exactLanguageOverride(mangaID: manga.id, sourceID: manga.sourceID)
        self.selectedReadingLanguageCode = Self.initialReadingLanguageCode(for: manga)
        self.isSavedInLibrary = LibraryMembershipStore.shared.contains(manga.id)
        self.progress = progress
        self.getChapterListUseCase = getChapterListUseCase
        self.downloadChapterUseCase = downloadChapterUseCase
        self.updateReadingProgressUseCase = updateReadingProgressUseCase
        self.sourceRepository = sourceRepository
        self.libraryRepository = libraryRepository
        self.detailLoadTimeout = max(0.1, detailLoadTimeout)
        self.detailSessionTimeout = max(self.detailLoadTimeout, detailSessionTimeout)
        self.maximumAutomaticSourceAttempts = max(1, maximumAutomaticSourceAttempts)

        let progressSourceID = progress.flatMap { progress in
            self.availableMangas.contains { $0.sourceID == progress.sourceID }
                ? progress.sourceID
                : nil
        }

        let initialSourceID = progressSourceID
            ?? self.recommendedSourceID
            ?? self.highestPriorityReadableSourceID
            ?? manga.sourceID

        if let initialManga = self.availableMangas.first(where: { $0.sourceID == initialSourceID }) {
            self.manga = initialManga
            self.selectedSourceID = initialSourceID
            self.selectedLanguagePreference = SourceLanguagePreferenceStore.shared.preference(for: initialSourceID)
            self.selectedExactLanguageCode = SourceLanguagePreferenceStore.shared.exactLanguageOverride(
                mangaID: initialManga.id,
                sourceID: initialSourceID
            )
            self.selectedReadingLanguageCode = Self.initialReadingLanguageCode(for: initialManga)
            self.isSavedInLibrary = LibraryMembershipStore.shared.contains(initialManga.id)
        }

        observeDownloadCenter()
    }

    deinit {
        detailSessionWatchdog?.cancel()
        detailRequestWatchdogs.values.forEach { $0.cancel() }
        detailLoadTokens.values.forEach { $0.cancel() }
        languageSearchToken?.cancel()
    }

#if DEBUG
    var activeDetailWatchdogCountForTesting: Int {
        (detailSessionWatchdog == nil ? 0 : 1) + detailRequestWatchdogs.count
    }
#endif

    var title: String {
        manga.title
    }

    var sourceLabel: String {
        sourceDisplayName(for: manga.sourceID)
    }

    var coverURL: URL? {
        manga.coverURL
    }

    var synopsis: String {
        manga.displaySynopsis
    }

    var chapters: [Chapter] {
        guard !shouldHideChaptersForLanguageSelection else {
            return []
        }

        return manga.chapters
    }

    var shouldHideChaptersForLanguageSelection: Bool {
        guard selectedReadingLanguageCode != nil else {
            return false
        }

        return isCheckingLanguage || languageStatusMessage != nil
    }

    var downloadableChapters: [Chapter] {
        let downloadedEquivalentKeys = downloadedEquivalentChapterKeysFromLibrary()

        return Self.uniqueDownloadableChapters(from: chapters)
            .filter { chapter in
                !chapter.isDownloaded
                    && !downloadedEquivalentKeys.contains(chapter.crossSourceDownloadDeduplicationKey)
            }
    }

    var canDownloadManga: Bool {
        !downloadableChapters.isEmpty && sourceIDSupportsRemotePages
    }

    var canDownloadNextBatch: Bool {
        canDownloadManga
    }

    var sourceIDSupportsRemotePages: Bool {
        NativeSourceCatalog.supportsReading(sourceID: manga.sourceID)
    }

    var sourceOptions: [MangaSourceOption] {
        availableMangas
            .map(MangaSourceOption.init)
            .sorted { lhs, rhs in
                if lhs.id == selectedSourceID { return true }
                if rhs.id == selectedSourceID { return false }
                if lhs.chapterCount != rhs.chapterCount { return lhs.chapterCount > rhs.chapterCount }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    var sourceAvailabilities: [MangaSourceAvailability] {
        sourceOptions.map { option in
            MangaSourceAvailability(
                option: option,
                state: availabilityState(for: option),
                hasMostChapters: option.id == sourceWithMostChaptersID && option.chapterCount == maxChapterCountAcrossSources && option.chapterCount > 0,
                isRecommended: option.id == recommendedSourceID
            )
        }
    }

    var maxChapterCountAcrossSources: Int {
        sourceOptions.map(\.chapterCount).max() ?? 0
    }

    var sourceWithMostChaptersID: String? {
        sourceOptions.max { lhs, rhs in
            lhs.chapterCount < rhs.chapterCount
        }?.id
    }

    var recommendedSourceID: String? {
        sourceOptions
            .filter { $0.isReadable && $0.chapterCount > 0 }
            .max { isLowerRecommendationPriority($0, than: $1) }?
            .id
    }

    var selectedSourceAvailabilitySummary: String {
        guard let selected = sourceOptions.first(where: { $0.id == selectedSourceID }) else {
            return String(localized: "source.summary.unavailable")
        }

        return String.localizedStringWithFormat(
            NSLocalizedString("source.summary.format", comment: ""),
            selected.title,
            selected.chapterCount,
            selected.language
        )
    }

    var supportsLanguageSelection: Bool {
        NativeSourceCatalog.supportsLanguageSelection(sourceID: selectedSourceID)
    }

    var languageOptions: [MangaLanguageOption] {
        var codes = Set(NativeSourceCatalog.selectableLanguageCodes)

        for candidate in availableMangas {
            if let declared = NativeSourceCatalog.declaredLanguageCode(for: candidate.sourceID) {
                codes.insert(NativeSourceCatalog.canonicalLanguageCode(declared))
            }

            candidate.availableLanguageCodes
                .map(NativeSourceCatalog.canonicalLanguageCode)
                .filter { !$0.isEmpty && $0 != "multi" }
                .forEach { codes.insert($0) }
        }

        let preferredOrder = ["es", "en"]
        return codes
            .filter { !$0.isEmpty && $0 != "multi" }
            .sorted { lhs, rhs in
                let lhsIndex = preferredOrder.firstIndex(of: lhs) ?? Int.max
                let rhsIndex = preferredOrder.firstIndex(of: rhs) ?? Int.max
                if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
                return lhs < rhs
            }
            .map(MangaLanguageOption.init)
    }

    var showsLanguageSelector: Bool {
        !languageOptions.isEmpty
    }

    var availableLanguageCodes: [String] {
        languageOptions.map(\.code)
    }

    var hasKnownAvailableLanguages: Bool {
        !availableLanguageCodes.isEmpty
    }

    var languagePreferenceTitle: String {
        if let selectedReadingLanguageCode {
            return selectedReadingLanguageCode.yomuhonLanguageDisplayName
        }

        return String(localized: "detail.language.auto")
    }

    var languageAvailabilityMessage: String? {
        if let languageStatusMessage {
            return languageStatusMessage
        }

        guard let selectedReadingLanguageCode,
              !isCheckingLanguage,
              !isLoadingDetails,
              manga.chapters.isEmpty
        else {
            return nil
        }

        return String.localizedStringWithFormat(
            NSLocalizedString("detail.language.empty", comment: ""),
            selectedReadingLanguageCode.yomuhonLanguageDisplayName
        )
    }

    var canFallbackToAnotherSource: Bool {
        sourceOptions.contains { $0.id != selectedSourceID && $0.isReadable && $0.chapterCount > 0 }
    }

    var bestFallbackSourceID: String? {
        sourceOptions
            .filter { $0.id != selectedSourceID && $0.isReadable && $0.chapterCount > 0 }
            .max { isLowerRecommendationPriority($0, than: $1) }?
            .id
    }

    var hasMultipleSources: Bool {
        availableMangas.count > 1
    }

    var currentChapterID: String? {
        progress?.currentChapterID
    }

    /// Builds a reader view model without publishing or mutating detail state.
    /// This method is intentionally side-effect free because SwiftUI may evaluate
    /// destination builders while computing MangaDetailView.body.
    func readerViewModel(for chapter: Chapter) -> ReaderViewModel {
        let latestProgress = progress

        return ReaderViewModel(
            manga: manga,
            chapter: chapter,
            initialPageIndex: latestProgress?.currentChapterID == chapter.id ? latestProgress?.currentPage ?? 0 : 0,
            updateReadingProgressUseCase: updateReadingProgressUseCase,
            sourceRepository: sourceRepository
        )
    }

    /// Runs only as a direct consequence of the user opening the reader.
    /// Reading a title makes it part of the user's library immediately, before
    /// the reader navigation hides this detail view.
    func prepareForReaderOpen() {
        LibraryMembershipStore.shared.add(manga.id)
        isSavedInLibrary = true
        persistCurrentManga()
    }

    func refreshProgress() {
        progress = libraryRepository
            .fetchReadingProgress()
            .first { $0.mangaID == manga.id }
        isSavedInLibrary = LibraryMembershipStore.shared.contains(manga.id)
    }

    func loadDetailsIfNeeded() {
        let sourceID = manga.sourceID

        guard manga.chapters.isEmpty else {
            loadedSourceIDs.insert(sourceID)
            return
        }

        // SwiftUI can call onAppear more than once while a navigation detail is
        // being rebuilt. The initial load must be idempotent; otherwise every
        // appearance cancels the active request and restarts the watchdog.
        guard !initialDetailLoadRequestedSourceIDs.contains(sourceID) else {
            detailTrace("initial load ignored because it was already requested for \(sourceID)")
            return
        }

        initialDetailLoadRequestedSourceIDs.insert(sourceID)
        startDetailLoadSession(for: sourceID, resetSourceState: false)
    }

    func refreshChapters() {
        initialDetailLoadRequestedSourceIDs.insert(selectedSourceID)
        startDetailLoadSession(for: selectedSourceID, resetSourceState: true)
    }

    func selectReadingLanguage(_ code: String?) {
        let normalizedCode = code.map(NativeSourceCatalog.canonicalLanguageCode)
        languageSearchGeneration += 1
        let generation = languageSearchGeneration
        languageSearchToken?.cancel()
        languageSearchToken = nil
        languageStatusMessage = nil

        guard let normalizedCode else {
            selectedReadingLanguageCode = nil
            isCheckingLanguage = false

            if supportsLanguageSelection, selectedExactLanguageCode != nil {
                selectedExactLanguageCode = nil
                SourceLanguagePreferenceStore.shared.setExactLanguageOverride(
                    nil,
                    mangaID: manga.id,
                    sourceID: selectedSourceID
                )
                resetSelectedSourceForLanguageReload()
            }
            return
        }

        guard selectedReadingLanguageCode != normalizedCode || languageStatusMessage != nil else {
            return
        }

        // Selecting a language is a verified content operation, not a cosmetic
        // filter. Hide the current chapter list immediately and keep it hidden
        // until one source actually returns readable chapters in that language.
        selectedReadingLanguageCode = normalizedCode
        isCheckingLanguage = true
        languageStatusMessage = String(localized: "detail.language.checking")

        let cancellationToken = RequestCancellationToken()
        languageSearchToken = cancellationToken
        let currentManga = manga
        let existingCandidates = availableMangas
        let repository = sourceRepository

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () -> Manga in
                var attemptedCandidateIDs = Set<String>()

                func verify(_ candidates: [Manga]) throws -> Manga? {
                    for candidate in candidates {
                        if cancellationToken.isCancelled {
                            throw HTTPClientError.cancelled
                        }

                        let candidateKey = "\(candidate.sourceID)|\(candidate.id)"
                        guard attemptedCandidateIDs.insert(candidateKey).inserted else {
                            continue
                        }

                        let store = SourceLanguagePreferenceStore.shared
                        let supportsExactLanguage = NativeSourceCatalog.supportsLanguageSelection(
                            sourceID: candidate.sourceID
                        )
                        let previousOverride = store.exactLanguageOverride(
                            mangaID: candidate.id,
                            sourceID: candidate.sourceID
                        )

                        // A fixed-language source whose language matches already
                        // has verified chapter semantics. Existing non-empty
                        // chapters can be reused without another network roundtrip.
                        if !supportsExactLanguage, !candidate.chapters.isEmpty {
                            return candidate
                        }

                        if supportsExactLanguage {
                            store.setExactLanguageOverride(
                                normalizedCode,
                                mangaID: candidate.id,
                                sourceID: candidate.sourceID
                            )
                        }

                        do {
                            let detailed = try repository.fetchDetails(for: candidate)
                            if !detailed.chapters.isEmpty {
                                return detailed
                            }
                        } catch {
                            SourceDebugTrace.log(
                                "Language",
                                "title=\(currentManga.title) language=\(normalizedCode) source=\(candidate.sourceID) failure=\(String(describing: error))"
                            )
                        }

                        if supportsExactLanguage {
                            store.setExactLanguageOverride(
                                previousOverride,
                                mangaID: candidate.id,
                                sourceID: candidate.sourceID
                            )
                        }
                    }

                    return nil
                }

                // First use sources already known for this work. This makes an
                // EN -> ES switch fast when Search already grouped both sources,
                // and lets a fixed-language current source confirm instantly.
                let knownCandidates = Self.languageCandidates(
                    currentManga: currentManga,
                    existingCandidates: existingCandidates,
                    searchedCandidates: [],
                    targetLanguageCode: normalizedCode,
                    canServeLanguage: { languageCode, sourceID in
                        NativeSourceCatalog.canServeLanguage(languageCode, sourceID: sourceID)
                    }
                )

                if let verified = try verify(knownCandidates) {
                    return verified
                }

                // Only search the wider catalog when the known representations
                // could not serve the requested language. Search by canonical
                // title and aliases, then keep same-work matches conservatively.
                var searched: [Manga] = []
                var seenResultIDs = Set<String>()

                for query in Self.languageSearchQueries(for: currentManga) {
                    if cancellationToken.isCancelled {
                        throw HTTPClientError.cancelled
                    }

                    let queryResults: [Manga]
                    if let progressiveRepository = repository as? ProgressiveSourceRepository {
                        queryResults = try progressiveRepository.searchManga(
                            query: query,
                            cancellationToken: cancellationToken,
                            progress: { _ in }
                        )
                    } else {
                        queryResults = try repository.searchManga(query: query)
                    }

                    for candidate in queryResults {
                        let key = "\(candidate.sourceID)|\(candidate.id)"
                        if seenResultIDs.insert(key).inserted {
                            searched.append(candidate)
                        }
                    }
                }

                let discoveredCandidates = Self.languageCandidates(
                    currentManga: currentManga,
                    existingCandidates: existingCandidates,
                    searchedCandidates: searched,
                    targetLanguageCode: normalizedCode,
                    canServeLanguage: { languageCode, sourceID in
                        NativeSourceCatalog.canServeLanguage(languageCode, sourceID: sourceID)
                    }
                )

                if let verified = try verify(discoveredCandidates) {
                    return verified
                }

                throw MangaLanguageResolutionError.unavailable
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.languageSearchGeneration == generation,
                      !cancellationToken.isCancelled
                else {
                    return
                }

                self.languageSearchToken = nil
                self.isCheckingLanguage = false

                switch result {
                case .success(let detailedManga):
                    self.mergeLanguageCandidate(detailedManga)
                    self.selectedSourceID = detailedManga.sourceID
                    self.selectedLanguagePreference = SourceLanguagePreferenceStore.shared.preference(
                        for: detailedManga.sourceID
                    )
                    self.selectedExactLanguageCode = NativeSourceCatalog.supportsLanguageSelection(
                        sourceID: detailedManga.sourceID
                    ) ? normalizedCode : nil
                    self.selectedReadingLanguageCode = normalizedCode
                    self.manga = detailedManga
                    self.loadedSourceIDs.insert(detailedManga.sourceID)
                    self.failedSourceIDs.remove(detailedManga.sourceID)
                    self.languageStatusMessage = nil
                    self.errorMessage = nil
                    self.refreshProgress()

                    SourceDebugTrace.log(
                        "Language",
                        "title=\(detailedManga.title) language=\(normalizedCode) verifiedSource=\(detailedManga.sourceID) chapters=\(detailedManga.chapters.count)"
                    )

                case .failure(let error):
                    if self.isCancellationError(error) {
                        return
                    }
                    self.languageStatusMessage = String.localizedStringWithFormat(
                        NSLocalizedString("detail.language.unavailable", comment: ""),
                        normalizedCode.yomuhonLanguageDisplayName
                    )
                }
            }
        }
    }

    func selectLanguagePreference(_ preference: SourceLanguagePreference) {
        guard supportsLanguageSelection,
              selectedLanguagePreference != preference || selectedExactLanguageCode != nil
        else {
            return
        }

        selectedLanguagePreference = preference
        SourceLanguagePreferenceStore.shared.setPreference(preference, for: selectedSourceID)

        if selectedExactLanguageCode != nil {
            selectedExactLanguageCode = nil
            SourceLanguagePreferenceStore.shared.setExactLanguageOverride(nil, mangaID: manga.id, sourceID: selectedSourceID)
        }

        if let index = availableMangas.firstIndex(where: { $0.sourceID == selectedSourceID }) {
            availableMangas[index] = Manga(
                id: manga.id,
                sourceID: manga.sourceID,
                title: manga.title,
                coverURL: manga.coverURL,
                synopsis: manga.synopsis,
                alternativeTitles: manga.alternativeTitles,
                author: manga.author,
                releaseYear: manga.releaseYear,
                chapters: []
            )
            manga = availableMangas[index]
        }

        startDetailLoadSession(for: selectedSourceID, resetSourceState: true)
    }

    /// Pick one specific language (e.g. "pt-br") for this title only, instead
    /// of the broad Spanish/English/both preference. Pass `nil` to go back to
    /// following the global preference for this title.
    func selectExactLanguage(_ code: String?) {
        guard supportsLanguageSelection, selectedExactLanguageCode != code else {
            return
        }

        selectedExactLanguageCode = code
        SourceLanguagePreferenceStore.shared.setExactLanguageOverride(code, mangaID: manga.id, sourceID: selectedSourceID)

        if let index = availableMangas.firstIndex(where: { $0.sourceID == selectedSourceID }) {
            availableMangas[index] = Manga(
                id: manga.id,
                sourceID: manga.sourceID,
                title: manga.title,
                coverURL: manga.coverURL,
                synopsis: manga.synopsis,
                alternativeTitles: manga.alternativeTitles,
                author: manga.author,
                releaseYear: manga.releaseYear,
                chapters: []
            )
            manga = availableMangas[index]
        }

        startDetailLoadSession(for: selectedSourceID, resetSourceState: true)
    }

    func addToLibrary() {
        updateReadingProgressUseCase.addToLibrary(manga: manga)
        isSavedInLibrary = true
        refreshProgress()
    }

    func selectSource(_ sourceID: String) {
        guard
            selectedSourceID != sourceID,
            let selectedManga = availableMangas.first(where: { $0.sourceID == sourceID })
        else {
            return
        }

        selectedSourceID = sourceID
        selectedLanguagePreference = SourceLanguagePreferenceStore.shared.preference(for: sourceID)
        selectedExactLanguageCode = SourceLanguagePreferenceStore.shared.exactLanguageOverride(mangaID: selectedManga.id, sourceID: sourceID)
        selectedReadingLanguageCode = Self.initialReadingLanguageCode(for: selectedManga)
        languageStatusMessage = nil
        manga = selectedManga
        isSavedInLibrary = LibraryMembershipStore.shared.contains(selectedManga.id)
        errorMessage = nil

        if selectedManga.chapters.isEmpty {
            startDetailLoadSession(for: sourceID, resetSourceState: true)
        } else {
            cancelCurrentDetailSession()
            loadedSourceIDs.insert(sourceID)
        }
    }

    func switchToBestFallbackSource() {
        guard let sourceID = bestFallbackSourceID else {
            return
        }

        selectSource(sourceID)
    }

    func downloadNextBatch(limit: Int = 10) {
        enqueueDownloads(Array(downloadableChapters.prefix(limit)), asBulkDownload: true)
    }

    func downloadAllChapters() {
        enqueueDownloads(downloadableChapters, asBulkDownload: true)
    }

    func canDownload(_ chapter: Chapter) -> Bool {
        sourceIDSupportsRemotePages
            && !chapter.isDownloaded
            && !alreadyDownloadedEquivalentChapter(for: chapter)
            && !downloadedEquivalentChapterKeysFromLibrary().contains(chapter.crossSourceDownloadDeduplicationKey)
    }

    func download(_ chapter: Chapter) {
        guard canDownload(chapter) else {
            return
        }

        enqueueDownloads([chapter], asBulkDownload: false)
    }

    private func enqueueDownloads(_ chaptersToDownload: [Chapter], asBulkDownload: Bool) {
        guard sourceIDSupportsRemotePages, !chaptersToDownload.isEmpty else {
            return
        }

        downloadStatusMessage = nil
        let ids = DownloadCenter.shared.enqueue(manga: manga, chapters: chaptersToDownload)

        if asBulkDownload {
            bulkDownloadIDs.formUnion(ids)
        }

        syncDownloadState(with: DownloadCenter.shared.activeDownloads)
    }

    private func observeDownloadCenter() {
        DownloadCenter.shared.$activeDownloads
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                self?.syncDownloadState(with: items)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .yomuhonDownloadLibraryDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self else { return }
                let changedMangaID = notification.userInfo?["mangaID"] as? String
                guard changedMangaID == nil || changedMangaID == self.manga.id else {
                    return
                }
                self.reloadDownloadedMangaFromLibrary()
            }
            .store(in: &cancellables)
    }

    private func syncDownloadState(with items: [ActiveDownloadItem]) {
        let relevant = items.filter { $0.manga.id == manga.id }
        let activeStates: Set<DownloadJobState> = [.queued, .running]
        let active = relevant.filter { activeStates.contains($0.state) }

        isDownloading = !active.isEmpty

        let bulkItems = relevant.filter { bulkDownloadIDs.contains($0.id) }
        let activeBulkItems = bulkItems.filter { activeStates.contains($0.state) }
        isDownloadingManga = !activeBulkItems.isEmpty

        if !bulkItems.isEmpty {
            mangaDownloadProgress = bulkItems.reduce(0) { $0 + $1.progress } / Double(bulkItems.count)
        } else {
            mangaDownloadProgress = 0
        }

        if let failed = relevant.first(where: { $0.state == .failed }) {
            downloadStatusMessage = failed.message ?? String(localized: "detail.downloadError")
        } else if DownloadCenter.shared.isPaused, !active.isEmpty {
            downloadStatusMessage = String(localized: "downloads.queue.paused.message")
        } else if !active.isEmpty {
            downloadStatusMessage = nil
        }

        let finishedBulkIDs = bulkDownloadIDs.filter { id in
            guard let item = items.first(where: { $0.id == id }) else {
                return true
            }
            return item.state == .completed || item.state == .cancelled || item.state == .failed
        }
        bulkDownloadIDs.subtract(finishedBulkIDs)
    }

    private func reloadDownloadedMangaFromLibrary() {
        guard let savedManga = libraryRepository
            .fetchLibrary()
            .first(where: { $0.id == manga.id })
        else {
            return
        }

        manga = savedManga
        replaceAvailableManga(savedManga)
    }

    private func downloadedEquivalentChapterKeysFromLibrary() -> Set<String> {
        let currentTitleKey = manga.crossSourceTitleKey

        return Set(
            libraryRepository
                .fetchLibrary()
                .filter { $0.id != manga.id && $0.crossSourceTitleKey == currentTitleKey }
                .flatMap { $0.chapters }
                .filter(\.isDownloaded)
                .map(\.crossSourceDownloadDeduplicationKey)
        )
    }

    private func alreadyDownloadedEquivalentChapter(for chapter: Chapter) -> Bool {
        let key = chapter.downloadDeduplicationKey

        return manga.chapters.contains { candidate in
            candidate.id != chapter.id
                && candidate.isDownloaded
                && candidate.downloadDeduplicationKey == key
        }
    }

    private var highestPriorityReadableSourceID: String? {
        sourceOptions
            .filter(\.isReadable)
            .max { isLowerRecommendationPriority($0, than: $1) }?
            .id
    }

    private func isLowerRecommendationPriority(
        _ lhs: MangaSourceOption,
        than rhs: MangaSourceOption
    ) -> Bool {
        let lhsHasKnownChapters = lhs.chapterCount > 0
        let rhsHasKnownChapters = rhs.chapterCount > 0

        if lhsHasKnownChapters != rhsHasKnownChapters {
            return !lhsHasKnownChapters
        }

        let lhsTrust = NativeSourceCatalog.automaticSelectionTrustRank(for: lhs.id)
        let rhsTrust = NativeSourceCatalog.automaticSelectionTrustRank(for: rhs.id)

        if lhsTrust != rhsTrust {
            return lhsTrust < rhsTrust
        }

        let lhsPriority = SourcePerformanceStore.shared.priorityScore(for: lhs.id)
        let rhsPriority = SourcePerformanceStore.shared.priorityScore(for: rhs.id)

        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        if lhs.chapterCount != rhs.chapterCount {
            return lhs.chapterCount < rhs.chapterCount
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedDescending
    }

    private func availabilityState(for option: MangaSourceOption) -> SourceAvailabilityState {
        if option.id == selectedSourceID {
            return .selected
        }

        if loadingSourceIDs.contains(option.id) {
            return .loading
        }

        if !option.isReadable || failedSourceIDs.contains(option.id) {
            return .unavailable
        }

        if option.chapterCount == 0 {
            return .empty
        }

        return .ready
    }

    private func persistCurrentManga() {
        libraryRepository.saveManga(manga)
    }

    private func replaceAvailableManga(_ updatedManga: Manga) {
        guard let index = availableMangas.firstIndex(where: { $0.sourceID == updatedManga.sourceID }) else {
            return
        }

        availableMangas[index] = updatedManga
    }

    private func startDetailLoadSession(for sourceID: String, resetSourceState: Bool) {
        cancelDetailSessionWatchdog()
        cancelAllDetailLoads()
        detailSessionGeneration += 1
        let sessionGeneration = detailSessionGeneration

        detailSessionAttemptedSourceIDs.removeAll()
        detailSessionDeadline = nil
        errorMessage = nil

        if resetSourceState {
            loadedSourceIDs.remove(sourceID)
            failedSourceIDs.remove(sourceID)
        } else if failedSourceIDs.contains(sourceID) {
            isLoadingDetails = false
            errorMessage = String(localized: "detail.noChaptersAfterRefresh")
            detailTrace("session not started because \(sourceID) is already marked failed")
            return
        } else if loadedSourceIDs.contains(sourceID) {
            isLoadingDetails = false
            errorMessage = String(localized: "detail.noChaptersAfterRefresh")
            detailTrace("session not started because \(sourceID) is marked loaded but has zero chapters")
            return
        }

        guard let targetManga = availableMangas.first(where: { $0.sourceID == sourceID }) else {
            isLoadingDetails = false
            errorMessage = String(localized: "detail.loadError")
            detailTrace("session failed: missing manga for source \(sourceID)")
            return
        }

        if !targetManga.chapters.isEmpty {
            loadedSourceIDs.insert(sourceID)
            failedSourceIDs.remove(sourceID)
            manga = targetManga
            isLoadingDetails = false
            detailTrace("session skipped: \(sourceID) already has \(targetManga.chapters.count) chapters")
            return
        }

        detailSessionDeadline = Date().addingTimeInterval(detailSessionTimeout)
        isLoadingDetails = true
        detailTrace("session \(sessionGeneration) started for \(sourceID)")
        scheduleDetailSessionTimeout(sessionGeneration: sessionGeneration)

        guard loadDetails(for: sourceID, sessionGeneration: sessionGeneration) else {
            completeDetailSessionFailure(
                sessionGeneration: sessionGeneration,
                message: String(localized: "detail.loadError")
            )
            return
        }
    }

    private func cancelCurrentDetailSession() {
        detailSessionGeneration += 1
        detailSessionDeadline = nil
        detailSessionAttemptedSourceIDs.removeAll()
        cancelDetailSessionWatchdog()
        cancelAllDetailLoads()
    }

    private func cancelAllDetailLoads() {
        detailRequestWatchdogs.values.forEach { $0.cancel() }
        detailRequestWatchdogs.removeAll()

        detailLoadTokens.values.forEach { $0.cancel() }
        detailLoadTokens.removeAll()

        for sourceID in loadingSourceIDs {
            detailLoadGenerationBySourceID[sourceID, default: 0] += 1
        }

        loadingSourceIDs.removeAll()
        isLoadingDetails = false
    }

    private func cancelDetailSessionWatchdog() {
        detailSessionWatchdog?.cancel()
        detailSessionWatchdog = nil
    }

    private func cancelDetailRequestWatchdog(for sourceID: String) {
        detailRequestWatchdogs.removeValue(forKey: sourceID)?.cancel()
    }

    @discardableResult
    private func loadDetails(for sourceID: String, sessionGeneration: Int) -> Bool {
        guard detailSessionGeneration == sessionGeneration,
              let deadline = detailSessionDeadline,
              deadline > Date(),
              detailSessionAttemptedSourceIDs.count < maximumAutomaticSourceAttempts,
              !detailSessionAttemptedSourceIDs.contains(sourceID),
              !loadedSourceIDs.contains(sourceID),
              !loadingSourceIDs.contains(sourceID),
              !failedSourceIDs.contains(sourceID)
        else {
            detailTrace("request refused for \(sourceID); session=\(sessionGeneration), attempted=\(detailSessionAttemptedSourceIDs), loaded=\(loadedSourceIDs), loading=\(loadingSourceIDs), failed=\(failedSourceIDs)")
            return false
        }

        guard let targetManga = availableMangas.first(where: { $0.sourceID == sourceID }) else {
            completeDetailSessionFailure(
                sessionGeneration: sessionGeneration,
                message: String(localized: "detail.loadError")
            )
            return false
        }

        detailSessionAttemptedSourceIDs.insert(sourceID)
        loadingSourceIDs.insert(sourceID)
        isLoadingDetails = true
        errorMessage = nil

        let generation = (detailLoadGenerationBySourceID[sourceID] ?? 0) + 1
        detailLoadGenerationBySourceID[sourceID] = generation

        let cancellationToken = RequestCancellationToken()
        detailLoadTokens[sourceID]?.cancel()
        detailLoadTokens[sourceID] = cancellationToken

        let remainingSessionTime = max(0.2, deadline.timeIntervalSinceNow)

        // Detail uses a hard UI deadline. Declarative sources now parse metadata
        // and chapters from one document, so a source no longer gets two serial
        // page downloads before the watchdog can move to the next candidate.
        scheduleDetailLoadTimeout(
            for: sourceID,
            generation: generation,
            sessionGeneration: sessionGeneration,
            timeout: min(detailLoadTimeout, remainingSessionTime),
            cancellationToken: cancellationToken
        )

        let useCase = getChapterListUseCase

        DispatchQueue.global(qos: .userInitiated).async {
            self.detailTrace("worker begin source=\(sourceID) session=\(sessionGeneration) generation=\(generation)")
            let result = Result {
                try HTTPRequestCancellationContext.withToken(cancellationToken) {
                    try useCase.execute(manga: targetManga)
                }
            }

            switch result {
            case .success(let loadedManga):
                self.detailTrace("worker result ready source=\(sourceID) chapters=\(loadedManga.chapters.count)")
            case .failure(let error):
                self.detailTrace("worker result ready source=\(sourceID) failure=\(String(describing: error))")
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.detailSessionGeneration == sessionGeneration,
                      self.detailLoadGenerationBySourceID[sourceID] == generation,
                      self.loadingSourceIDs.contains(sourceID),
                      !cancellationToken.isCancelled
                else {
                    return
                }

                self.finishDetailLoading(sourceID: sourceID)

                switch result {
                case .success(let updatedManga):
                    self.detailTrace("request succeeded for \(sourceID) with \(updatedManga.chapters.count) chapters")
                    self.replaceAvailableManga(updatedManga)

                    guard !updatedManga.chapters.isEmpty else {
                        self.failedSourceIDs.insert(sourceID)
                        self.tryNextAutomaticSource(
                            after: sourceID,
                            sessionGeneration: sessionGeneration,
                            terminalMessage: String(localized: "detail.noChaptersAfterRefresh")
                        )
                        return
                    }

                    self.loadedSourceIDs.insert(sourceID)
                    self.failedSourceIDs.remove(sourceID)
                    self.selectedSourceID = sourceID
                    self.selectedLanguagePreference = SourceLanguagePreferenceStore.shared.preference(for: sourceID)
                    self.selectedExactLanguageCode = SourceLanguagePreferenceStore.shared.exactLanguageOverride(mangaID: updatedManga.id, sourceID: sourceID)
                    self.manga = updatedManga
                    self.completeDetailSessionSuccess(sessionGeneration: sessionGeneration)

                case .failure(let error):
                    self.detailTrace("request failed for \(sourceID): \(String(describing: error))")
                    self.failedSourceIDs.insert(sourceID)

                    let terminalMessage: String
                    if self.isCancellationError(error) {
                        terminalMessage = String(localized: "detail.loadTimedOut")
                    } else {
                        terminalMessage = String(localized: "detail.loadError")
                    }

                    self.tryNextAutomaticSource(
                        after: sourceID,
                        sessionGeneration: sessionGeneration,
                        terminalMessage: terminalMessage
                    )
                }
            }
        }

        return true
    }

    private func tryNextAutomaticSource(
        after sourceID: String,
        sessionGeneration: Int,
        terminalMessage: String
    ) {
        guard detailSessionGeneration == sessionGeneration,
              let deadline = detailSessionDeadline,
              deadline > Date(),
              detailSessionAttemptedSourceIDs.count < maximumAutomaticSourceAttempts,
              let fallbackID = nextUnloadedReadableSourceID(excluding: sourceID)
        else {
            completeDetailSessionFailure(
                sessionGeneration: sessionGeneration,
                message: terminalMessage
            )
            return
        }

        guard loadDetails(for: fallbackID, sessionGeneration: sessionGeneration) else {
            completeDetailSessionFailure(
                sessionGeneration: sessionGeneration,
                message: terminalMessage
            )
            return
        }
    }

    private func scheduleDetailSessionTimeout(sessionGeneration: Int) {
        cancelDetailSessionWatchdog()

        let scheduledAt = Date()
        detailTrace("session \(sessionGeneration) watchdog scheduled for \(detailSessionTimeout)s")
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.detailSessionGeneration == sessionGeneration,
                  self.detailSessionDeadline != nil,
                  self.isLoadingDetails
            else {
                return
            }

            self.detailSessionWatchdog = nil
            self.detailTrace(
                "session \(sessionGeneration) watchdog fired after \(String(format: "%.3f", Date().timeIntervalSince(scheduledAt)))s"
            )
            self.detailTrace("session \(sessionGeneration) timed out; active sources=\(self.loadingSourceIDs)")
            self.failedSourceIDs.formUnion(self.loadingSourceIDs)
            self.cancelAllDetailLoads()
            self.detailSessionDeadline = nil
            self.errorMessage = String(localized: "detail.loadTimedOut")
        }

        detailSessionWatchdog = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + detailSessionTimeout, execute: workItem)
    }

    private func scheduleDetailLoadTimeout(
        for sourceID: String,
        generation: Int,
        sessionGeneration: Int,
        timeout: TimeInterval,
        cancellationToken: RequestCancellationToken
    ) {
        cancelDetailRequestWatchdog(for: sourceID)

        let scheduledAt = Date()
        detailTrace("request watchdog scheduled source=\(sourceID) timeout=\(timeout)s generation=\(generation)")
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.detailSessionGeneration == sessionGeneration,
                  self.detailLoadGenerationBySourceID[sourceID] == generation,
                  self.loadingSourceIDs.contains(sourceID)
            else {
                return
            }

            self.detailRequestWatchdogs.removeValue(forKey: sourceID)
            self.detailTrace(
                "request watchdog fired source=\(sourceID) after=\(String(format: "%.3f", Date().timeIntervalSince(scheduledAt)))s generation=\(generation)"
            )
            self.detailTrace("request timeout for \(sourceID), generation \(generation)")
            cancellationToken.cancel()
            self.failedSourceIDs.insert(sourceID)
            self.detailLoadGenerationBySourceID[sourceID] = generation + 1
            self.finishDetailLoading(sourceID: sourceID)
            self.tryNextAutomaticSource(
                after: sourceID,
                sessionGeneration: sessionGeneration,
                terminalMessage: String(localized: "detail.loadTimedOut")
            )
        }

        detailRequestWatchdogs[sourceID] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func completeDetailSessionSuccess(sessionGeneration: Int) {
        guard detailSessionGeneration == sessionGeneration else { return }
        detailTrace("session \(sessionGeneration) completed successfully with \(manga.chapters.count) chapters")
        detailSessionDeadline = nil
        cancelDetailSessionWatchdog()
        cancelAllDetailLoads()
        errorMessage = nil
    }

    private func completeDetailSessionFailure(sessionGeneration: Int, message: String) {
        guard detailSessionGeneration == sessionGeneration else { return }
        detailTrace("session \(sessionGeneration) failed: \(message)")
        detailSessionDeadline = nil
        cancelDetailSessionWatchdog()
        cancelAllDetailLoads()
        errorMessage = message
    }

    private func finishDetailLoading(sourceID: String) {
        cancelDetailRequestWatchdog(for: sourceID)
        loadingSourceIDs.remove(sourceID)
        detailLoadTokens.removeValue(forKey: sourceID)
        isLoadingDetails = !loadingSourceIDs.isEmpty
    }

    private func nextUnloadedReadableSourceID(excluding sourceID: String) -> String? {
        availableMangas
            .filter { candidate in
                candidate.sourceID != sourceID
                    && NativeSourceCatalog.supportsReading(sourceID: candidate.sourceID)
                    && !detailSessionAttemptedSourceIDs.contains(candidate.sourceID)
                    && !loadedSourceIDs.contains(candidate.sourceID)
                    && !loadingSourceIDs.contains(candidate.sourceID)
                    && !failedSourceIDs.contains(candidate.sourceID)
            }
            .map(MangaSourceOption.init)
            .max { isLowerRecommendationPriority($0, than: $1) }?
            .id
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if let clientError = error as? HTTPClientError {
            return clientError.isCancellation
        }

        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError {
            return urlError.code == .cancelled
        }

        return false
    }

    private func resetSelectedSourceForLanguageReload() {
        guard let index = availableMangas.firstIndex(where: { $0.sourceID == selectedSourceID }) else {
            return
        }

        let current = availableMangas[index]
        let resetManga = Manga(
            id: current.id,
            sourceID: current.sourceID,
            title: current.title,
            coverURL: current.coverURL,
            synopsis: current.synopsis,
            alternativeTitles: current.alternativeTitles,
            author: current.author,
            releaseYear: current.releaseYear,
            chapters: []
        )

        availableMangas[index] = resetManga
        manga = resetManga
        startDetailLoadSession(for: selectedSourceID, resetSourceState: true)
    }

    private func mergeLanguageCandidate(_ candidate: Manga) {
        if let index = availableMangas.firstIndex(where: { $0.sourceID == candidate.sourceID }) {
            availableMangas[index] = candidate
        } else {
            availableMangas.append(candidate)
        }
    }

    private static func initialReadingLanguageCode(for manga: Manga) -> String? {
        if let exact = SourceLanguagePreferenceStore.shared.exactLanguageOverride(
            mangaID: manga.id,
            sourceID: manga.sourceID
        ) {
            return NativeSourceCatalog.canonicalLanguageCode(exact)
        }

        return NativeSourceCatalog.declaredLanguageCode(for: manga.sourceID)
    }

    private static func languageSearchQueries(for manga: Manga) -> [String] {
        var titles: [String] = [manga.title]

        if let alternativeTitles = manga.alternativeTitles {
            titles.append(contentsOf: alternativeTitles)
        }

        var seen = Set<String>()

        return titles
            .map { title in
                title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .filter { query in
                let key = query
                    .folding(
                        options: [.diacriticInsensitive, .caseInsensitive],
                        locale: .current
                    )
                    .lowercased()

                return seen.insert(key).inserted
            }
            .prefix(4)
            .map { String($0) }
    }

    static func languageCandidates(
        currentManga: Manga,
        existingCandidates: [Manga],
        searchedCandidates: [Manga],
        targetLanguageCode: String,
        canServeLanguage: (String, String) -> Bool
    ) -> [Manga] {
        let normalizedCode = NativeSourceCatalog.canonicalLanguageCode(targetLanguageCode)
        let sameWorkResults = searchedCandidates.filter {
            MangaIdentityResolver.sameWork(currentManga, $0)
        }

        var alternatives = existingCandidates
        alternatives.append(contentsOf: sameWorkResults)

        return uniqueMangas(
            primary: currentManga,
            alternatives: alternatives
        )
        .filter { canServeLanguage(normalizedCode, $0.sourceID) }
        .sorted { lhs, rhs in
            languageCandidateScore(lhs) > languageCandidateScore(rhs)
        }
    }

    private static func languageCandidateScore(_ manga: Manga) -> Double {
        let trust = Double(NativeSourceCatalog.automaticSelectionTrustRank(for: manga.sourceID))
        let performance = SourcePerformanceStore.shared.priorityScore(for: manga.sourceID)
        let chapterBonus = manga.chapters.isEmpty ? 0.0 : min(Double(manga.chapters.count), 2_000) / 10_000.0
        return trust + performance + chapterBonus
    }

    private static func uniqueDownloadableChapters(from chapters: [Chapter]) -> [Chapter] {
        var seen = Set<String>()

        return chapters
            .sorted { lhs, rhs in
                if lhs.number != rhs.number {
                    return lhs.number < rhs.number
                }

                return lhs.id < rhs.id
            }
            .filter { chapter in
                seen.insert(chapter.downloadDeduplicationKey).inserted
            }
    }

    private static func uniqueMangas(primary: Manga, alternatives: [Manga]) -> [Manga] {
        var seen = Set<String>()
        var candidates: [Manga] = [primary]
        candidates.append(contentsOf: alternatives)

        return candidates.filter { manga in
            seen.insert(manga.sourceID).inserted
        }
    }

    private func detailTrace(_ message: @autoclosure () -> String) {
#if DEBUG
        print("[Yomuhon][Detail][vm:\(ObjectIdentifier(self))] \(message())")
#endif
    }

}

private enum MangaLanguageResolutionError: Error {
    case unavailable
}

private func sourceDisplayName(for sourceID: String) -> String {
    NativeSourceCatalog.displayName(for: sourceID)
}

private extension ReadingStatus {
    var localizedTitle: String {
        switch self {
        case .planToRead:
            return String(localized: "readingStatus.planToRead")
        case .reading:
            return String(localized: "readingStatus.reading")
        case .completed:
            return String(localized: "readingStatus.completed")
        }
    }
}


