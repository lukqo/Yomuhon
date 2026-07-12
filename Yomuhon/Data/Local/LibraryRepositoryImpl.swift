//
//  LibraryRepositoryImpl.swift
//  Yomuhon
//

import CoreData
import Foundation

struct LibraryRepositoryImpl: LibraryRepository {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        self.context = context
        resetLegacyCacheIfNeeded()
        removeLegacyPreviewContentIfNeeded()
    }

    func fetchLibrary() -> [Manga] {
        fetchManagedObjects(entityName: "CDManga", sortKey: "title")
            .compactMap(Manga.init(managedObject:))
            .filter { !Self.isLegacyPreviewManga($0) }
    }

    func fetchReadingProgress() -> [ReadingProgress] {
        let validMangaIDs = Set(fetchLibrary().map { $0.id })

        return fetchManagedObjects(entityName: "CDReadingProgress", sortKey: "lastReadAt")
            .compactMap(ReadingProgress.init(managedObject:))
            .filter { validMangaIDs.contains($0.mangaID) }
    }

    func saveManga(_ manga: Manga) {
        let object = fetchManagedObject(entityName: "CDManga", id: manga.id)
            ?? NSEntityDescription.insertNewObject(forEntityName: "CDManga", into: context)
        object.apply(manga)
        saveContext()
    }

    func saveReadingProgress(_ progress: ReadingProgress) {
        let object = fetchManagedObject(entityName: "CDReadingProgress", id: progress.id)
            ?? NSEntityDescription.insertNewObject(forEntityName: "CDReadingProgress", into: context)
        object.apply(progress)
        saveContext()
    }

    func deleteManga(id: String) {
        if let object = fetchManagedObject(entityName: "CDManga", id: id) {
            context.delete(object)
        }

        deleteReadingProgress(mangaID: id)
        saveContext()
    }

    func deleteReadingProgress(mangaID: String) {
        fetchManagedObjects(entityName: "CDReadingProgress", sortKey: "lastReadAt")
            .filter { object in
                (object.value(forKey: "mangaID") as? String) == mangaID
            }
            .forEach(context.delete)

        saveContext()
    }

    private func resetLegacyCacheIfNeeded() {
        let resetKey = "yomuhon.cacheReset.releasePolish.v3"

        guard !UserDefaults.standard.bool(forKey: resetKey) else {
            return
        }

        fetchManagedObjects(entityName: "CDManga", sortKey: "title")
            .forEach(context.delete)

        fetchManagedObjects(entityName: "CDReadingProgress", sortKey: "lastReadAt")
            .forEach(context.delete)

        saveContext()
        UserDefaults.standard.set(true, forKey: resetKey)
    }

    private func removeLegacyPreviewContentIfNeeded() {
        let legacyMangaObjects = fetchManagedObjects(entityName: "CDManga", sortKey: "title").filter { object in
            let sourceID = object.value(forKey: "sourceID") as? String
            let id = object.value(forKey: "id") as? String
            return Self.isLegacyPreviewSourceID(sourceID)
                || Self.legacyPreviewMangaIDs.contains(id ?? "")
        }

        let legacyMangaIDs = Set(legacyMangaObjects.compactMap { $0.value(forKey: "id") as? String })

        legacyMangaObjects.forEach(context.delete)

        fetchManagedObjects(entityName: "CDReadingProgress", sortKey: "lastReadAt")
            .filter { object in
                let sourceID = object.value(forKey: "sourceID") as? String
                let mangaID = object.value(forKey: "mangaID") as? String
                return Self.isLegacyPreviewSourceID(sourceID)
                    || legacyMangaIDs.contains(mangaID ?? "")
                    || Self.legacyPreviewMangaIDs.contains(mangaID ?? "")
            }
            .forEach(context.delete)

        saveContext()
    }

    private func fetchManagedObjects(entityName: String, sortKey: String) -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.sortDescriptors = [NSSortDescriptor(key: sortKey, ascending: true)]

        do {
            return try context.fetch(request)
        } catch {
            return []
        }
    }

    private func fetchManagedObject(entityName: String, id: String) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1

        do {
            return try context.fetch(request).first
        } catch {
            return nil
        }
    }

    private static let legacyPreviewMangaIDs: Set<String> = [
        "blue-period",
        "witch-hat",
        "frieren",
        "yotsuba"
    ]

    private static func isLegacyPreviewManga(_ manga: Manga) -> Bool {
        isLegacyPreviewSourceID(manga.sourceID) || legacyPreviewMangaIDs.contains(manga.id)
    }

    private static func isLegacyPreviewSourceID(_ sourceID: String?) -> Bool {
        guard let sourceID else {
            return false
        }

        return sourceID == "offline.demo"
            || sourceID == "local.preview"
            || sourceID == "source.preview"
    }

    private func saveContext() {
        guard context.hasChanges else {
            return
        }

        do {
            try context.save()
        } catch {
            context.rollback()
        }
    }
}

private struct StoredMangaPayload: Codable {
    let chapters: [Chapter]
    let alternativeTitles: [String]?
    let author: String?
    let releaseYear: Int?
}

private extension Manga {
    init?(managedObject: NSManagedObject) {
        guard
            let id = managedObject.value(forKey: "id") as? String,
            let sourceID = managedObject.value(forKey: "sourceID") as? String,
            let title = managedObject.value(forKey: "title") as? String
        else {
            return nil
        }

        let coverURLString = managedObject.value(forKey: "coverURLString") as? String
        let synopsis = managedObject.value(forKey: "synopsis") as? String
        let chaptersData = managedObject.value(forKey: "chaptersData") as? Data
        let storedPayload = chaptersData.flatMap {
            try? JSONDecoder().decode(StoredMangaPayload.self, from: $0)
        }
        let chapters = storedPayload?.chapters
            ?? chaptersData.flatMap { try? JSONDecoder().decode([Chapter].self, from: $0) }
            ?? []

        self.init(
            id: id,
            sourceID: sourceID,
            title: title.deduplicatedMangaTitle,
            coverURL: coverURLString.flatMap(URL.init(string:)),
            synopsis: synopsis,
            alternativeTitles: storedPayload?.alternativeTitles,
            author: storedPayload?.author,
            releaseYear: storedPayload?.releaseYear,
            chapters: chapters
        )
    }
}

private extension ReadingProgress {
    init?(managedObject: NSManagedObject) {
        guard
            let id = managedObject.value(forKey: "id") as? String,
            let mangaID = managedObject.value(forKey: "mangaID") as? String,
            let sourceID = managedObject.value(forKey: "sourceID") as? String,
            let currentChapterID = managedObject.value(forKey: "currentChapterID") as? String,
            let statusRawValue = managedObject.value(forKey: "status") as? String,
            let status = ReadingStatus(rawValue: statusRawValue)
        else {
            return nil
        }

        self.init(
            id: id,
            mangaID: mangaID,
            sourceID: sourceID,
            currentChapterID: currentChapterID,
            currentPage: Int(managedObject.value(forKey: "currentPage") as? Int32 ?? 0),
            lastReadAt: managedObject.value(forKey: "lastReadAt") as? Date ?? Date(),
            status: status
        )
    }
}

private extension NSManagedObject {
    func apply(_ manga: Manga) {
        setValue(manga.id, forKey: "id")
        setValue(manga.sourceID, forKey: "sourceID")
        setValue(manga.title, forKey: "title")
        setValue(manga.coverURL?.absoluteString, forKey: "coverURLString")
        setValue(manga.synopsis, forKey: "synopsis")
        let payload = StoredMangaPayload(
            chapters: manga.chapters,
            alternativeTitles: manga.alternativeTitles,
            author: manga.author,
            releaseYear: manga.releaseYear
        )
        setValue(try? JSONEncoder().encode(payload), forKey: "chaptersData")
    }

    func apply(_ progress: ReadingProgress) {
        setValue(progress.id, forKey: "id")
        setValue(progress.mangaID, forKey: "mangaID")
        setValue(progress.sourceID, forKey: "sourceID")
        setValue(progress.currentChapterID, forKey: "currentChapterID")
        setValue(Int32(progress.currentPage), forKey: "currentPage")
        setValue(progress.lastReadAt, forKey: "lastReadAt")
        setValue(progress.status.rawValue, forKey: "status")
    }
}


private extension String {
    var deduplicatedMangaTitle: String {
        let cleaned = replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.split(separator: " ").map(String.init)

        guard parts.count.isMultiple(of: 2), !parts.isEmpty else {
            return cleaned
        }

        let midpoint = parts.count / 2
        let left = parts[..<midpoint].joined(separator: " ")
        let right = parts[midpoint...].joined(separator: " ")

        return left.caseInsensitiveCompare(right) == .orderedSame ? left : cleaned
    }
}
