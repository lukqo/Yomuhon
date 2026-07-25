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

1. latest valid definitions published by `Yomuhon-Sources`;
2. definitions cached from the last successful repository refresh.

Yomuhon ships no provider definitions and no provider-specific adapters. On a fresh installation without network access, the catalog is empty until the repository can be reached. The cache contains only definitions that were previously downloaded from GitHub.

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

## Publication semantics

The remote catalog is the publication authority.

- `index.enabled` decides whether a source is published to the app.
- `index.status` describes repository lifecycle state. `stable` and `testing` sources may be used; `broken`, `disabled` and `deprecated` sources are excluded.
- Schema V1 still carries `enabledByDefault: false` as a legacy compatibility sentinel. It is not an activation switch and must never require a local Test action.
- Temporary runtime health is local state managed by the circuit breaker and must remain separate from repository publication state.

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

A source that only returns catalog results is not a proven readable source.

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

## Mixed-operation sources

A provider may expose different public interfaces for different operations. A source can keep a source-wide `engineMode` and override only selected capabilities with `operationModes`:

```json
{
  "engineMode": "html",
  "operationModes": {
    "chapters": "json-api"
  }
}
```

Supported operation keys are `popular`, `search`, `details`, `chapters`, `pages` and `genres`. Existing definitions without `operationModes` keep their previous behavior.

An API request may declare its own HTTPS `baseURL` when the public JSON endpoint uses a different host from the HTML website. Chapter API operations can also:

- derive variables declaratively from `mangaURL` or `mangaID`;
- store a public reader URL from `urlPath` on each chapter;
- hand that chapter URL back to an HTML pages operation.

Some providers encode the stable work identifier in a query parameter. `identity.preserveQueryItems` declares only the public query names that must survive canonicalization:

```json
{
  "identity": {
    "preserveQueryItems": ["title_no"]
  }
}
```

All other query items are still removed. This contract remains declarative and repository-controlled; it does not add provider adapters or bundled source definitions to the app.

