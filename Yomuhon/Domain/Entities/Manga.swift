//
//  Manga.swift
//  Yomuhon
//

import Foundation

struct Manga: Identifiable, Hashable, Codable {
    let id: String
    let sourceID: String
    let title: String
    let coverURL: URL?
    let synopsis: String?
    let alternativeTitles: [String]?
    let author: String?
    let releaseYear: Int?
    var chapters: [Chapter]

    init(
        id: String,
        sourceID: String,
        title: String,
        coverURL: URL?,
        synopsis: String?,
        alternativeTitles: [String]? = nil,
        author: String? = nil,
        releaseYear: Int? = nil,
        chapters: [Chapter]
    ) {
        self.id = id
        self.sourceID = sourceID
        self.title = title
        self.coverURL = coverURL
        self.synopsis = synopsis
        self.alternativeTitles = alternativeTitles
        self.author = author
        self.releaseYear = releaseYear
        self.chapters = chapters
    }
}


extension Manga {
    var cleanSynopsis: String? {
        synopsis?
            .removingYomuhonSourceMarkers
            .cleanedUserFacingSynopsis
    }

    var displaySynopsis: String {
        let cleaned = cleanSynopsis
        return cleaned?.isEmpty == false ? cleaned! : String(localized: "detail.noSynopsis")
    }

    var crossSourceTitleKey: String {
        title
            .removingTrailingSourceNumericIdentifier
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Language codes this title is known to have on its source
    /// (e.g. ["en", "es", "pt-br"]). Populated by a source runtime when the
    /// remote definition exposes language metadata. Empty when unknown.
    var availableLanguageCodes: [String] {
        guard let line = synopsis?
            .components(separatedBy: "\n")
            .first(where: { $0.hasPrefix("yomuhon-available-languages:") })
        else {
            return []
        }

        return line
            .replacingOccurrences(of: "yomuhon-available-languages:", with: "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Compact label for a language badge overlay on a cover/poster, e.g.
    /// "EN" for a single known language or "EN +2" when more are available.
    /// `nil` when there's no language metadata worth badging.
    var languageBadgeLabel: String? {
        guard let primary = availableLanguageCodes.first else { return nil }

        let remaining = availableLanguageCodes.count - 1
        let primaryCode = primary.yomuhonLanguageBadgeCode

        guard remaining > 0 else { return primaryCode }
        return "\(primaryCode) +\(remaining)"
    }

    func withAvailableLanguageCodes(_ codes: [String]) -> Manga {
        let uniqueCodes = codes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, code in
                if !result.contains(code) {
                    result.append(code)
                }
            }

        guard !uniqueCodes.isEmpty else {
            return self
        }

        let marker = "yomuhon-available-languages:\(uniqueCodes.joined(separator: ","))"
        let cleanedSynopsis = synopsis?
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("yomuhon-available-languages:") }
            .joined(separator: "\n")

        return Manga(
            id: id,
            sourceID: sourceID,
            title: title,
            coverURL: coverURL,
            synopsis: [marker, cleanedSynopsis]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "\n"),
            alternativeTitles: alternativeTitles,
            author: author,
            releaseYear: releaseYear,
            chapters: chapters
        )
    }
}


extension Manga {
    var identityTitles: [String] {
        var seen = Set<String>()
        var titles: [String] = [title]
        if let alternativeTitles {
            titles.append(contentsOf: alternativeTitles)
        }

        return titles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { value in
                let key = value
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                return seen.insert(key).inserted
            }
    }
}

extension String {
    var removingYomuhonSourceMarkers: String {
        components(separatedBy: "\n")
            .filter { line in
                !line.hasPrefix("yomuhon-source-url:")
                    && !line.hasPrefix("yomuhon-declarative-source-url:")
                    && !line.hasPrefix("yomuhon-available-languages:")
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Some HTML sources leak their internal numeric manga id into the visible
    /// title slug (for example `Title.27493`). That suffix must not split the
    /// same manga into a separate cross-source search group.
    var removingTrailingSourceNumericIdentifier: String {
        replacingOccurrences(
            of: #"\.[0-9]{4,}$"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var cleanedUserFacingSynopsis: String {
        decodedHTMLLite
            .replacingOccurrences(of: #"<br\s*/?>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</p\s*>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .decodedHTMLLite
            .replacingOccurrences(of: #"(Source:.*)$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"Read .*? online.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ([{"))
    }

    var decodedHTMLLite: String {
        let replacements: [(String, String)] = [
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&#34;", "\""),
            ("&#39;", "'"),
            ("&#039;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " "),
            ("&rsquo;", "’"),
            ("&lsquo;", "‘"),
            ("&rdquo;", "”"),
            ("&ldquo;", "“"),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&hellip;", "…"),
            ("&copy;", "©")
        ]

        return replacements.reduce(self) { value, replacement in
            value.replacingOccurrences(of: replacement.0, with: replacement.1)
        }
    }
}
