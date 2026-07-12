//
//  DownloadsView.swift
//  Yomuhon
//

import SwiftUI
import Combine
import Foundation

enum DownloadJobState: String, Equatable, Hashable, Codable {
    case queued
    case running
    case paused
    case completed
    case failed
    case cancelled

    var titleKey: LocalizedStringKey {
        switch self {
        case .queued:
            return "downloads.queue.queued"
        case .running:
            return "downloads.queue.running"
        case .paused:
            return "downloads.queue.paused"
        case .completed:
            return "downloads.queue.completed"
        case .failed:
            return "downloads.queue.failed"
        case .cancelled:
            return "downloads.queue.cancelled"
        }
    }

    var systemImage: String {
        switch self {
        case .queued:
            return "clock"
        case .running:
            return "arrow.down.circle"
        case .paused:
            return "pause.circle"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        case .cancelled:
            return "xmark.circle"
        }
    }
}

struct ActiveDownloadItem: Identifiable, Equatable, Codable {
    let id: String
    var manga: Manga
    let chapter: Chapter
    let mangaTitle: String
    let chapterTitle: String
    let coverURL: URL?
    var progress: Double
    var state: DownloadJobState
    var message: String?

    var canCancel: Bool {
        state == .queued || state == .running || state == .paused
    }

    var canRetry: Bool {
        state == .failed || state == .cancelled
    }
}

extension Notification.Name {
    static let yomuhonDownloadLibraryDidChange = Notification.Name("yomuhon.download.libraryDidChange")
}

/// Persistent download queue shared by Detail and Downloads.
///
/// The queue owns download execution. View models only enqueue work and observe
/// the library change notification, which prevents duplicate download pipelines
/// from competing for the same chapter.
final class DownloadCenter: ObservableObject {
    static let shared = DownloadCenter()

    @Published private(set) var activeDownloads: [ActiveDownloadItem]
    @Published private(set) var isPaused: Bool

    private let operationQueue: OperationQueue
    private let cancellationLock = NSLock()
    private let dependencyLock = NSLock()
    private let executionLock = NSLock()
    private let pauseStateLock = NSLock()
    private let activeRequestTokenLock = NSLock()
    private let pauseInterruptionLock = NSLock()
    private var cancelledIDs = Set<String>()
    private var executingIDs = Set<String>()
    private var activeRequestTokens: [String: RequestCancellationToken] = [:]
    private var pauseInterruptedIDs = Set<String>()
    private var pauseFlag: Bool
    private var downloadUseCase: DownloadChapterUseCase?
    private var persistWorkItem: DispatchWorkItem?

    private struct PersistedQueue: Codable {
        let items: [ActiveDownloadItem]
        let isPaused: Bool
    }

    private init() {
        #if DEBUG
        let persisted = ProcessInfo.processInfo.arguments.contains("-ui-testing")
            ? PersistedQueue(items: [], isPaused: false)
            : Self.loadPersistedQueue()
        #else
        let persisted = Self.loadPersistedQueue()
        #endif
        self.activeDownloads = persisted.items
            .filter { $0.state != .completed }
            .map { item in
                var item = item
                switch item.state {
                case .running:
                    item.state = persisted.isPaused ? .paused : .queued
                    item.message = persisted.isPaused
                        ? String(localized: "downloads.queue.paused.message")
                        : String(localized: "downloads.queue.restored")
                case .paused:
                    if !persisted.isPaused {
                        item.state = .queued
                        item.message = String(localized: "downloads.queue.restored")
                    }
                default:
                    break
                }
                return item
            }
        self.isPaused = persisted.isPaused
        self.pauseFlag = persisted.isPaused

        let queue = OperationQueue()
        queue.name = "com.yomuhon.downloads"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        self.operationQueue = queue
    }

    deinit {
        persistWorkItem?.cancel()
        cancelAllActiveRequestTokens()
    }

    var runningCount: Int {
        activeDownloads.filter { $0.state == .running }.count
    }

    var queuedCount: Int {
        activeDownloads.filter { $0.state == .queued || $0.state == .paused }.count
    }

    var failedCount: Int {
        activeDownloads.filter { $0.state == .failed }.count
    }

    func configure(downloadUseCase: DownloadChapterUseCase) {
        dependencyLock.lock()
        self.downloadUseCase = downloadUseCase
        dependencyLock.unlock()
        runOnMain { [weak self] in
            self?.pumpQueue()
        }
    }

    @discardableResult
    func enqueue(manga: Manga, chapter: Chapter) -> String {
        let id = "\(manga.id)-\(chapter.id)"

        runOnMain { [weak self] in
            guard let self else { return }

            self.cancelledIDsSafelyRemove(id)
            let item = ActiveDownloadItem(
                id: id,
                manga: manga,
                chapter: chapter,
                mangaTitle: manga.title,
                chapterTitle: chapter.cleanTitleOrDisplayTitle,
                coverURL: manga.coverURL,
                progress: 0,
                state: self.isPaused ? .paused : .queued,
                message: self.isPaused
                    ? String(localized: "downloads.queue.paused.message")
                    : nil
            )

            if let index = self.activeDownloads.firstIndex(where: { $0.id == id }) {
                let existing = self.activeDownloads[index]
                guard existing.state != .running
                    && existing.state != .queued
                    && existing.state != .paused
                else {
                    return
                }
                self.activeDownloads[index] = item
            } else {
                self.activeDownloads.append(item)
            }

            self.schedulePersist()
            self.pumpQueue()
        }

        return id
    }

    @discardableResult
    func enqueue(manga: Manga, chapters: [Chapter]) -> [String] {
        chapters.map { enqueue(manga: manga, chapter: $0) }
    }

    func pauseAll() {
        runOnMain { [weak self] in
            guard let self, !self.isPaused else { return }

            self.setPauseFlag(true)
            self.isPaused = true
            for index in self.activeDownloads.indices {
                if self.activeDownloads[index].state == .running
                    || self.activeDownloads[index].state == .queued {
                    self.activeDownloads[index].state = .paused
                    self.activeDownloads[index].message = String(localized: "downloads.queue.paused.message")
                }
            }
            SourceDebugTrace.log("Downloads", "PAUSE requested active=\(self.executingCount)")
            self.interruptActiveRequestsForPause()
            self.schedulePersist()
        }
    }

    func resumeAll() {
        runOnMain { [weak self] in
            guard let self, self.isPaused else { return }

            self.setPauseFlag(false)
            self.isPaused = false
            for index in self.activeDownloads.indices where self.activeDownloads[index].state == .paused {
                guard !self.isExecuting(id: self.activeDownloads[index].id) else {
                    continue
                }
                self.activeDownloads[index].state = .queued
                self.activeDownloads[index].message = nil
            }
            SourceDebugTrace.log("Downloads", "RESUME requested queued=\(self.queuedCount)")
            self.schedulePersist()
            self.pumpQueue()
        }
    }

    func cancel(id: String) {
        cancellationLock.lock()
        cancelledIDs.insert(id)
        cancellationLock.unlock()
        cancelActiveRequestToken(id: id)
        SourceDebugTrace.log("Downloads", "CANCEL id=\(id)")

        runOnMain { [weak self] in
            guard let self,
                  let index = self.activeDownloads.firstIndex(where: { $0.id == id })
            else {
                return
            }

            self.activeDownloads[index].state = .cancelled
            self.activeDownloads[index].message = String(localized: "downloads.queue.cancelled.message")
            self.schedulePersist()
            self.pumpQueue()
        }
    }

    func retry(id: String) {
        runOnMain { [weak self] in
            guard let self,
                  let index = self.activeDownloads.firstIndex(where: { $0.id == id }),
                  self.activeDownloads[index].canRetry
            else {
                return
            }

            self.cancelledIDsSafelyRemove(id)
            self.pauseInterruptedIDsSafelyRemove(id)
            self.activeDownloads[index].progress = 0
            self.activeDownloads[index].state = self.isPaused ? .paused : .queued
            self.activeDownloads[index].message = self.isPaused
                ? String(localized: "downloads.queue.paused.message")
                : nil
            self.schedulePersist()
            self.pumpQueue()
        }
    }

    func isCancelled(id: String) -> Bool {
        cancellationLock.lock()
        let isCancelled = cancelledIDs.contains(id)
        cancellationLock.unlock()
        return isCancelled
    }

    func clearFinishedOrCancelled(id: String) {
        runOnMain { [weak self] in
            guard let self else { return }
            self.activeDownloads.removeAll {
                $0.id == id && ($0.state == .cancelled || $0.state == .completed)
            }
            self.cancelledIDsSafelyRemove(id)
            self.pauseInterruptedIDsSafelyRemove(id)
            self.schedulePersist()
            self.pumpQueue()
        }
    }

    func clearFailed(id: String) {
        runOnMain { [weak self] in
            guard let self else { return }
            self.activeDownloads.removeAll {
                $0.id == id && ($0.state == .failed || $0.state == .cancelled)
            }
            self.cancelledIDsSafelyRemove(id)
            self.pauseInterruptedIDsSafelyRemove(id)
            self.schedulePersist()
            self.pumpQueue()
        }
    }

    private func pumpQueue() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isPaused else { return }

        dependencyLock.lock()
        let hasUseCase = downloadUseCase != nil
        dependencyLock.unlock()
        guard hasUseCase else { return }

        let capacity = max(0, operationQueue.maxConcurrentOperationCount - executingCount)
        guard capacity > 0 else { return }

        let candidates = Array(activeDownloads.filter { $0.state == .queued }.prefix(capacity))
        guard !candidates.isEmpty else { return }

        for candidate in candidates {
            guard let index = activeDownloads.firstIndex(where: { $0.id == candidate.id }) else {
                continue
            }

            activeDownloads[index].state = .running
            activeDownloads[index].message = nil
            markExecuting(candidate.id)
            schedulePersist()

            operationQueue.addOperation { [weak self] in
                self?.execute(candidate)
            }
        }
    }

    private func execute(_ item: ActiveDownloadItem) {
        dependencyLock.lock()
        let useCase = downloadUseCase
        dependencyLock.unlock()

        guard let useCase else {
            markExecutionFinished(item.id)
            finishWithFailure(id: item.id, message: String(localized: "downloads.queue.failed.message"))
            return
        }

        let cancellationToken = RequestCancellationToken()
        registerActiveRequestToken(cancellationToken, id: item.id)
        SourceDebugTrace.log("Downloads", "START id=\(item.id) chapter=\(item.chapter.id)")

        let result = Result {
            try HTTPRequestCancellationContext.withToken(cancellationToken) {
                if shouldInterruptDownload(id: item.id) {
                    throw DownloadRepositoryError.cancelled
                }

                return try useCase.execute(
                    chapter: item.chapter,
                    manga: item.manga,
                    progressHandler: { [weak self] progress in
                        self?.updateProgress(id: item.id, progress: progress)
                    },
                    shouldCancel: { [weak self] in
                        self?.shouldInterruptDownload(id: item.id) ?? true
                    }
                )
            }
        }

        unregisterActiveRequestToken(id: item.id, token: cancellationToken)
        markExecutionFinished(item.id)

        switch result {
        case .success(let updatedManga):
            pauseInterruptedIDsSafelyRemove(item.id)
            runOnMain { [weak self] in
                guard let self,
                      let index = self.activeDownloads.firstIndex(where: { $0.id == item.id })
                else {
                    return
                }

                self.activeDownloads[index].manga = updatedManga
                self.activeDownloads[index].progress = 1
                self.activeDownloads[index].state = .completed
                self.activeDownloads[index].message = String(localized: "downloads.queue.completed")
                self.cancelledIDsSafelyRemove(item.id)
                self.schedulePersist()
                SourceDebugTrace.log("Downloads", "COMPLETED id=\(item.id)")

                NotificationCenter.default.post(
                    name: .yomuhonDownloadLibraryDidChange,
                    object: self,
                    userInfo: ["mangaID": updatedManga.id]
                )

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    guard let self else { return }
                    self.activeDownloads.removeAll { $0.id == item.id && $0.state == .completed }
                    self.schedulePersist()
                    self.pumpQueue()
                }

                self.pumpQueue()
            }

        case .failure(let error):
            if isDownloadCancellation(error) {
                let explicitlyCancelled = isCancelled(id: item.id)
                let interruptedForPause = consumePauseInterruption(id: item.id)

                runOnMain { [weak self] in
                    guard let self,
                          let index = self.activeDownloads.firstIndex(where: { $0.id == item.id })
                    else {
                        return
                    }

                    if explicitlyCancelled {
                        self.activeDownloads[index].state = .cancelled
                        self.activeDownloads[index].message = String(localized: "downloads.queue.cancelled.message")
                        SourceDebugTrace.log("Downloads", "CANCELLED id=\(item.id)")
                    } else if interruptedForPause || self.isPaused {
                        self.activeDownloads[index].state = self.isPaused ? .paused : .queued
                        self.activeDownloads[index].message = self.isPaused
                            ? String(localized: "downloads.queue.paused.message")
                            : nil
                        SourceDebugTrace.log(
                            "Downloads",
                            "PAUSE_INTERRUPT id=\(item.id) requeued=\(!self.isPaused)"
                        )
                    } else {
                        self.activeDownloads[index].state = .queued
                        self.activeDownloads[index].message = nil
                        SourceDebugTrace.log("Downloads", "INTERRUPTED id=\(item.id) requeued=true")
                    }

                    self.schedulePersist()
                    self.pumpQueue()
                }
            } else {
                SourceDebugTrace.log("Downloads", "FAILED id=\(item.id) error=\(String(describing: error))")
                finishWithFailure(id: item.id, message: String(localized: "downloads.queue.failed.message"))
            }
        }
    }

    private func updateProgress(id: String, progress: Double) {
        runOnMain { [weak self] in
            guard let self,
                  let index = self.activeDownloads.firstIndex(where: { $0.id == id }),
                  self.activeDownloads[index].state == .running
            else {
                return
            }

            self.activeDownloads[index].progress = min(max(progress, 0), 1)
            self.schedulePersist()
        }
    }

    private func finishWithFailure(id: String, message: String) {
        runOnMain { [weak self] in
            guard let self,
                  let index = self.activeDownloads.firstIndex(where: { $0.id == id })
            else {
                return
            }

            self.activeDownloads[index].state = .failed
            self.activeDownloads[index].message = message
            self.schedulePersist()
            self.pumpQueue()
        }
    }

    private func schedulePersist() {
        dispatchPrecondition(condition: .onQueue(.main))
        persistWorkItem?.cancel()

        let snapshot = PersistedQueue(items: activeDownloads, isPaused: isPaused)
        let workItem = DispatchWorkItem {
            Self.persist(snapshot)
        }
        persistWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private static func loadPersistedQueue() -> PersistedQueue {
        guard let url = try? queueFileURL(),
              let data = try? Data(contentsOf: url),
              let queue = try? JSONDecoder().decode(PersistedQueue.self, from: data)
        else {
            return PersistedQueue(items: [], isPaused: false)
        }

        return queue
    }

    private static func persist(_ queue: PersistedQueue) {
        guard let url = try? queueFileURL(),
              let data = try? JSONEncoder().encode(queue)
        else {
            return
        }

        try? data.write(to: url, options: .atomic)
    }

    private static func queueFileURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Yomuhon", isDirectory: true)
        .appendingPathComponent("DownloadQueue", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("queue-v1.json")
    }

    private var executingCount: Int {
        executionLock.lock()
        defer { executionLock.unlock() }
        return executingIDs.count
    }

    private func markExecuting(_ id: String) {
        executionLock.lock()
        executingIDs.insert(id)
        executionLock.unlock()
    }

    private func markExecutionFinished(_ id: String) {
        executionLock.lock()
        executingIDs.remove(id)
        executionLock.unlock()
    }

    private func isExecuting(id: String) -> Bool {
        executionLock.lock()
        defer { executionLock.unlock() }
        return executingIDs.contains(id)
    }

    private func setPauseFlag(_ paused: Bool) {
        pauseStateLock.lock()
        pauseFlag = paused
        pauseStateLock.unlock()
    }

    private var isPauseRequested: Bool {
        pauseStateLock.lock()
        defer { pauseStateLock.unlock() }
        return pauseFlag
    }

    private func shouldInterruptDownload(id: String) -> Bool {
        isCancelled(id: id) || isPauseRequested
    }

    private func registerActiveRequestToken(_ token: RequestCancellationToken, id: String) {
        activeRequestTokenLock.lock()
        activeRequestTokens[id] = token
        activeRequestTokenLock.unlock()
    }

    private func unregisterActiveRequestToken(id: String, token: RequestCancellationToken) {
        activeRequestTokenLock.lock()
        if activeRequestTokens[id] === token {
            activeRequestTokens.removeValue(forKey: id)
        }
        activeRequestTokenLock.unlock()
    }

    private func cancelActiveRequestToken(id: String) {
        activeRequestTokenLock.lock()
        let token = activeRequestTokens[id]
        activeRequestTokenLock.unlock()
        token?.cancel()
    }

    private func cancelAllActiveRequestTokens() {
        activeRequestTokenLock.lock()
        let tokens = Array(activeRequestTokens.values)
        activeRequestTokenLock.unlock()
        tokens.forEach { $0.cancel() }
    }

    private func interruptActiveRequestsForPause() {
        activeRequestTokenLock.lock()
        let tokens = activeRequestTokens
        activeRequestTokenLock.unlock()

        pauseInterruptionLock.lock()
        pauseInterruptedIDs.formUnion(tokens.keys)
        pauseInterruptionLock.unlock()

        for (id, token) in tokens {
            SourceDebugTrace.log("Downloads", "PAUSE cancelling in-flight request id=\(id)")
            token.cancel()
        }
    }

    private func consumePauseInterruption(id: String) -> Bool {
        pauseInterruptionLock.lock()
        let contained = pauseInterruptedIDs.remove(id) != nil
        pauseInterruptionLock.unlock()
        return contained
    }

    private func pauseInterruptedIDsSafelyRemove(_ id: String) {
        pauseInterruptionLock.lock()
        pauseInterruptedIDs.remove(id)
        pauseInterruptionLock.unlock()
    }

    private func isDownloadCancellation(_ error: Error) -> Bool {
        if case DownloadRepositoryError.cancelled = error {
            return true
        }

        if let clientError = error as? HTTPClientError {
            return clientError.isCancellation
        }

        if let urlError = error as? URLError {
            return urlError.code == .cancelled
        }

        return error is CancellationError
    }

    private func cancelledIDsSafelyRemove(_ id: String) {
        cancellationLock.lock()
        cancelledIDs.remove(id)
        cancellationLock.unlock()
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}



struct DownloadsView: View {
    @ObservedObject var viewModel: LibraryViewModel
    let compositionRoot: PresentationCompositionRoot
    var onOpenMangaDetail: ((MangaDetailViewModel) -> Void)? = nil

    @Environment(\.yomuhonTheme) private var theme
    @StateObject private var downloadCenter = DownloadCenter.shared
    @State private var deletingDownloadID: String?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: YomuhonSpacing.extraLarge) {
                    header(width: proxy.size.width)

                    if !downloadCenter.activeDownloads.isEmpty {
                        downloadQueueSection(width: proxy.size.width)
                    }

                    if downloadedItems.isEmpty {
                        emptyState(width: proxy.size.width)
                    } else {
                        downloadedShelf(width: proxy.size.width)
                        downloadsList(width: proxy.size.width)
                    }

                    storageCard
                }
                .padding(.horizontal, contentPadding(for: proxy.size.width))
                .padding(.top, proxy.size.width > 760 ? YomuhonSpacing.extraLarge : YomuhonSpacing.large)
                .padding(.bottom, YomuhonSpacing.grand)
                .frame(maxWidth: 1040, alignment: .leading)
            }
        }
        .background(theme.background)
        .navigationTitle("Yomuhon")
        .onAppear { viewModel.loadLibrary() }
    }

    private func header(width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: YomuhonSpacing.extraLarge) {
            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                Text("downloads.title")
                    .font(YomuhonTypography.largeTitle)
                    .foregroundColor(theme.textPrimary)

                Text(downloadSummary)
                    .font(YomuhonTypography.body)
                    .foregroundColor(theme.textSecondary)
            }

            Spacer()

            if width > 760 {
                Text("downloads.offlineReading")
                    .font(YomuhonTypography.captionMedium)
                    .foregroundColor(theme.textSecondary)
                    .padding(.horizontal, YomuhonSpacing.medium)
                    .padding(.vertical, 9)
                    .background(theme.secondaryBackground.opacity(0.72))
                    .clipShape(Capsule())
            }
        }
    }

    private func downloadedShelf(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text("downloads.availableOffline")
                    .font(YomuhonTypography.title)
                    .foregroundColor(theme.textPrimary)

                Spacer()

                if !downloadedMangas.isEmpty {
                    Button {
                        deleteAllDownloads()
                    } label: {
                        Label("downloads.deleteAll", systemImage: "trash")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .font(YomuhonTypography.captionMedium)
                    .foregroundColor(theme.textSecondary)
                }

                Text(String.localizedStringWithFormat(NSLocalizedString("search.results.summary", comment: ""), downloadedMangas.count))
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: YomuhonSpacing.large) {
                    ForEach(downloadedMangas) { manga in
                        downloadTrigger(for: manga) {
                            DownloadedCoverCard(
                                manga: manga,
                                onDelete: { deleteDownloadedManga(manga) }
                            )
                        }
                    }
                }
                .padding(.vertical, YomuhonSpacing.small)
            }
        }
    }

    private func downloadsList(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text("detail.chapters")
                    .font(YomuhonTypography.title)
                    .foregroundColor(theme.textPrimary)

                Spacer()

                Text(String.localizedStringWithFormat(NSLocalizedString("downloads.summary", comment: ""), downloadedItems.count, downloadedMangas.count))
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
            }

            LazyVStack(spacing: 0) {
                ForEach(downloadedItems) { item in
                    downloadTrigger(for: item.manga) {
                        DownloadItemRow(
                            item: item,
                            isCompact: width < 720,
                            isDeleting: deletingDownloadID == item.id,
                            onDelete: { deleteDownloadedChapter(item) }
                        )
                    }

                    if item.id != downloadedItems.last?.id {
                        Divider()
                            .padding(.leading, width < 720 ? 76 : 96)
                    }
                }
            }
            .background(theme.card.opacity(theme.id == .ink ? 0.46 : 1.0))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(theme.separator.opacity(0.58), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }


    private func downloadQueueSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("downloads.queue.title")
                        .font(YomuhonTypography.title)
                        .foregroundColor(theme.textPrimary)

                    Text(queueSummary)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                }

                Spacer()

                HStack(spacing: YomuhonSpacing.small) {
                    if downloadCenter.failedCount > 0 {
                        Text(String.localizedStringWithFormat(
                            NSLocalizedString("downloads.queue.failedCount", comment: ""),
                            downloadCenter.failedCount
                        ))
                        .font(YomuhonTypography.captionMedium)
                        .foregroundColor(theme.textSecondary)
                        .padding(.horizontal, YomuhonSpacing.small)
                        .padding(.vertical, 5)
                        .background(theme.secondaryBackground.opacity(0.72))
                        .clipShape(Capsule())
                    }

                    Button {
                        downloadCenter.isPaused ? downloadCenter.resumeAll() : downloadCenter.pauseAll()
                    } label: {
                        Label(
                            downloadCenter.isPaused ? "downloads.queue.resume" : "downloads.queue.pause",
                            systemImage: downloadCenter.isPaused ? "play.fill" : "pause.fill"
                        )
                    }
                    .buttonStyle(YomuhonSecondaryButtonStyle(theme: theme))
                }
            }

            LazyVStack(spacing: 0) {
                ForEach(downloadCenter.activeDownloads) { item in
                    ActiveDownloadRow(
                        item: item,
                        isCompact: width < 720,
                        onCancel: { downloadCenter.cancel(id: item.id) },
                        onRetry: { downloadCenter.retry(id: item.id) },
                        onClear: { downloadCenter.clearFailed(id: item.id) }
                    )

                    if item.id != downloadCenter.activeDownloads.last?.id {
                        Divider()
                            .padding(.leading, width < 720 ? 76 : 96)
                    }
                }
            }
            .background(theme.card.opacity(theme.id == .ink ? 0.46 : 1.0))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(theme.separator.opacity(0.58), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func emptyState(width: CGFloat) -> some View {
        VStack(spacing: YomuhonSpacing.medium) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(theme.textSecondary.opacity(0.42))

            Text("downloads.empty.title")
                .font(YomuhonTypography.title)
                .foregroundColor(theme.textPrimary)

            Text("downloads.empty.message")
                .font(YomuhonTypography.body)
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, minHeight: width > 760 ? 360 : 280)
        .background(theme.card.opacity(theme.id == .ink ? 0.42 : 1.0))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.58), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("downloads.storage")
                        .font(YomuhonTypography.headline)
                        .foregroundColor(theme.textPrimary)

                    Text(storageMessage)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                }

                Spacer()

                Text("downloads.storage.local")
                    .font(YomuhonTypography.captionMedium)
                    .foregroundColor(theme.textSecondary)
                    .padding(.horizontal, YomuhonSpacing.small)
                    .padding(.vertical, 5)
                    .background(theme.secondaryBackground.opacity(0.72))
                    .clipShape(Capsule())
            }

            YomuhonProgressBar(value: deviceStorageProgress)

            HStack {
                Label(freeStorageText, systemImage: "internaldrive")
                Spacer()
                Text(downloadedItemsStorageSummary)
            }
            .font(YomuhonTypography.captionMedium)
            .foregroundColor(theme.textSecondary)
        }
        .padding(YomuhonSpacing.large)
        .background(theme.card.opacity(theme.id == .ink ? 0.46 : 1.0))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.58), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func downloadTrigger<Content: View>(
        for manga: Manga,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let detailViewModel = compositionRoot.makeMangaDetailViewModel(
            manga: manga,
            progress: viewModel.progressByMangaID[manga.id]
        )

        if let onOpenMangaDetail {
            Button {
                onOpenMangaDetail(detailViewModel)
            } label: {
                content()
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(destination: MangaDetailView(viewModel: detailViewModel)) {
                content()
            }
            .buttonStyle(.plain)
        }
    }


    private func deleteDownloadedChapter(_ item: DownloadedChapterItem) {
        guard deletingDownloadID == nil else {
            return
        }

        deletingDownloadID = item.id
        let useCase = compositionRoot.makeDownloadChapterUseCase()

        DispatchQueue.global(qos: .utility).async {
            let result = Result {
                try useCase.deleteDownloadedChapter(item.chapter, manga: item.manga)
            }

            DispatchQueue.main.async {
                switch result {
                case .success:
                    viewModel.loadLibrary()
                case .failure:
                    break
                }

                deletingDownloadID = nil
            }
        }
    }

    private func deleteDownloadedManga(_ manga: Manga) {
        guard deletingDownloadID == nil else {
            return
        }

        deletingDownloadID = manga.id
        let useCase = compositionRoot.makeDownloadChapterUseCase()

        DispatchQueue.global(qos: .utility).async {
            let result = Result {
                try useCase.deleteDownloadedManga(manga)
            }

            DispatchQueue.main.async {
                switch result {
                case .success:
                    viewModel.loadLibrary()
                case .failure:
                    break
                }

                deletingDownloadID = nil
            }
        }
    }

    private func deleteAllDownloads() {
        guard deletingDownloadID == nil else {
            return
        }

        deletingDownloadID = "all"
        let useCase = compositionRoot.makeDownloadChapterUseCase()
        let mangas = downloadedMangas

        DispatchQueue.global(qos: .utility).async {
            for manga in mangas {
                _ = try? useCase.deleteDownloadedManga(manga)
            }

            DispatchQueue.main.async {
                viewModel.loadLibrary()
                deletingDownloadID = nil
            }
        }
    }

    private func contentPadding(for width: CGFloat) -> CGFloat {
        if width >= 1180 {
            return YomuhonSpacing.grand
        }

        return width >= 720 ? YomuhonSpacing.extraLarge : YomuhonSpacing.large
    }


    private var queueSummary: String {
        String.localizedStringWithFormat(
            NSLocalizedString("downloads.queue.summary", comment: ""),
            downloadCenter.runningCount,
            downloadCenter.queuedCount,
            downloadCenter.failedCount
        )
    }

    private var deviceStorageProgress: Double {
        guard let storage = deviceStorage, storage.total > 0 else {
            return storageProgress
        }

        return min(1, max(0, Double(storage.total - storage.available) / Double(storage.total)))
    }

    private var storageProgress: Double {
        guard totalChapterCount > 0 else {
            return 0
        }

        return min(1, Double(downloadedItems.count) / Double(totalChapterCount))
    }

    private var storageMessage: String {
        guard let storage = deviceStorage else {
            return NSLocalizedString("downloads.storage.message", comment: "")
        }

        return String.localizedStringWithFormat(
            NSLocalizedString("downloads.storage.deviceMessage", comment: ""),
            ByteCountFormatter.string(fromByteCount: storage.available, countStyle: .file),
            ByteCountFormatter.string(fromByteCount: storage.total, countStyle: .file)
        )
    }

    private var freeStorageText: String {
        guard let storage = deviceStorage else {
            return NSLocalizedString("downloads.storage.unknown", comment: "")
        }

        return String.localizedStringWithFormat(
            NSLocalizedString("downloads.storage.freeFormat", comment: ""),
            ByteCountFormatter.string(fromByteCount: storage.available, countStyle: .file)
        )
    }

    private var downloadedItemsStorageSummary: String {
        String.localizedStringWithFormat(
            NSLocalizedString("downloads.storage.downloadedSummary", comment: ""),
            downloadedItems.count
        )
    }

    private var deviceStorage: DeviceStorageInfo? {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let values = try? url.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey
              ]),
              let available = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity
        else {
            return nil
        }

        return DeviceStorageInfo(available: Int64(available), total: Int64(total))
    }

    private var totalChapterCount: Int {
        viewModel.mangas.reduce(0) { partialResult, manga in
            partialResult + manga.chapters.count
        }
    }

    private var downloadedMangas: [Manga] {
        var seen = Set<String>()
        return downloadedItems.compactMap { item in
            guard seen.insert(item.manga.id).inserted else {
                return nil
            }

            return item.manga
        }
    }

    private var downloadedItems: [DownloadedChapterItem] {
        let items = viewModel.mangas.flatMap { manga in
            manga.chapters
                .filter { $0.isDownloaded }
                .sorted { $0.number < $1.number }
                .map { chapter in
                    DownloadedChapterItem(manga: manga, chapter: chapter)
                }
        }

        return items.sorted { lhs, rhs in
            if lhs.manga.title == rhs.manga.title {
                return lhs.chapter.number < rhs.chapter.number
            }

            return lhs.manga.title < rhs.manga.title
        }
    }

    private var downloadSummary: String {
        String.localizedStringWithFormat(
            NSLocalizedString("downloads.summary", comment: ""),
            downloadedItems.count,
            Set(downloadedItems.map(\.manga.id)).count
        )
    }
}

private struct DeviceStorageInfo {
    let available: Int64
    let total: Int64
}

private struct DownloadedChapterItem: Identifiable {
    let manga: Manga
    let chapter: Chapter

    var id: String {
        "\(manga.id)-\(chapter.id)"
    }

    var progress: Double {
        guard !manga.chapters.isEmpty else {
            return 0
        }

        return Double(manga.chapters.filter(\.isDownloaded).count) / Double(manga.chapters.count)
    }
}

private struct DownloadedCoverCard: View {
    let manga: Manga
    let onDelete: () -> Void

    @Environment(\.yomuhonTheme) private var theme
    @StateObject private var downloadCenter = DownloadCenter.shared
    @State private var deletingDownloadID: String?
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
            CoverView(title: manga.title, imageURL: manga.coverURL, cornerRadius: 14)
                .frame(width: 122, height: 176)
                .shadow(color: theme.shadow.opacity(isHovering ? 0.75 : 0.42), radius: isHovering ? 12 : 7, x: 0, y: isHovering ? 7 : 4)

            Text(manga.title)
                .font(YomuhonTypography.captionMedium)
                .foregroundColor(theme.textPrimary)
                .lineLimit(2)
                .frame(width: 122, alignment: .leading)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("downloads.deleteManga", systemImage: "trash")
            }
        }
        .scaleEffect(isHovering ? 1.006 : 1)
        .animation(theme.animation, value: isHovering)
        .onHover { isHovering = $0 }
    }
}


private struct ActiveDownloadRow: View {
    let item: ActiveDownloadItem
    let isCompact: Bool
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onClear: () -> Void

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        HStack(spacing: YomuhonSpacing.medium) {
            CoverView(title: item.mangaTitle, imageURL: item.coverURL, cornerRadius: 10)
                .frame(width: isCompact ? 54 : 66, height: isCompact ? 76 : 92)
                .clipped()

            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                HStack(spacing: YomuhonSpacing.small) {
                    Text(item.mangaTitle)
                        .font(YomuhonTypography.calloutSemibold)
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)

                    Label(item.state.titleKey, systemImage: item.state.systemImage)
                        .font(YomuhonTypography.captionMedium)
                        .foregroundColor(theme.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(theme.secondaryBackground.opacity(0.72))
                        .clipShape(Capsule())
                }

                Text(item.chapterTitle)
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)

                if let message = item.message {
                    Text(message)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                }

                HStack(spacing: YomuhonSpacing.small) {
                    YomuhonProgressBar(value: item.progress)
                        .frame(maxWidth: isCompact ? 180 : 280)

                    Text(String.localizedStringWithFormat(
                        NSLocalizedString("common.percentFormat", comment: ""),
                        Int(item.progress * 100)
                    ))
                    .font(YomuhonTypography.captionMedium)
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 44, alignment: .trailing)
                }
            }

            Spacer()

            if item.canCancel {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(YomuhonTypography.captionMedium)
                        .foregroundColor(theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(theme.secondaryBackground.opacity(0.72))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            } else if item.canRetry {
                HStack(spacing: 6) {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise")
                            .font(YomuhonTypography.captionMedium)
                            .foregroundColor(theme.textPrimary)
                            .frame(width: 30, height: 30)
                            .background(theme.secondaryBackground.opacity(0.72))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button(action: onClear) {
                        Image(systemName: "trash")
                            .font(YomuhonTypography.captionMedium)
                            .foregroundColor(theme.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(theme.secondaryBackground.opacity(0.72))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ProgressView()
                    .scaleEffect(0.72)
            }
        }
        .padding(isCompact ? YomuhonSpacing.medium : YomuhonSpacing.large)
    }
}

private struct DownloadItemRow: View {
    let item: DownloadedChapterItem
    let isCompact: Bool
    let isDeleting: Bool
    let onDelete: () -> Void

    @Environment(\.yomuhonTheme) private var theme
    @StateObject private var downloadCenter = DownloadCenter.shared
    @State private var deletingDownloadID: String?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: YomuhonSpacing.medium) {
            CoverView(title: item.manga.title, imageURL: item.manga.coverURL, cornerRadius: 10)
                .frame(width: isCompact ? 54 : 66, height: isCompact ? 76 : 92)

            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                Text(item.manga.title)
                    .font(YomuhonTypography.calloutSemibold)
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)

                Text(item.chapter.displayTitle)
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)

                YomuhonProgressBar(value: item.progress)
                    .frame(maxWidth: isCompact ? 180 : 280)
            }

            Spacer()

            if isDeleting {
                ProgressView()
                    .scaleEffect(0.72)
            } else {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(YomuhonTypography.captionMedium)
                        .foregroundColor(theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(theme.secondaryBackground.opacity(0.72))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Image(systemName: "chevron.right")
                .font(YomuhonTypography.captionMedium)
                .foregroundColor(theme.textSecondary.opacity(0.62))
        }
        .padding(isCompact ? YomuhonSpacing.medium : YomuhonSpacing.large)
        .contentShape(Rectangle())
        .background(isHovering ? theme.secondaryBackground.opacity(0.34) : Color.clear)
        .onHover { isHovering = $0 }
        .animation(theme.animation, value: isHovering)
    }
}
