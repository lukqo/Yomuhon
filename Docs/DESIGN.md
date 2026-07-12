# Design

## Direction

Yomuhon should feel:

- calm;
- editorial;
- native;
- premium;
- timeless.

It should not feel:

- Android-like;
- decorative;
- dashboard-heavy;
- technically exposed;
- trend-driven.

The manga cover is the primary visual element. The interface supports it.

## Visual principles

### Content first

Artwork and reading actions are visually stronger than infrastructure and metadata.

### Whitespace over decoration

Prefer spacing and hierarchy over stacked cards, borders and visual effects.

### Neutral interface

Artwork provides most of the color.

The app chrome should remain restrained.

### Semantic typography

Use native semantic styles such as large title, title, headline, body and caption.

Avoid arbitrary type scales unless an established shared component requires one.

### Shared components

Before adding a new visual component:

1. Search for an existing shared component.
2. Extend it if the behavior belongs there.
3. Create a new shared component only when the pattern is genuinely new.

Do not duplicate the same button, empty state, progress row or cover treatment in multiple screens.

## Themes

Official themes:

- Slate
- Ink

All theme colors come from `AppTheme`.

Do not hardcode visible interface colors in feature views.

## Layout spacing

Preferred spacing rhythm:

- 8
- 16
- 24
- 40
- 64

These values are a design rhythm, not a reason to damage a native control or platform requirement.

## Interaction

Preferred durations:

- approximately 0.18 s for direct feedback;
- approximately 0.25 s for state changes;
- approximately 0.35 s for major transitions.

Avoid bouncing, flashy movement and decorative motion.

Respect Reduce Motion.

## Screen intent

### Library

Feels like a personal shelf.

Continue Reading is the strongest section when real progress exists.

Manual shelf membership, reading history and offline availability should not be visually confused.

### Search

Feels like browsing manga.

Results prioritize cover and title.

Source details are secondary and only appear where they help users choose a readable version.

### Manga detail

The cover, title and primary reading action dominate.

Synopsis and chapters should remain readable and calm.

Source comparison belongs below the manga-first hierarchy.

### Reader

The UI disappears.

No decorative page frames or heavy shadows.

HUD controls float above content and hide when not needed.

### Downloads

Feels like an offline library with understandable active work.

It should not become a developer-style queue inspector in the normal product UI.

### Settings

Prefer native settings hierarchy and plain language.

Technical diagnostics stay separate from normal preferences.

### Sources

Sources are supporting infrastructure.

Normal users should see availability and health in understandable language, not parser terminology, JSON details or internal cache paths.

## Accessibility

Every new user-facing feature should consider:

- VoiceOver labels;
- Dynamic Type;
- keyboard navigation on macOS where relevant;
- sufficient contrast;
- Reduce Motion;
- readable disabled states.

Accessibility is part of the definition of done.
