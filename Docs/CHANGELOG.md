# Changelog

This file keeps a concise history of meaningful product and architecture changes.

It intentionally does not record every compile fix or one-line patch.

## Unreleased

### Source engine v2

- Moved provider discovery toward repository-driven declarative definitions.
- Added generic HTML and JSON API runtimes.
- Added remote `index.json` discovery.
- Added cache fallback for valid definitions.
- Added configuration-aware cache invalidation.
- Kept arbitrary remote executable code out of the source system.

### Source resilience

- Added bounded source health checking.
- Removed the requirement for normal users to press Test before reading.
- Search uses healthy sources.
- Detail and Reader can resolve a known source independently from Search enabled state.
- Added self-repair for manga records missing internal source URL markers.
- Added finite detail timeout and retry behavior.

### Search and intake

- Added concurrent, progressive multi-source search.
- Added cancellation of obsolete searches.
- Added deterministic cross-source grouping.
- Added source-family badge deduplication.
- Added manga intake cleanup for placeholder titles and duplicate candidates.
- Added metadata enrichment for missing covers and synopsis without replacing the reading source.

### Reader

- Added paged and webtoon modes.
- Added fit page, width and height behavior.
- Added chapter-to-chapter navigation.
- Added reading progress restoration after remote pages load.
- Added global dark HUD preference.
- Added keyboard navigation on macOS.
- Improved HUD stability and auto-hide behavior.

### Downloads

- Added persistent queue states and launch recovery.
- Added cancel and retry.
- Added cancellation-aware page downloads.
- Added Download current chapter, next 10 and remaining actions.
- Added cross-source chapter deduplication.
- Added source-separated download paths.
- Added deletion of chapter and manga offline files.
- Added real device storage information.

### Library

- Separated manual Library membership from reading history.
- Added explicit Add to Library behavior.
- Kept Continue Reading tied to actual reading progress.
- Added offline/downloaded manga presentation.
- Added metadata repair for saved manga missing cover or synopsis.

### Adaptive UI

- Formalized regular and compact layout families.
- Kept sidebar for regular layouts and tab navigation for compact layouts.
- Continued light/dark contrast fixes.
- Improved cover clipping and loading skeleton states.

## Historical note

Earlier development used many temporary “pass” notes in the root README. Those notes were consolidated into this changelog and the focused documentation files in `Docs/`.
