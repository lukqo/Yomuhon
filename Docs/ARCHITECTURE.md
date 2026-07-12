# Architecture

## Overview

Yomuhon follows Clean Architecture with MVVM in the presentation layer.

```text
Presentation
     ↓
   Domain
     ↑
    Data
```

## Dependency rules

- Domain must not depend on SwiftUI.
- Domain must not depend on Presentation.
- Data implements Domain repository protocols.
- Presentation reaches business logic through use cases and repositories.
- Views should not own business logic.
- ViewModels own presentation state.
- External systems are abstracted behind repositories or source protocols.

## Technology

| Area | Technology |
|---|---|
| UI | SwiftUI |
| Presentation | MVVM |
| State | ObservableObject, @Published, Combine |
| Persistence | Core Data and local stores |
| Networking | URLSession |
| Localization | Localizable.strings |
| Icons | SF Symbols |
| Themes | AppTheme |

Avoid introducing SwiftData, `@Observable` or third-party UI frameworks while Xcode 14.2 remains the project constraint.

## Main project areas

```text
Yomuhon/
├── App/
├── Domain/
│   ├── Entities/
│   ├── Repositories/
│   └── UseCases/
├── Data/
│   ├── Local/
│   ├── Network/
│   └── Sources/
├── Presentation/
│   ├── Shell/
│   ├── Library/
│   ├── Search/
│   ├── MangaDetail/
│   ├── Reader/
│   ├── Downloads/
│   ├── Settings/
│   └── Shared/
└── Platform/
```

The exact folder tree may evolve, but the dependency direction must remain clear.

## Domain concepts

### Manga

Represents a manga candidate from a reading source.

Cross-source grouping may present multiple source versions as one visible title. Source identity must still be preserved for reading and downloads.

### Chapter

Represents a readable chapter belonging to a manga/source version.

Chapters support progress and offline download state.

### Page

Represents a readable image.

The reader should not need to know whether the page is local or remote.

### Reading progress

Stores chapter, page and last-read information locally.

## Search

Search should:

- query currently usable sources concurrently;
- publish progressive results;
- cancel obsolete requests;
- group duplicate titles deterministically;
- avoid presenting unreadable source results as successful reading options.

Network response order must not determine visible grouping identity.

## Detail loading

Manga detail loading must always be finite.

Requirements:

- idempotent loading for repeated SwiftUI lifecycle callbacks;
- per-source timeout;
- cancellation of obsolete work;
- fallback without retry loops;
- no infinite spinner when every source fails;
- readable source selection based on actual chapter availability.

## Downloads

Downloads use a persistent queue.

Expected behavior:

- queued, downloading, paused, failed and completed states;
- bounded concurrency;
- launch recovery;
- cancellation-aware page downloads;
- explicit offline chapter storage;
- source-separated paths;
- equivalent chapter deduplication where safe.

Offline files are product data, not cache.

## Reader

The Reader is the final destination of the product.

It supports:

- paged mode;
- webtoon mode;
- fit page, width and height behavior;
- optional two-page spreads on suitable large layouts;
- keyboard navigation on macOS;
- progress persistence;
- automatic next/previous chapter transitions when available.

Reader UI state and manga reading progress are separate concerns.

## Error handling

Remote content is untrusted input.

The app must:

- decode defensively;
- validate URLs;
- use HTTPS for remote definitions;
- ignore a broken remote source definition without breaking the full catalog;
- surface finite, user-readable states;
- preserve usable cached definitions when remote refresh fails.
