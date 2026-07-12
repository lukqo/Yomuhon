# Testing and Release

## Supported matrix

Before a release candidate is considered ready, test:

### macOS

- Launch from a clean build.
- Resize from minimum supported width to fullscreen.
- Verify sidebar navigation.
- Verify keyboard reader navigation.
- Search while typing rapidly.
- Open grouped results.
- Read a chapter.
- Download a chapter and read it offline.
- Quit and relaunch with queued or paused downloads.

### iPhone

- Compact navigation only.
- No sidebar.
- Search cancellation and progressive results.
- Manga detail actions.
- Reader paged and webtoon modes.
- Reader resume position.
- Download recovery.
- Airplane-mode launch with existing downloads.

### iPad portrait

- Compact layout.
- Tab navigation.
- Reader controls remain touch-friendly.
- No regular sidebar shown at the same time as the tab bar.

### iPad landscape

- Regular layout.
- Sidebar.
- Split-view resizing.
- Reader transition.
- Source/supporting screens scroll correctly.
- No simultaneous sidebar and tab bar.

## Required source failure cases

Test:

- remote source index unavailable;
- cached definitions available;
- one source times out while others succeed;
- every source fails;
- a source returns zero chapters;
- a source returns malformed HTML or JSON;
- an old manga is missing its internal source URL marker;
- a paused source later becomes healthy.

Expected result: a finite state. Never an endless spinner.

## Download cases

Test:

- one chapter;
- next 10;
- remaining chapters;
- pause;
- resume;
- cancel;
- retry failure;
- app termination during active queue;
- duplicate/equivalent chapter protection;
- source-separated local paths;
- delete one chapter;
- delete manga downloads;
- offline reading after Wi-Fi is disabled.

A completed offline chapter must remain readable without contacting the network.

## Reader cases

Test:

- resume at saved page;
- fit page;
- fit width;
- fit height;
- paged to webtoon transition;
- webtoon to paged transition;
- global HUD preference;
- previous chapter;
- next chapter;
- final chapter end state;
- keyboard navigation on macOS;
- HUD auto-hide and quick menu interaction.

## Definition of done

A user-facing feature is complete only when it:

- compiles with Xcode 14.2;
- works on supported platform families;
- respects adaptive navigation;
- uses the theme system;
- uses shared components where the pattern already exists;
- is localized in English and Spanish;
- has finite loading and error states;
- does not introduce a known offline regression;
- does not expose internal source terminology without a support/debug reason.

## Release checklist

1. Clean build.
2. Run unit tests.
3. Run UI tests that are currently maintained.
4. Complete the device/layout matrix.
5. Verify offline reading.
6. Verify remote-source fallback.
7. Check localization for new visible strings.
8. Check privacy/legal text if network services changed.
9. Review the changelog.
10. Tag only after the tested build matches the documented release candidate.
