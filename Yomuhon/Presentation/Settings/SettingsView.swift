//
//  SettingsView.swift
//  Yomuhon
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = YomuhonThemeID.defaultValue.rawValue
    @AppStorage(ReaderPreferenceKeys.imageCacheMaximumMegabytes) private var readerImageCacheMegabytes = ReaderImageCacheSize.standard.rawValue
    let compositionRoot: PresentationCompositionRoot
    var onOpenSources: (() -> Void)? = nil

    @Environment(\.yomuhonTheme) private var theme
    @State private var cacheStatusMessage: String?
    @State private var showsCacheSizePicker = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: YomuhonSpacing.extraLarge) {
                    header(width: proxy.size.width)
                    appearanceSection(width: proxy.size.width)
                    storageSection(width: proxy.size.width)
                    infrastructureSection
                    aboutSection
                }
                .padding(.horizontal, contentPadding(for: proxy.size.width))
                .padding(.top, proxy.size.width > 760 ? YomuhonSpacing.extraLarge : YomuhonSpacing.large)
                .padding(.bottom, YomuhonSpacing.grand)
                .frame(maxWidth: min(proxy.size.width - contentPadding(for: proxy.size.width) * 2, 980), alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(theme.background)
        .navigationTitle("Yomuhon")
        .onChange(of: readerImageCacheMegabytes) { _ in
            ReaderCacheMaintenance.enforceImageCacheLimit()
        }
    }

    private func header(width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: YomuhonSpacing.extraLarge) {
            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                Text("settings.title")
                    .font(YomuhonTypography.largeTitle)
                    .foregroundColor(theme.textPrimary)

                Text("settings.subtitle")
                    .font(YomuhonTypography.body)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(3)
            }

            Spacer()

            if width > 760 {
                Text("settings.nativeApp")
                    .font(YomuhonTypography.captionMedium)
                    .foregroundColor(theme.textSecondary)
                    .padding(.horizontal, YomuhonSpacing.medium)
                    .padding(.vertical, 9)
                    .background(theme.secondaryBackground.opacity(0.72))
                    .clipShape(Capsule())
            }
        }
    }

    private func appearanceSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            sectionHeading(title: "settings.appearance", subtitle: "settings.appearance.subtitle")

            LazyVGrid(columns: themeColumns(for: width), alignment: .leading, spacing: YomuhonSpacing.medium) {
                ForEach(YomuhonThemeID.allCases) { id in
                    Button {
                        withAnimation(theme.animation) {
                            selectedThemeID = id.rawValue
                        }
                    } label: {
                        ThemeChoiceCard(
                            id: id,
                            isSelected: selectedThemeID == id.rawValue
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(YomuhonSpacing.large)
        .settingsSurface(theme: theme)
    }


    private func storageSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            sectionHeading(title: "settings.cache", subtitle: "settings.cache.subtitle")

            VStack(spacing: 0) {
                preferenceRow(
                    icon: "photo.on.rectangle",
                    title: "settings.cache.reader",
                    subtitle: "settings.cache.reader.subtitle",
                    stacksVertically: width < 650
                ) {
                    Button {
                        showsCacheSizePicker.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Text(selectedCacheSizeTitle)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: YomuhonIconSize.disclosure, weight: .semibold))
                                .opacity(0.68)
                        }
                        .font(YomuhonTypography.captionMedium)
                        .foregroundColor(theme.textPrimary)
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .background(theme.secondaryBackground.opacity(0.72))
                        .overlay(
                            Capsule()
                                .strokeBorder(theme.separator.opacity(0.56), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .popover(isPresented: $showsCacheSizePicker) {
                        cacheSizePickerPopover
                    }
                }

                Divider().padding(.leading, 64)

                SettingsRow(
                    icon: "arrow.down.circle",
                    title: "settings.cache.downloads",
                    subtitle: "settings.cache.downloads.subtitle",
                    value: nil,
                    showsDisclosure: false,
                    isInteractive: false
                )

                Divider().padding(.leading, 64)

                preferenceRow(
                    icon: "trash",
                    title: "settings.cache.clear",
                    subtitle: "settings.cache.clear.subtitle",
                    stacksVertically: width < 650
                ) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Button {
                            clearReaderCache()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                Text("settings.cache.clear.action")
                            }
                            .font(YomuhonTypography.captionMedium)
                            .foregroundColor(theme.textPrimary)
                            .padding(.horizontal, 13)
                            .frame(height: 34)
                            .background(theme.secondaryBackground.opacity(0.72))
                            .overlay(
                                Capsule()
                                    .strokeBorder(theme.separator.opacity(0.56), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        if let cacheStatusMessage {
                            Text(cacheStatusMessage)
                                .font(YomuhonTypography.caption)
                                .foregroundColor(theme.textSecondary)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .settingsSurface(theme: theme)
        }
    }

    private var infrastructureSection: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            sectionHeading(title: "settings.infrastructure", subtitle: "settings.infrastructure.subtitle")

            VStack(spacing: 0) {
                sourcesTrigger {
                    SettingsRow(
                        icon: "globe",
                        title: "settings.readingSources",
                        subtitle: "settings.readingSources.subtitle",
                        value: "settings.readingSources.value",
                        showsDisclosure: true,
                        isInteractive: true
                    )
                }
            }
            .settingsSurface(theme: theme)
        }
    }

    private var aboutSection: some View {
        settingsGroup(
            title: "settings.about",
            rows: [
                SettingsRowModel(icon: "info.circle", title: "settings.about.app", subtitle: "settings.about.subtitle", value: "settings.about.app.value", showsDisclosure: false),
                SettingsRowModel(icon: "sparkles", title: "settings.about.identity", subtitle: "settings.about.identity.subtitle", value: "settings.about.identity.value", showsDisclosure: false)
            ]
        )
    }

    @ViewBuilder
    private func preferenceRow<Control: View>(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        stacksVertically: Bool,
        @ViewBuilder control: () -> Control
    ) -> some View {
        if stacksVertically {
            VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
                preferenceLabel(icon: icon, title: title, subtitle: subtitle)
                control()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(YomuhonSpacing.medium)
        } else {
            HStack(spacing: YomuhonSpacing.medium) {
                preferenceLabel(icon: icon, title: title, subtitle: subtitle)
                Spacer(minLength: YomuhonSpacing.medium)
                control()
            }
            .padding(YomuhonSpacing.medium)
        }
    }

    private func preferenceLabel(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey
    ) -> some View {
        HStack(spacing: YomuhonSpacing.medium) {
            Image(systemName: icon)
                .font(.system(size: YomuhonIconSize.compact, weight: .regular))
                .foregroundColor(theme.textPrimary)
                .frame(width: 36, height: 36)
                .background(theme.secondaryBackground.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(YomuhonTypography.calloutMedium)
                    .foregroundColor(theme.textPrimary)

                Text(subtitle)
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(3)
            }
        }
    }

    private var cacheSizePickerPopover: some View {
        VStack(spacing: 0) {
            ForEach(ReaderImageCacheSize.allCases) { size in
                Button {
                    readerImageCacheMegabytes = size.rawValue
                    showsCacheSizePicker = false
                } label: {
                    HStack(spacing: YomuhonSpacing.medium) {
                        Text(size.title)
                            .font(YomuhonTypography.calloutMedium)
                            .foregroundColor(theme.textPrimary)

                        Spacer(minLength: YomuhonSpacing.large)

                        if readerImageCacheMegabytes == size.rawValue {
                            Image(systemName: "checkmark")
                                .font(YomuhonTypography.captionMedium)
                                .foregroundColor(theme.accent)
                        }
                    }
                    .padding(.horizontal, YomuhonSpacing.medium)
                    .frame(height: 38)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if size.id != ReaderImageCacheSize.allCases.last?.id {
                    Divider()
                }
            }
        }
        .padding(8)
        .frame(minWidth: 180)
        .background(theme.card)
    }

    private var selectedCacheSizeTitle: String {
        ReaderImageCacheSize(rawValue: readerImageCacheMegabytes)?.title
            ?? ReaderImageCacheSize.standard.title
    }

    private func clearReaderCache() {
        ReaderCacheMaintenance.clearImageCache()

        withAnimation(theme.animation) {
            cacheStatusMessage = String(localized: "settings.cache.clear.done")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(theme.animation) {
                cacheStatusMessage = nil
            }
        }
    }

    private func settingsGroup(title: LocalizedStringKey, rows: [SettingsRowModel]) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            Text(title)
                .font(YomuhonTypography.headline)
                .foregroundColor(theme.textPrimary)

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    SettingsRow(
                        icon: row.icon,
                        title: row.title,
                        subtitle: row.subtitle,
                        value: row.value,
                        showsDisclosure: row.showsDisclosure,
                        isInteractive: false
                    )

                    if row.id != rows.last?.id {
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .settingsSurface(theme: theme)
        }
    }

    @ViewBuilder
    private func sourcesTrigger<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if let onOpenSources {
            Button(action: onOpenSources) {
                content()
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(destination: SourcesView(viewModel: compositionRoot.makeSourcesViewModel())) {
                content()
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionHeading(title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(YomuhonTypography.headline)
                .foregroundColor(theme.textPrimary)

            Text(subtitle)
                .font(YomuhonTypography.caption)
                .foregroundColor(theme.textSecondary)
        }
    }

    private func themeColumns(for width: CGFloat) -> [GridItem] {
        let minimum: CGFloat = width > 760 ? 220 : 160
        return [GridItem(.adaptive(minimum: minimum, maximum: minimum + 90), spacing: YomuhonSpacing.medium)]
    }

    private func contentPadding(for width: CGFloat) -> CGFloat {
        if width >= 1180 {
            return YomuhonSpacing.grand
        }

        return width >= 720 ? YomuhonSpacing.extraLarge : YomuhonSpacing.large
    }
}

private struct SettingsRowModel: Identifiable {
    let id = UUID()
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let value: LocalizedStringKey?
    let showsDisclosure: Bool
}

private struct SettingsRow: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let value: LocalizedStringKey?
    let showsDisclosure: Bool
    let isInteractive: Bool

    @Environment(\.yomuhonTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: YomuhonSpacing.medium) {
            Image(systemName: icon)
                .font(.system(size: YomuhonIconSize.compact, weight: .regular))
                .foregroundColor(theme.textPrimary)
                .frame(width: 36, height: 36)
                .background(theme.secondaryBackground.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(YomuhonTypography.calloutMedium)
                    .foregroundColor(theme.textPrimary)

                Text(subtitle)
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: YomuhonSpacing.medium)

            if let value {
                Text(value)
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
            }

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(YomuhonTypography.captionMedium)
                    .foregroundColor(theme.textSecondary.opacity(0.72))
            }
        }
        .padding(YomuhonSpacing.medium)
        .contentShape(isInteractive ? Rectangle() : Rectangle())
        .background(isInteractive && isHovering ? theme.secondaryBackground.opacity(0.28) : Color.clear)
        .onHover { isHovering = isInteractive && $0 }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct ThemeChoiceCard: View {
    let id: YomuhonThemeID
    let isSelected: Bool

    @Environment(\.yomuhonTheme) private var currentTheme

    private var previewTheme: YomuhonTheme {
        AppTheme.theme(for: id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(previewTheme.background)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(previewTheme.sidebar)
                            .frame(width: 28, height: 54)

                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(previewTheme.textPrimary.opacity(0.86))
                                .frame(width: 70, height: 7)

                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(previewTheme.textSecondary.opacity(0.72))
                                .frame(width: 92, height: 5)

                            HStack(spacing: 5) {
                                ForEach(0..<3, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(previewTheme.accent.opacity(0.80))
                                        .frame(width: 22, height: 32)
                                }
                            }
                        }
                    }
                }
                .padding(YomuhonSpacing.medium)
            }
            .frame(height: 118)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? currentTheme.textPrimary : currentTheme.separator.opacity(0.74), lineWidth: isSelected ? 2 : 1)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(id.titleKey)
                    .font(YomuhonTypography.calloutSemibold)
                    .foregroundColor(currentTheme.textPrimary)

                Text(id.descriptionKey)
                    .font(YomuhonTypography.caption)
                    .foregroundColor(currentTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(YomuhonSpacing.medium)
        .background(currentTheme.card.opacity(currentTheme.id == .ink ? 0.36 : 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private extension View {
    func settingsSurface(theme: YomuhonTheme) -> some View {
        background(theme.card.opacity(theme.id == .ink ? 0.46 : 1.0))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(theme.separator.opacity(0.58), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
