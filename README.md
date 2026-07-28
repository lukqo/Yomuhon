# Yomuhon

> Native manga reader for macOS, iPadOS and iOS.

Yomuhon is an Apple-first, local-first manga reader built around one product rule:

> **The manga is the product.**

The interface exists to help users discover manga, keep a personal library and read comfortably. Source repositories, parsers and remote definitions are infrastructure and should remain secondary to the reading experience.

## Current state

Yomuhon already includes:

- Adaptive SwiftUI navigation for regular and compact layouts.
- Local library and reading history.
- Multi-source search with grouping and progressive results.
- Manga detail and chapter loading with finite timeout/retry states.
- Paged and webtoon reader modes.
- Global reader preferences where appropriate.
- Persistent download queue with pause, retry and launch recovery.
- Offline chapter reading.
- Remote declarative source discovery through `Yomuhon-Sources`.
- Per-operation source runtimes, allowing one remote definition to use HTML for catalog/reader pages and JSON for chapters without provider-specific Swift.
- Local caching of definitions previously downloaded from GitHub for resilience.
- No provider definitions or provider-specific adapters embedded in the app.
- English and Spanish localization.
- macOS, iPhone and iPad presentation paths.

The current development focus is stability, source reliability, reader polish and release readiness.

## Development constraints

- macOS Monterey 12.x
- Xcode 14.2
- macOS deployment target: 12.7
- iOS / iPadOS deployment target: 16.2
- SwiftUI
- MVVM
- Clean Architecture
- Core Data
- URLSession
- Combine

Do not introduce APIs that require a newer SDK unless the project explicitly migrates.

## Documentation

- [Product](Docs/PRODUCT.md)
- [Architecture](Docs/ARCHITECTURE.md)
- [Design](Docs/DESIGN.md)
- [Source engine](Docs/SOURCES.md)
- [Testing and release](Docs/TESTING.md)
- [Roadmap](Docs/ROADMAP.md)
- [Changelog](Docs/CHANGELOG.md)

## Build

Open:

```text
Yomuhon.xcodeproj
```

Select the Yomuhon scheme and run the appropriate macOS or iOS/iPadOS destination in Xcode 14.2.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for setup,
code guidelines and how to submit a PR. For manga source issues or new
sources, use [Yomuhon-Sources](https://github.com/lukqo/Yomuhon-Sources)
instead.

Yomuhon is licensed under the [MIT License](LICENSE).

## Project rule

A feature is not complete because it compiles.

It is complete when it is stable, understandable, localized, visually consistent and usable on the supported layout families.

## Legal

Yomuhon is a personal open-source reading client. It does not host manga content.

Remote source definitions are declarative configuration. The production app should not execute arbitrary remote code, run Android/Tachiyomi extensions or attempt to bypass anti-bot protections.
