# Contributing to Yomuhon

Thanks for your interest in contributing. Yomuhon is a personal project, but
external contributions are welcome as long as they respect the project's
direction and constraints.

## Before you start

- Read [Docs/PRODUCT.md](Docs/PRODUCT.md) and [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md)
  first. Yomuhon follows MVVM + Clean Architecture, and PRs that don't fit the
  existing structure will need rework.
- Check [Docs/ROADMAP.md](Docs/ROADMAP.md) and open issues before starting
  something big, so we don't duplicate effort.
- For anything non-trivial (new feature, refactor, new reader mode), please
  open an issue first to discuss the approach before writing code.

## Development setup

Requirements (see the README for the authoritative list):

- macOS Monterey 12.x
- Xcode 14.2
- Deployment targets: macOS 12.7, iOS/iPadOS 16.2

Do not introduce APIs that require a newer SDK than the above unless the
project explicitly migrates its deployment target.

1. Fork the repo and clone your fork.
2. Open `Yomuhon.xcodeproj` in Xcode 14.2.
3. In **Signing & Capabilities**, select your own Team under "Team" for each
   target (the repo doesn't ship a Development Team, so Xcode will prompt
   you to pick one — any free personal team works for local builds/simulator
   runs).
4. Select the `Yomuhon` scheme and run on macOS or an iOS/iPadOS simulator.
5. Source definitions are fetched from [Yomuhon-Sources](https://github.com/lukqo/Yomuhon-Sources)
   at runtime — you don't need to touch that repo unless you're adding or
   fixing a manga source, which lives there, not in this app.

## Code guidelines

- SwiftUI, MVVM, Clean Architecture — keep view, view-model and domain layers
  separated the way the existing modules do.
- No provider-specific parsing code inside the app. Source-specific logic
  belongs in [Yomuhon-Sources](https://github.com/lukqo/Yomuhon-Sources) as a
  declarative definition, not as Swift.
- Keep both English and Spanish localizations updated (`en.lproj` / `es.lproj`)
  when you add user-facing strings.
- A feature isn't done because it compiles: it should be stable, localized,
  visually consistent, and usable across the supported layout families
  (iPhone, iPad, Mac).

## Submitting a PR

1. Create a branch from `main`.
2. Keep PRs focused — one feature or fix per PR.
3. Make sure the app builds and existing tests pass (`YomuhonTests`,
   `YomuhonUITests`).
4. Describe what changed and why. Screenshots/recordings are appreciated for
   UI changes.
5. Be responsive to review feedback — this is a small project maintained in
   spare time, so reviews may take a few days.

## Reporting bugs / requesting features

Use the issue templates. Include:

- Yomuhon version and platform (macOS/iOS/iPadOS) and OS version.
- Steps to reproduce, expected vs actual behavior.
- Whether the issue is app-side or source-side (a broken manga source usually
  belongs in the [Yomuhon-Sources](https://github.com/lukqo/Yomuhon-Sources) repo instead).

## Code of conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
