//
//  SourceRepositoryConfiguration.swift
//  Yomuhon
//

import Foundation

struct SourceRepositoryConfiguration: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var isEnabled: Bool
    var isBundled: Bool
    var installedSources: [InstalledSourceConfiguration]
    var statusMessage: String?

    init(
        id: String,
        name: String,
        isEnabled: Bool,
        isBundled: Bool,
        installedSources: [InstalledSourceConfiguration] = [],
        statusMessage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.isBundled = isBundled
        self.installedSources = installedSources
        self.statusMessage = statusMessage
    }
}

enum SourceHealthStatus: String, Codable, Hashable {
    case available
    case unavailable
}

struct InstalledSourceConfiguration: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var language: String?
    var healthStatus: SourceHealthStatus
    var mangas: [Manga]
    var isInstalled: Bool

    init(
        id: String,
        name: String,
        language: String? = nil,
        healthStatus: SourceHealthStatus = .available,
        mangas: [Manga] = [],
        isInstalled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.healthStatus = healthStatus
        self.mangas = mangas
        self.isInstalled = isInstalled
    }
}
