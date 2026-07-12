//
//  ReadingProgress.swift
//  Yomuhon
//

import Foundation

struct ReadingProgress: Identifiable, Hashable, Codable {
    let id: String
    let mangaID: String
    let sourceID: String
    var currentChapterID: String
    var currentPage: Int
    var lastReadAt: Date
    var status: ReadingStatus
}

enum ReadingStatus: String, Codable, CaseIterable, Hashable {
    case planToRead
    case reading
    case completed

    var title: String {
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
