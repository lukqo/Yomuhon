//
//  LibraryViewModel.swift
//  Yomuhon
//

import Combine
import Foundation
import SwiftUI

final class LibraryViewModel: ObservableObject {
    @Published var mangas: [Manga] = []
    @Published var progress: [ReadingProgress] = []
    @Published var searchText = ""
    @Published var selectedCategory: LibraryCategory = .all
    @Published private(set) var manualShelfIDs: Set<String> = []

    private let getLibraryUseCase: GetLibraryUseCase
    private let metadataEnrichmentService: MangaMetadataEnrichmentService
    private var cancellables = Set<AnyCancellable>()

    init(
        getLibraryUseCase: GetLibraryUseCase,
        metadataEnrichmentService: MangaMetadataEnrichmentService = MangaMetadataEnrichmentService()
    ) {
        self.getLibraryUseCase = getLibraryUseCase
        self.metadataEnrichmentService = metadataEnrichmentService

        NotificationCenter.default.publisher(for: .yomuhonDownloadLibraryDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadLibrary()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .yomuhonLibraryDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadLibrary()
            }
            .store(in: &cancellables)

        loadLibrary()
    }

    var filteredMangas: [Manga] {
        applySearch(to: categoryMangas)
    }

    var visibleMangas: [Manga] {
        filteredMangas
    }

    var allLibraryMangas: [Manga] {
        deduplicated(
            shelfMangas + historyMangas + downloadedMangas
        )
        .sorted { lhs, rhs in
            let left = progressByMangaID[lhs.id]?.lastReadAt ?? .distantPast
            let right = progressByMangaID[rhs.id]?.lastReadAt ?? .distantPast
            if left != right { return left > right }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    var shelfMangas: [Manga] {
        mangas.filter { manualShelfIDs.contains($0.id) }
    }

    var historyMangas: [Manga] {
        let historyIDs = Set(progress.map(\.mangaID))
        return mangas
            .filter { historyIDs.contains($0.id) }
            .sorted { lhs, rhs in
                let left = progressByMangaID[lhs.id]?.lastReadAt ?? .distantPast
                let right = progressByMangaID[rhs.id]?.lastReadAt ?? .distantPast
                return left > right
            }
    }

    var readingMangas: [Manga] {
        historyMangas.filter { progressByMangaID[$0.id]?.status == .reading }
    }

    var completedMangas: [Manga] {
        historyMangas.filter { progressByMangaID[$0.id]?.status == .completed }
    }

    var planToReadMangas: [Manga] {
        deduplicated(shelfMangas + historyMangas)
            .filter { progressByMangaID[$0.id]?.status == .planToRead }
            .sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    var downloadedMangas: [Manga] {
        mangas.filter { manga in
            manga.chapters.contains(where: \.isDownloaded)
        }
    }

    var hasAnyVisibleContent: Bool {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return !visibleMangas.isEmpty
        }
        return !categoryMangas.isEmpty
    }

    var shelfCount: Int {
        shelfMangas.count
    }

    var historyCount: Int {
        historyMangas.count
    }

    var averageReadingProgress: Double {
        guard !readingMangas.isEmpty else { return 0 }
        let total = readingMangas.reduce(0.0) { $0 + readingProgress(for: $1) }
        return total / Double(readingMangas.count)
    }

    var completedOfflineCount: Int {
        completedMangas.filter { manga in
            manga.chapters.contains(where: \.isDownloaded)
        }.count
    }

    var planToReadChapterCount: Int {
        planToReadMangas.reduce(0) { result, manga in
            result + manga.chapters.count
        }
    }

    var progressByMangaID: [String: ReadingProgress] {
        Dictionary(uniqueKeysWithValues: progress.map { ($0.mangaID, $0) })
    }

    var downloadedChapterCount: Int {
        mangas.reduce(0) { result, manga in
            result + manga.chapters.filter(\.isDownloaded).count
        }
    }

    func categoryCount(_ category: LibraryCategory) -> Int {
        switch category {
        case .all:
            return allLibraryMangas.count
        case .reading:
            return readingMangas.count
        case .completed:
            return completedMangas.count
        case .planToRead:
            return planToReadMangas.count
        }
    }

    func readingProgress(for manga: Manga) -> Double {
        guard let readingProgress = progressByMangaID[manga.id],
              let chapterIndex = manga.chapters.firstIndex(where: { $0.id == readingProgress.currentChapterID }),
              !manga.chapters.isEmpty else {
            return 0
        }

        let chapterProgress = Double(chapterIndex) / Double(manga.chapters.count)
        let pageFraction: Double
        if let chapter = manga.chapters.first(where: { $0.id == readingProgress.currentChapterID }),
           !chapter.pages.isEmpty {
            pageFraction = (Double(readingProgress.currentPage) / Double(chapter.pages.count)) / Double(manga.chapters.count)
        } else {
            pageFraction = 0
        }

        return min(max(chapterProgress + pageFraction, 0), 1)
    }

    func loadLibrary() {
        let snapshot = getLibraryUseCase.execute()
        mangas = snapshot.mangas
        progress = snapshot.progress
        manualShelfIDs = LibraryMembershipStore.shared.ids
        repairMissingMetadataIfNeeded(snapshot.mangas)
    }

    private var categoryMangas: [Manga] {
        switch selectedCategory {
        case .all:
            return allLibraryMangas
        case .reading:
            return readingMangas
        case .completed:
            return completedMangas
        case .planToRead:
            return planToReadMangas
        }
    }

    private func applySearch(to mangas: [Manga]) -> [Manga] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return mangas
        }

        return mangas.filter { manga in
            manga.identityTitles.contains { $0.localizedCaseInsensitiveContains(query) }
                || manga.sourceID.localizedCaseInsensitiveContains(query)
                || (manga.synopsis?.localizedCaseInsensitiveContains(query) ?? false)
                || (manga.author?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func deduplicated(_ mangas: [Manga]) -> [Manga] {
        var seen = Set<String>()
        return mangas.filter { seen.insert($0.id).inserted }
    }

    private func repairMissingMetadataIfNeeded(_ mangas: [Manga]) {
        let candidates = mangas.filter { manga in
            manga.coverURL == nil || manga.cleanSynopsis == nil || manga.cleanSynopsis?.isEmpty == true
        }

        guard !candidates.isEmpty else {
            return
        }

        DispatchQueue.global(qos: .utility).async { [metadataEnrichmentService, getLibraryUseCase] in
            let enriched = metadataEnrichmentService.enrich(candidates)

            for manga in enriched where manga.coverURL != nil || manga.cleanSynopsis?.isEmpty == false {
                getLibraryUseCase.saveManga(manga)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                var current = self.mangas
                for manga in enriched {
                    guard let index = current.firstIndex(where: { $0.id == manga.id }) else {
                        continue
                    }

                    current[index] = manga
                }

                self.mangas = current
            }
        }
    }

    func deleteManga(_ manga: Manga) {
        LibraryMembershipStore.shared.remove(manga.id)
        getLibraryUseCase.deleteManga(manga)

        // Delete is only ever triggered from the long-press context menu, so
        // the card is still mid-way through the system's dismiss animation
        // when this fires. Removing it from `mangas` immediately (which
        // yanks the card out of the grid) fought with that animation and
        // produced a visible glitch on iPad. Give the dismiss a moment to
        // finish before the grid actually reflows.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            withAnimation(YomuhonMotion.relaxed) {
                self?.loadLibrary()
            }
        }
    }

    func removeFromShelf(_ manga: Manga) {
        LibraryMembershipStore.shared.remove(manga.id)
        manualShelfIDs = LibraryMembershipStore.shared.ids
    }
}

enum LibraryCategory: String, CaseIterable, Identifiable {
    case all
    case reading
    case completed
    case planToRead

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            return String(localized: "library.category.overview")
        case .reading:
            return String(localized: "readingStatus.reading")
        case .completed:
            return String(localized: "readingStatus.completed")
        case .planToRead:
            return String(localized: "readingStatus.planToRead")
        }
    }

    var iconName: String {
        switch self {
        case .all:
            return "rectangle.grid.2x2"
        case .reading:
            return "book"
        case .completed:
            return "checkmark.circle"
        case .planToRead:
            return "bookmark"
        }
    }

    var status: ReadingStatus? {
        switch self {
        case .all:
            return nil
        case .reading:
            return .reading
        case .completed:
            return .completed
        case .planToRead:
            return .planToRead
        }
    }
}
