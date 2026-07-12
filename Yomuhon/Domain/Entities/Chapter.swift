//
//  Chapter.swift
//  Yomuhon
//

import Foundation

struct Chapter: Identifiable, Hashable, Codable {
    let id: String
    let mangaID: String
    let number: Double
    let title: String?
    var pages: [Page]
    var isDownloaded: Bool
}

extension Chapter {
    var cleanTitle: String? {
        let cleanTitle = title?
            .removingYomuhonSourceMarkers

        return cleanTitle?.isEmpty == false ? cleanTitle : nil
    }

    var cleanTitleOrDisplayTitle: String {
        cleanTitle ?? displayTitle
    }

    var displayTitle: String {
        let fallback = String.localizedStringWithFormat(
            NSLocalizedString("chapter.displayTitle", comment: ""),
            formattedNumber
        )

        guard let cleanTitle = title?.removingYomuhonSourceMarkers,
              !cleanTitle.isEmpty
        else {
            return fallback
        }

        return cleanTitle
    }

    var formattedNumber: String {
        number.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(number))
            : String(number)
    }
}


extension Chapter {
    var crossSourceDownloadDeduplicationKey: String {
        downloadDeduplicationKey
    }

    var downloadDeduplicationKey: String {
        if number > 0 {
            return "number:\(formattedNumber)"
        }

        if let cleanTitle {
            let normalizedTitle = cleanTitle
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !normalizedTitle.isEmpty {
                return "title:\(normalizedTitle)"
            }
        }

        return "id:\(id)"
    }
}
