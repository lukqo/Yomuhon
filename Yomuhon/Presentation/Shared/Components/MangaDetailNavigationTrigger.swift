//
//  MangaDetailNavigationTrigger.swift
//  Yomuhon
//
//  Single source of truth for "tap a manga row to open its detail screen".
//  Previously this exact pattern (build a MangaDetailViewModel, then either call
//  onOpenMangaDetail or push a NavigationLink) was duplicated in SearchView,
//  LibraryView, and ContinueReadingView. Building it here also fixes a subtle
//  issue: the old call sites constructed the MangaDetailViewModel eagerly as a
//  `let` inside the view body / a @ViewBuilder helper, so a brand new view
//  model was instantiated on *every* body re-evaluation (e.g. while a search is
//  still streaming results). @StateObject discards the extra instances as long
//  as row identity is stable, but it's wasted work and fragile. Using the
//  closure-based NavigationLink initializer defers construction until the
//  destination is actually needed.

import SwiftUI

struct MangaDetailNavigationTrigger<Content: View>: View {
    let compositionRoot: PresentationCompositionRoot
    let manga: Manga
    var alternativeMangas: [Manga] = []
    var progress: ReadingProgress?
    var onOpenMangaDetail: ((MangaDetailViewModel) -> Void)?
    let content: Content

    init(
        compositionRoot: PresentationCompositionRoot,
        manga: Manga,
        alternativeMangas: [Manga] = [],
        progress: ReadingProgress? = nil,
        onOpenMangaDetail: ((MangaDetailViewModel) -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.compositionRoot = compositionRoot
        self.manga = manga
        self.alternativeMangas = alternativeMangas
        self.progress = progress
        self.onOpenMangaDetail = onOpenMangaDetail
        self.content = content()
    }

    var body: some View {
        if let onOpenMangaDetail {
            Button {
                onOpenMangaDetail(makeDetailViewModel())
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                MangaDetailView(viewModel: makeDetailViewModel())
            } label: {
                content
            }
            .buttonStyle(.plain)
        }
    }

    private func makeDetailViewModel() -> MangaDetailViewModel {
        compositionRoot.makeMangaDetailViewModel(
            manga: manga,
            alternativeMangas: alternativeMangas,
            progress: progress
        )
    }
}
