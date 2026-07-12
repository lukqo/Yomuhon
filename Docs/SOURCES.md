# Source Engine

## Product rule

Sources provide manga. They are not the product.

Normal reading should not require a user to press Test, manage parsers or understand the remote repository.

## Current model

Yomuhon uses generic declarative runtimes for remote source definitions.

The remote catalog is discovered from:

```text
https://raw.githubusercontent.com/lukqo/Yomuhon-Sources/main/index.json
```

Valid definitions are cached locally.

The source loader should prefer:

1. latest valid remote definitions;
2. cached definitions from the last successful refresh;
3. bundled fallback definitions when they exist.

A failure in one definition must not invalidate the complete source catalog.

## Remote code policy

Remote source files are configuration, not executable plugins.

Yomuhon should not:

- execute arbitrary remote Swift or JavaScript;
- load Tachiyomi/Android extension packages;
- decompile third-party extensions;
- hide a headless browser to bypass a site's protections;
- bypass Cloudflare or other anti-bot systems.

## Validation

Remote definitions must be validated before use.

At minimum:

- supported schema version;
- matching source identifier;
- supported engine mode;
- HTTPS URLs;
- allowed-domain validation;
- unique source identifiers;
- acceptable repository status.

Definitions marked broken, disabled or deprecated should not become active reading sources.

## Health

Source health is app-managed.

Expected behavior:

- health checks run in the background on a bounded schedule;
- a single transient failure should not immediately pause a source;
- repeated failures may pause it from Search;
- a later successful check can restore it;
- Detail and Reader may still resolve a known manga source directly when appropriate.

Diagnostic tests are for support and development. They are not a mandatory activation step for normal users.

## Smoke test

A full source diagnostic should verify a real reading path:

1. Search returns a plausible manga.
2. Detail resolves.
3. At least one chapter is returned.
4. At least one real page is returned from a chapter.

A source that only returns catalog results is not a verified reading source.

## Intake

Incoming source results pass through a normalization/intake layer.

The layer may:

- clean visible titles;
- reject obvious placeholders;
- choose the best duplicate candidate;
- group equivalent manga across sources;
- enrich missing cover or synopsis metadata.

It must preserve internal information required by the reading source to resolve details and chapters.

Metadata enrichment must not silently change the reading source identity.

## Cache invalidation

Source configuration versions fingerprint source-dependent caches.

When a source definition changes, stale search/detail/page cache entries may be invalidated.

Explicit offline downloads must not be deleted as ordinary cache.
