# Product

## Vision

Yomuhon is a native manga reading application for Apple platforms.

It is not a repository manager, parser dashboard or source testing utility. Those systems may exist internally, but the user should primarily interact with manga.

The intended user journey is simple:

1. Discover manga.
2. Save manga.
3. Read manga.

## Product principles

### Manga first

Artwork and reading take visual priority over metadata and infrastructure.

### Apple first

Yomuhon is designed for macOS, iPadOS and iOS. The product should feel natural beside Apple Books, Finder, Photos, TV and Journal without copying them.

### Editorial

Whitespace, typography and artwork create hierarchy. The interface should feel calm rather than dense.

### Native

Prefer platform conventions and SwiftUI controls when they solve the interaction well.

### Stable

A finite error state is better than an infinite loading state. A graceful fallback is better than a crash.

### Consistent

Reuse established components and interaction patterns instead of redesigning each screen independently.

## Product model

### Library

The Library is the user's explicit shelf.

Opening a manga detail does not automatically add it to the Library.

### Reading history

Starting or continuing a manga creates and updates reading progress. Reading history and manual Library membership are related but distinct concepts.

### Downloads

Downloads represent offline availability. Completed chapters must remain usable without a network connection and must not be treated as disposable image cache.

### Sources

Sources are infrastructure.

Users should not be forced to test, enable or repair a source as part of normal reading. Source health and remote configuration should be managed by the application whenever possible.

## Supported layouts

Yomuhon has two interface families.

### Regular

Used when horizontal space is regular.

Typical environments:

- macOS
- iPad landscape
- wider split-view widths

Characteristics:

- Sidebar
- Toolbar
- Multi-column composition
- Keyboard support
- Hover where appropriate

### Compact

Used when horizontal space is compact.

Typical environments:

- iPhone
- iPad portrait
- narrow split-view widths

Characteristics:

- Tab-based primary navigation
- Single-column composition
- Touch-first interaction

The layout is selected by available width and size class, not by hardcoded device model.

Sidebar and tab bar must never be shown simultaneously.

## Release philosophy

The first public release should prioritize:

- complete reading flow
- reliable offline reading
- finite network states
- source resilience
- reader comfort
- adaptive layout correctness

Cloud sync, accounts, Android and Windows are outside the initial Apple release scope.
