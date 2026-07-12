//
//  CompactRootView.swift
//  Yomuhon
//

import SwiftUI

struct CompactRootView: View {
    @ObservedObject var libraryViewModel: LibraryViewModel
    let compositionRoot: PresentationCompositionRoot
    @ObservedObject var navigationModel: AppNavigationModel

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        Group {
            if let route = navigationModel.currentRoute {
                compactRouteShell(route)
            } else {
                tabShell
            }
        }
        .background(theme.background)
    }

    private var tabShell: some View {
        TabView(selection: $navigationModel.selectedSection) {
            NavigationView {
                LibraryView(
                    viewModel: libraryViewModel,
                    showsSidebar: false,
                    onFindManga: { navigationModel.selectSection(.search) },
                    onOpenMangaDetail: { detailViewModel in
                        navigationModel.openMangaDetail(detailViewModel)
                    },
                    compositionRoot: compositionRoot
                )
            }
            .compactNavigationStyle()
            .tabItem {
                Label("library.title", systemImage: "books.vertical")
            }
            .tag(AppSection.library)

            NavigationView {
                SearchView(
                    viewModel: compositionRoot.makeSearchViewModel(),
                    compositionRoot: compositionRoot,
                    onOpenMangaDetail: { detailViewModel in
                        navigationModel.openMangaDetail(detailViewModel)
                    }
                )
            }
            .compactNavigationStyle()
            .tabItem {
                Label("search.title", systemImage: "magnifyingglass")
            }
            .tag(AppSection.search)

            NavigationView {
                DownloadsView(
                    viewModel: libraryViewModel,
                    compositionRoot: compositionRoot,
                    onOpenMangaDetail: { detailViewModel in
                        navigationModel.openMangaDetail(detailViewModel)
                    }
                )
            }
            .compactNavigationStyle()
            .tabItem {
                Label("downloads.title", systemImage: "arrow.down.circle")
            }
            .tag(AppSection.downloads)

            NavigationView {
                SettingsView(
                    compositionRoot: compositionRoot,
                    onOpenSources: {
                        navigationModel.openSources(compositionRoot.makeSourcesViewModel())
                    }
                )
            }
            .compactNavigationStyle()
            .tabItem {
                Label("settings.title", systemImage: "gearshape")
            }
            .tag(AppSection.settings)
        }
    }

    private func compactRouteShell(_ route: AppRoute) -> some View {
        VStack(spacing: 0) {
            compactRouteBar(route)

            Rectangle()
                .fill(theme.separator.opacity(0.55))
                .frame(height: 1)

            routeContent(route)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func compactRouteBar(_ route: AppRoute) -> some View {
        HStack(spacing: YomuhonSpacing.medium) {
            Button {
                withAnimation(theme.animation) {
                    navigationModel.goBack()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(theme.textPrimary)
            .accessibilityLabel(Text("navigation.back"))

            compactRouteTitle(route)
                .font(YomuhonTypography.headline)
                .foregroundColor(theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, YomuhonSpacing.medium)
        .padding(.vertical, YomuhonSpacing.small)
        .background(theme.background)
    }

    @ViewBuilder
    private func compactRouteTitle(_ route: AppRoute) -> some View {
        switch route {
        case .mangaDetail(let viewModel):
            MangaDetailRouteTitle(viewModel: viewModel)
        case .sources:
            Text(NSLocalizedString("sources.title", comment: ""))
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

private extension View {
    @ViewBuilder
    func compactNavigationStyle() -> some View {
        #if os(iOS)
        navigationViewStyle(.stack)
        #else
        self
        #endif
    }
}
