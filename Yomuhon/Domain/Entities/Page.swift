//
//  Page.swift
//  Yomuhon
//

import Foundation

struct Page: Identifiable, Hashable, Codable {
    let id: String
    let index: Int
    let imageURL: URL?
    var localFileURL: URL?
}
