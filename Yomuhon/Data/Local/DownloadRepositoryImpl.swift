//
//  DownloadRepositoryImpl.swift
//  Yomuhon
//

import Foundation

struct DownloadRepositoryImpl: DownloadRepository {
    private let httpClient: HTTPClient
    private let fileManager: FileManager

    init(httpClient: HTTPClient = HTTPClient(), fileManager: FileManager = .default) {
        self.httpClient = httpClient
        self.fileManager = fileManager
    }

    func downloadChapter(_ chapter: Chapter, from manga: Manga, progressHandler: ((Double) -> Void)? = nil, shouldCancel: (() -> Bool)? = nil) throws -> Chapter {
        let chapterDirectory = try directory(for: manga, chapter: chapter)
        var downloadedChapter = chapter

        var downloadedPages: [Page] = []

        let totalPages = max(chapter.pages.count, 1)

        for (downloadIndex, page) in chapter.pages.enumerated() {
            if shouldCancel?() == true {
                throw DownloadRepositoryError.cancelled
            }

            var downloadedPage = page
            let fileURL = chapterDirectory.appendingPathComponent("page-\(page.index + 1).img")

            let data: Data
            let reusedPartialPage: Bool
            if fileManager.fileExists(atPath: fileURL.path),
               let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let fileSize = attributes[.size] as? NSNumber,
               fileSize.int64Value > 0 {
                data = try Data(contentsOf: fileURL)
                reusedPartialPage = true
                SourceDebugTrace.log(
                    "Downloads",
                    "REUSE chapter=\(chapter.id) page=\(page.index + 1) bytes=\(data.count)"
                )
            } else if let localFileURL = page.localFileURL,
                      fileManager.fileExists(atPath: localFileURL.path) {
                data = try Data(contentsOf: localFileURL)
                reusedPartialPage = localFileURL == fileURL
            } else if let imageURL = page.imageURL {
                data = try imageData(
                    from: imageURL,
                    sourceID: manga.sourceID,
                    refererURL: chapter.declarativeSourceURL ?? manga.declarativeSourceURL
                )
                reusedPartialPage = false
            } else {
                throw DownloadRepositoryError.missingPageImage
            }

            // A queue pause cancels the in-flight HTTP request. If cancellation
            // races with a completed response, do not write or advance progress
            // after the user has already paused the queue.
            if shouldCancel?() == true {
                throw DownloadRepositoryError.cancelled
            }

            if !reusedPartialPage {
                try data.write(to: fileURL, options: .atomic)
            }

            // It is safe to leave an atomically written page on disk when pause
            // arrives here. Resume will reuse the deterministic page-N file and
            // continue without downloading that page twice.
            if shouldCancel?() == true {
                throw DownloadRepositoryError.cancelled
            }

            downloadedPage.localFileURL = fileURL
            downloadedPages.append(downloadedPage)
            progressHandler?(Double(downloadIndex + 1) / Double(totalPages))

            if shouldCancel?() == true {
                throw DownloadRepositoryError.cancelled
            }

            // Be gentle with sources while downloading a whole chapter.
            Thread.sleep(forTimeInterval: 0.18)
        }

        if shouldCancel?() == true {
            throw DownloadRepositoryError.cancelled
        }

        downloadedChapter.pages = downloadedPages
        downloadedChapter.isDownloaded = true
        return downloadedChapter
    }


    func deleteDownloadedChapter(_ chapter: Chapter, from manga: Manga) throws -> Manga {
        var updatedManga = manga
        let chapterDirectory = try directory(for: manga, chapter: chapter, create: false)

        if fileManager.fileExists(atPath: chapterDirectory.path) {
            try fileManager.removeItem(at: chapterDirectory)
        }

        guard let chapterIndex = updatedManga.chapters.firstIndex(where: { $0.id == chapter.id }) else {
            return updatedManga
        }

        updatedManga.chapters[chapterIndex].pages = updatedManga.chapters[chapterIndex].pages.map { page in
            var clearedPage = page
            clearedPage.localFileURL = nil
            return clearedPage
        }
        updatedManga.chapters[chapterIndex].isDownloaded = false

        return updatedManga
    }

    func deleteDownloadedManga(_ manga: Manga) throws -> Manga {
        var updatedManga = manga
        let mangaDirectory = try mangaDownloadDirectory(for: manga, create: false)

        if fileManager.fileExists(atPath: mangaDirectory.path) {
            try fileManager.removeItem(at: mangaDirectory)
        }

        updatedManga.chapters = updatedManga.chapters.map { chapter in
            var clearedChapter = chapter
            clearedChapter.pages = chapter.pages.map { page in
                var clearedPage = page
                clearedPage.localFileURL = nil
                return clearedPage
            }
            clearedChapter.isDownloaded = false
            return clearedChapter
        }

        return updatedManga
    }

    private func directory(for manga: Manga, chapter: Chapter, create: Bool = true) throws -> URL {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Yomuhon", isDirectory: true)
        .appendingPathComponent("Downloads", isDirectory: true)
        .appendingPathComponent(manga.sourceID, isDirectory: true)
        .appendingPathComponent(manga.id, isDirectory: true)
        .appendingPathComponent(chapter.id, isDirectory: true)

        if create {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    private func mangaDownloadDirectory(for manga: Manga, create: Bool = true) throws -> URL {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Yomuhon", isDirectory: true)
        .appendingPathComponent("Downloads", isDirectory: true)
        .appendingPathComponent(manga.sourceID, isDirectory: true)
        .appendingPathComponent(manga.id, isDirectory: true)

        if create {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }

        return root
    }

    private func imageData(from url: URL, sourceID: String, refererURL: URL?) throws -> Data {
        let cacheURL = try cacheFileURL(for: url)

        if fileManager.fileExists(atPath: cacheURL.path) {
            return try Data(contentsOf: cacheURL)
        }

        var lastError: Error?

        for referer in referers(for: url, sourceID: sourceID, refererURL: refererURL) {
            var request = URLRequest(url: url)

            if let config = DeclarativeRemoteConfigLoader.availableConfigs()
                .first(where: { $0.id.caseInsensitiveCompare(sourceID) == .orderedSame }) {
                for (key, value) in config.network?.headers ?? [:] {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }

            if request.value(forHTTPHeaderField: "Accept") == nil {
                request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            }
            if request.value(forHTTPHeaderField: "User-Agent") == nil {
                request.setValue("Mozilla/5.0 Yomuhon/1.0", forHTTPHeaderField: "User-Agent")
            }

            if let referer {
                request.setValue(referer, forHTTPHeaderField: "Referer")
            }

            do {
                let data = try httpClient.data(for: request)
                try? data.write(to: cacheURL, options: .atomic)
                return data
            } catch {
                lastError = error

                if let clientError = error as? HTTPClientError, clientError.isRateLimited {
                    throw error
                }
            }
        }

        throw lastError ?? DownloadRepositoryError.missingPageImage
    }

    private func referers(for url: URL, sourceID: String, refererURL: URL?) -> [String?] {
        var candidates: [String?] = []

        if let refererURL {
            candidates.append(refererURL.absoluteString)
            candidates.append(originString(for: refererURL))
        }

        if let config = DeclarativeRemoteConfigLoader.availableConfigs()
            .first(where: { $0.id.caseInsensitiveCompare(sourceID) == .orderedSame }) {
            let base = config.baseURL.absoluteString
            candidates.append(base.hasSuffix("/") ? base : base + "/")
        }

        candidates.append(originString(for: url))
        candidates.append(nil)

        var seen = Set<String>()
        return candidates.filter { value in
            guard let value else { return true }
            return seen.insert(value).inserted
        }
    }

    private func originString(for url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        guard let origin = components.url?.absoluteString else { return nil }
        return origin.hasSuffix("/") ? origin : origin + "/"
    }

    private func cacheFileURL(for url: URL) throws -> URL {
        let directory = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Yomuhon", isDirectory: true)
        .appendingPathComponent("ImageCache", isDirectory: true)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(url.absoluteString.stableCacheFileName)
    }
}

private extension String {
    var stableCacheFileName: String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

enum DownloadRepositoryError: Error {
    case missingPageImage
    case cancelled
}
