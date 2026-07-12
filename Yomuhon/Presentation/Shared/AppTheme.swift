//
//  AppTheme.swift
//  Yomuhon
//

import SwiftUI

struct YomuhonTheme {
    let id: YomuhonThemeID
    let name: String
    let background: Color
    let secondaryBackground: Color
    let sidebar: Color
    let card: Color
    let separator: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let cornerRadius: CGFloat
    let spacing: CGFloat
    let animation: Animation
    let shadow: Color
}

enum YomuhonThemeID: String, CaseIterable, Identifiable {
    case ink
    case slate

    static let defaultValue = YomuhonThemeID.slate

    var id: String {
        rawValue
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .ink:
            return "settings.theme.ink"
        case .slate:
            return "settings.theme.slate"
        }
    }

    var descriptionKey: LocalizedStringKey {
        switch self {
        case .ink:
            return "settings.theme.ink.description"
        case .slate:
            return "settings.theme.slate.description"
        }
    }
}

enum AppTheme {
    static let storageKey = "yomuhon.selectedTheme"

    static let inkTheme = YomuhonTheme(
        id: .ink,
        name: "Ink",
        background: Color(red: 0.030, green: 0.030, blue: 0.032),
        secondaryBackground: Color(red: 0.072, green: 0.072, blue: 0.076),
        sidebar: Color(red: 0.050, green: 0.050, blue: 0.054),
        card: Color.white.opacity(0.070),
        separator: Color.white.opacity(0.115),
        textPrimary: Color.white.opacity(0.940),
        textSecondary: Color.white.opacity(0.600),
        accent: Color.white.opacity(0.920),
        cornerRadius: 14,
        spacing: YomuhonSpacing.large,
        animation: YomuhonMotion.relaxed,
        shadow: Color.black.opacity(0.520)
    )

    static let slateTheme = YomuhonTheme(
        id: .slate,
        name: "Slate",
        background: Color(red: 0.976, green: 0.976, blue: 0.976),
        secondaryBackground: Color(red: 0.945, green: 0.945, blue: 0.947),
        sidebar: Color(red: 0.961, green: 0.961, blue: 0.963),
        card: Color.white,
        separator: Color.black.opacity(0.075),
        textPrimary: Color.black.opacity(0.900),
        textSecondary: Color.black.opacity(0.480),
        accent: Color.black.opacity(0.900),
        cornerRadius: 14,
        spacing: YomuhonSpacing.large,
        animation: YomuhonMotion.relaxed,
        shadow: Color.black.opacity(0.100)
    )

    static let current = slateTheme

    static let background = current.background
    static let sidebarBackground = current.sidebar
    static let elevatedBackground = current.card
    static let secondaryBackground = current.secondaryBackground
    static let hairline = current.separator
    static let ink = current.accent

    static func theme(for rawValue: String) -> YomuhonTheme {
        theme(for: YomuhonThemeID(rawValue: rawValue) ?? .defaultValue)
    }

    static func theme(for id: YomuhonThemeID) -> YomuhonTheme {
        switch id {
        case .ink:
            return inkTheme
        case .slate:
            return slateTheme
        }
    }
}

private struct YomuhonThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppTheme.slateTheme
}

extension EnvironmentValues {
    var yomuhonTheme: YomuhonTheme {
        get { self[YomuhonThemeEnvironmentKey.self] }
        set { self[YomuhonThemeEnvironmentKey.self] = newValue }
    }
}
