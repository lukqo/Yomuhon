//
//  RootView.swift
//  Yomuhon
//

import Foundation
import SwiftUI

#if os(iOS)
import UIKit
#endif

enum YomuhonShellLayout: Equatable {
    case regular
    case compact
}

enum YomuhonShellLayoutResolver {
    static func resolve(
        viewportWidth: CGFloat,
        isPad: Bool,
        currentLayout: YomuhonShellLayout
    ) -> YomuhonShellLayout {
        guard isPad else {
            return .compact
        }

        let width = safeDimension(viewportWidth)

        switch currentLayout {
        case .compact:
            return width >= YomuhonLayout.regularShellEnterBreakpoint ? .regular : .compact
        case .regular:
            return width < YomuhonLayout.regularShellExitBreakpoint ? .compact : .regular
        }
    }
}


enum AppSection: String, CaseIterable, Identifiable {
    case library
    case search
    case downloads
    case settings

    var id: String {
        rawValue
    }

    var title: String {
        NSLocalizedString(titleKey, comment: "")
    }

    var titleKey: String {
        switch self {
        case .library:
            return "library.title"
        case .search:
            return "search.title"
        case .downloads:
            return "downloads.title"
        case .settings:
            return "settings.title"
        }
    }

    var systemImage: String {
        switch self {
        case .library:
            return "books.vertical"
        case .search:
            return "magnifyingglass"
        case .downloads:
            return "arrow.down.circle"
        case .settings:
            return "gearshape"
        }
    }
}

enum AppRoute {
    case mangaDetail(MangaDetailViewModel)
    case sources(SourcesViewModel)
    case sourceCatalog(SourceCatalogViewModel)
}

struct ReaderNavigationSession: Identifiable {
    let id: UUID
    let viewModel: ReaderViewModel
    let originDetailViewModel: MangaDetailViewModel?

    init(
        id: UUID = UUID(),
        viewModel: ReaderViewModel,
        originDetailViewModel: MangaDetailViewModel?
    ) {
        self.id = id
        self.viewModel = viewModel
        self.originDetailViewModel = originDetailViewModel
    }
}

final class AppNavigationModel: ObservableObject {
    @Published var selectedSection: AppSection
    @Published private(set) var routeStack: [AppRoute]
    @Published private(set) var activeReaderSession: ReaderNavigationSession?
    @Published private(set) var shellLayout: YomuhonShellLayout

    init(
        selectedSection: AppSection = .library,
        shellLayout: YomuhonShellLayout = .compact
    ) {
        self.selectedSection = selectedSection
        self.routeStack = []
        self.activeReaderSession = nil
        self.shellLayout = shellLayout
    }

    var currentRoute: AppRoute? {
        routeStack.last
    }

    func selectSection(_ section: AppSection) {
        selectedSection = section
        routeStack.removeAll()
    }

    func openMangaDetail(_ viewModel: MangaDetailViewModel) {
        routeStack.append(.mangaDetail(viewModel))
#if DEBUG
        print("[Yomuhon][Navigation] push detail vm=\(ObjectIdentifier(viewModel)) section=\(selectedSection.rawValue)")
#endif
    }

    func openSources(_ viewModel: SourcesViewModel) {
        routeStack.append(.sources(viewModel))
    }

    func openSourceCatalog(_ viewModel: SourceCatalogViewModel) {
        routeStack.append(.sourceCatalog(viewModel))
    }

    func goBack() {
        guard !routeStack.isEmpty else { return }
        _ = routeStack.popLast()
    }

    func openReader(
        _ viewModel: ReaderViewModel,
        from detailViewModel: MangaDetailViewModel?
    ) {
        activeReaderSession = ReaderNavigationSession(
            viewModel: viewModel,
            originDetailViewModel: detailViewModel
        )
#if DEBUG
        print("[Yomuhon][Navigation] reader open vm=\(ObjectIdentifier(viewModel)) page=\(viewModel.currentPageIndex)")
#endif
    }

    func closeReader() {
        let originDetailViewModel = activeReaderSession?.originDetailViewModel
#if DEBUG
        if let activeReaderSession {
            print("[Yomuhon][Navigation] reader close vm=\(ObjectIdentifier(activeReaderSession.viewModel)) page=\(activeReaderSession.viewModel.currentPageIndex)")
        }
#endif
        activeReaderSession = nil

        // ReaderView flushes progress before invoking its close action. Refresh on
        // the next main-loop turn so Detail observes the persisted page/chapter.
        DispatchQueue.main.async {
            originDetailViewModel?.refreshProgress()
        }
    }

    func updateShellLayout(viewportWidth: CGFloat, isPad: Bool) {
        let resolved = YomuhonShellLayoutResolver.resolve(
            viewportWidth: viewportWidth,
            isPad: isPad,
            currentLayout: shellLayout
        )

        guard resolved != shellLayout else { return }
#if DEBUG
        print(
            "[Yomuhon][Navigation] shell \(shellLayout) -> \(resolved) width=\(safeDimension(viewportWidth)) route=\(routeDebugName) reader=\(activeReaderSession == nil ? "none" : "active")"
        )
#endif
        shellLayout = resolved
    }

    private var routeDebugName: String {
        guard let currentRoute else { return "root" }

        switch currentRoute {
        case .mangaDetail:
            return "detail"
        case .sources:
            return "sources"
        case .sourceCatalog:
            return "sourceCatalog"
        }
    }
}

struct RootView: View {
    private let compositionRoot: PresentationCompositionRoot
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var searchViewModel: SearchViewModel
    @StateObject private var navigationModel: AppNavigationModel

    init(compositionRoot: PresentationCompositionRoot = .live) {
        self.compositionRoot = compositionRoot
        _libraryViewModel = StateObject(wrappedValue: compositionRoot.makeLibraryViewModel())
        _searchViewModel = StateObject(wrappedValue: compositionRoot.makeSearchViewModel())
        _navigationModel = StateObject(wrappedValue: AppNavigationModel())
    }

    var body: some View {
        #if os(iOS)
        GeometryReader { proxy in
            let isPad = UIDevice.current.userInterfaceIdiom == .pad
            let resolvedLayout = YomuhonShellLayoutResolver.resolve(
                viewportWidth: proxy.size.width,
                isPad: isPad,
                currentLayout: navigationModel.shellLayout
            )

            rootLayers(layout: resolvedLayout)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    navigationModel.updateShellLayout(
                        viewportWidth: proxy.size.width,
                        isPad: isPad
                    )
                }
                .onChange(of: proxy.size.width) { newWidth in
                    navigationModel.updateShellLayout(
                        viewportWidth: newWidth,
                        isPad: isPad
                    )
                }
        }
        #else
        rootLayers(layout: .regular)
        #endif
    }

    private func rootLayers(layout: YomuhonShellLayout) -> some View {
        ZStack {
            shell(for: layout)
                .allowsHitTesting(navigationModel.activeReaderSession == nil)

            if let session = navigationModel.activeReaderSession {
                ReaderView(
                    viewModel: session.viewModel,
                    onClose: navigationModel.closeReader
                )
                .id(session.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .zIndex(100)
            }
        }
    }

    @ViewBuilder
    private func shell(for layout: YomuhonShellLayout) -> some View {
        switch layout {
        case .regular:
            RegularRootView(
                libraryViewModel: libraryViewModel,
                searchViewModel: searchViewModel,
                compositionRoot: compositionRoot,
                navigationModel: navigationModel
            )

        case .compact:
            CompactRootView(
                libraryViewModel: libraryViewModel,
                searchViewModel: searchViewModel,
                compositionRoot: compositionRoot,
                navigationModel: navigationModel
            )
        }
    }
}
