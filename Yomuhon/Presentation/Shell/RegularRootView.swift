//
//  RegularRootView.swift
//  Yomuhon
//

import SwiftUI

struct RegularRootView: View {
    @ObservedObject var libraryViewModel: LibraryViewModel
    let compositionRoot: PresentationCompositionRoot
    @ObservedObject var navigationModel: AppNavigationModel

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        regularShell
            .background(theme.background)
    }

    private var regularShell: some View {
        HStack(spacing: 0) {
            sidebar

            Rectangle()
                .fill(theme.separator.opacity(0.55))
                .frame(width: 1)

            VStack(spacing: 0) {
                if navigationModel.currentRoute != nil {
                    routeBar

                    Rectangle()
                        .fill(theme.separator.opacity(0.55))
                        .frame(height: 1)
                }

                currentContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand

            VStack(alignment: .leading, spacing: YomuhonSpacing.large) {
                librarySection
                contentSection
            }
            .padding(.horizontal, YomuhonSpacing.medium)

            Spacer()

            settingsButton
                .padding(.horizontal, YomuhonSpacing.medium)
                .padding(.bottom, YomuhonSpacing.medium)
        }
        .frame(width: YomuhonLayout.sidebarMinWidth)
        .background(theme.sidebar)
    }

    private var brand: some View {
        HStack(spacing: YomuhonSpacing.small) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 28, height: 28)

            Text("Yomuhon")
                .font(YomuhonTypography.headline)
        }
        .foregroundColor(theme.textPrimary)
        .padding(.horizontal, YomuhonSpacing.large)
        .padding(.top, YomuhonSpacing.extraLarge)
        .padding(.bottom, YomuhonSpacing.large)
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
            sidebarTitle("library.title")

            SidebarButton(
                title: LibraryCategory.all.title,
                systemImage: LibraryCategory.all.iconName,
                badgeText: String(libraryViewModel.categoryCount(.all)),
                isSelected: navigationModel.selectedSection == .library && libraryViewModel.selectedCategory == .all
            ) {
                selectLibraryCategory(.all)
            }

            Text("library.collections")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(theme.textSecondary.opacity(0.68))
                .textCase(.uppercase)
                .padding(.horizontal, YomuhonSpacing.small)
                .padding(.top, YomuhonSpacing.small)

            ForEach([LibraryCategory.reading, .completed, .planToRead]) { category in
                SidebarButton(
                    title: category.title,
                    systemImage: category.iconName,
                    badgeText: String(libraryViewModel.categoryCount(category)),
                    isSelected: navigationModel.selectedSection == .library && libraryViewModel.selectedCategory == category
                ) {
                    selectLibraryCategory(category)
                }
            }
        }
    }

    private func selectLibraryCategory(_ category: LibraryCategory) {
        libraryViewModel.selectedCategory = category
        navigationModel.selectSection(.library)
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
            sidebarTitle("content.title")

            SidebarButton(
                title: AppSection.search.title,
                systemImage: AppSection.search.systemImage,
                isSelected: navigationModel.selectedSection == .search
            ) {
                navigationModel.selectSection(.search)
            }

            SidebarButton(
                title: AppSection.downloads.title,
                systemImage: AppSection.downloads.systemImage,
                isSelected: navigationModel.selectedSection == .downloads
            ) {
                navigationModel.selectSection(.downloads)
            }
        }
    }

    private var settingsButton: some View {
        SidebarButton(
            title: AppSection.settings.title,
            systemImage: AppSection.settings.systemImage,
            isSelected: navigationModel.selectedSection == .settings
        ) {
            navigationModel.selectSection(.settings)
        }
    }

    private func sidebarTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(YomuhonTypography.captionMedium)
            .foregroundColor(theme.textSecondary)
            .textCase(.uppercase)
            .padding(.horizontal, YomuhonSpacing.small)
    }

    private var routeBar: some View {
        HStack(spacing: YomuhonSpacing.medium) {
            Button {
                withAnimation(theme.animation) {
                    navigationModel.goBack()
                }
            } label: {
                Label("navigation.back", systemImage: "chevron.left")
                    .font(YomuhonTypography.calloutMedium)
            }
            .buttonStyle(.plain)
            .foregroundColor(theme.textPrimary)

            routeTitleView
                .font(YomuhonTypography.headline)
                .foregroundColor(theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, YomuhonSpacing.extraLarge)
        .padding(.vertical, YomuhonSpacing.medium)
        .background(theme.background)
    }

    @ViewBuilder
    private var routeTitleView: some View {
        if let route = navigationModel.currentRoute {
            switch route {
            case .mangaDetail(let viewModel):
                MangaDetailRouteTitle(viewModel: viewModel)
            case .sources:
                Text(NSLocalizedString("sources.title", comment: ""))
            }
        } else {
            Text(navigationModel.selectedSection.title)
        }
    }

    @ViewBuilder
    private var currentContent: some View {
        if let route = navigationModel.currentRoute {
            routeContent(route)
        } else {
            sectionContent(navigationModel.selectedSection)
        }
    }

    @ViewBuilder
    private func sectionContent(_ section: AppSection) -> some View {
        switch section {
        case .library:
            LibraryView(
                viewModel: libraryViewModel,
                showsSidebar: false,
                onFindManga: {
                    withAnimation(theme.animation) {
                        navigationModel.selectSection(.search)
                    }
                },
                onOpenMangaDetail: { detailViewModel in
                    withAnimation(theme.animation) {
                        navigationModel.openMangaDetail(detailViewModel)
                    }
                },
                compositionRoot: compositionRoot
            )

        case .search:
            SearchView(
                viewModel: compositionRoot.makeSearchViewModel(),
                compositionRoot: compositionRoot,
                onOpenMangaDetail: { detailViewModel in
                    withAnimation(theme.animation) {
                        navigationModel.openMangaDetail(detailViewModel)
                    }
                }
            )

        case .downloads:
            DownloadsView(
                viewModel: libraryViewModel,
                compositionRoot: compositionRoot,
                onOpenMangaDetail: { detailViewModel in
                    withAnimation(theme.animation) {
                        navigationModel.openMangaDetail(detailViewModel)
                    }
                }
            )

        case .settings:
            SettingsView(
                compositionRoot: compositionRoot,
                onOpenSources: {
                    withAnimation(theme.animation) {
                        navigationModel.openSources(compositionRoot.makeSourcesViewModel())
                    }
                }
            )
        }
    }

    @ViewBuilder
    private func routeContent(_ route: AppRoute) -> some View {
        switch route {
        case .mangaDetail(let detailViewModel):
            MangaDetailRouteHost(
                viewModel: detailViewModel,
                onOpenReader: { readerViewModel in
                    withAnimation(theme.animation) {
                        navigationModel.openReader(readerViewModel, from: detailViewModel)
                    }
                }
            )
            .id(ObjectIdentifier(detailViewModel))

        case .sources(let sourcesViewModel):
            SourcesView(viewModel: sourcesViewModel)
        }
    }
}

struct MangaDetailRouteHost: View {
    @StateObject private var viewModel: MangaDetailViewModel
    private let onOpenReader: (ReaderViewModel) -> Void

    init(
        viewModel: MangaDetailViewModel,
        onOpenReader: @escaping (ReaderViewModel) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onOpenReader = onOpenReader
    }

    var body: some View {
        MangaDetailView(
            viewModel: viewModel,
            onOpenReader: onOpenReader
        )
#if DEBUG
        .onAppear {
            print("[Yomuhon][Route] detail host appear vm=\(ObjectIdentifier(viewModel)) chapters=\(viewModel.chapters.count) loading=\(viewModel.isLoadingDetails)")
        }
#endif
    }
}

struct MangaDetailRouteTitle: View {
    @ObservedObject private var viewModel: MangaDetailViewModel

    init(viewModel: MangaDetailViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        Text(viewModel.title)
    }
}

private struct SidebarButton: View {
    let title: String
    let systemImage: String
    var badgeText: String? = nil
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.yomuhonTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: YomuhonSpacing.medium) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 22)

                Text(title)
                    .font(YomuhonTypography.calloutMedium)

                Spacer(minLength: YomuhonSpacing.small)

                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(isSelected ? theme.textPrimary : theme.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(theme.background.opacity(isSelected ? 0.72 : 0.42))
                        .clipShape(Capsule())
                }

                if isSelected {
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: 3, height: 18)
                        .transition(.opacity)
                }
            }
            .foregroundColor(isSelected ? theme.textPrimary : theme.textSecondary)
            .padding(.horizontal, YomuhonSpacing.small)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected || isHovering ? theme.secondaryBackground.opacity(isSelected ? 0.86 : 0.48) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}
