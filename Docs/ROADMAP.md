# Roadmap

This roadmap describes product direction, not a fixed delivery schedule.

## Priority 1 — Release reliability

- Finish real-device validation on macOS, iPhone and iPad.
- Eliminate remaining infinite loading paths.
- Validate download pause/resume/recovery under termination.
- Validate offline next/previous chapter behavior.
- Keep source health checks non-blocking.
- Audit source definitions before enabling them broadly.
- Review accessibility and localization gaps.

## Priority 2 — Reader polish

- Refine large-screen two-page behavior.
- Improve chapter boundary feedback.
- Keep reader preferences consistent and intentionally scoped.
- Validate Apple Pencil interactions that provide real reading value on iPad.
- Improve very large chapter memory behavior.

## Priority 3 — Library and discovery

- Improve metadata repair without changing source identity.
- Make manual Library membership, history and downloads visually unmistakable.
- Improve popular/discovery ranking with real source-backed content.
- Keep genre filtering tied to real metadata or source capability instead of plain text genre searches.

## Priority 4 — Source platform

- Continue schema hardening.
- Add stable source definitions one by one.
- Add automated validation in `Yomuhon-Sources`.
- Improve source-level metrics and health decisions without exposing technical noise to normal users.
- Upgrade parser internals only when it clearly improves reliability.

## Later

- Local CBZ/ZIP library.
- Cloud sync.
- Cross-device library synchronization.
- Accounts, only if a real product need appears.
- Additional platforms only if they do not compromise the Apple-first product.

## Explicitly not a current goal

- Tachiyomi extension compatibility.
- Android extension execution.
- Arbitrary remote code.
- Anti-bot bypass systems.
- Turning Sources into the main user experience.
