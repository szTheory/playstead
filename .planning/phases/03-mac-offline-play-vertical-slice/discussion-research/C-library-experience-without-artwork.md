# Gray Area C — Library Browse Experience Without Artwork

**Phase:** 3 — Mac Offline Play Vertical Slice
**Constraint (LOCKED):** No metadata/artwork providers. Titles come from No-Intro filename parse or header evidence (D-22); catalogue payload is D-23 (system, status, display_title, tags{region, languages, version, dev_status}, members, recognition, attention). Seven systems + unknown. LIBR-04 hides empty systems. Curation nouns: Favorites / Collections / Continue / Recent / Queue (sync semantics are area B; only presentation decided here). Cache mechanics are area D; only the six CACH-02 states' presentation decided here.
**Design authority:** EXPERIENCE-ETHOS.md — "beautifully designed console that respects ordinary files"; quiet health; motion explains state; controller-first, never controller-only; a library is not an inventory dump (§15).

---

## Decision Point 1 — Visual identity of a library with no artwork

### Prior art survey

| Product | No-artwork behavior | Lesson |
|---|---|---|
| OpenEmu | Generic per-system cartridge/box silhouette with title beneath | System-shaped placeholders read as "empty slots waiting for art" — the library feels unfinished, which is exactly wrong when art is *deliberately* absent |
| Steam | Missing grid capsule = flat dark tile with the raw title text | Functional but reads as broken; users install SteamGridDB to escape it |
| Plex / Jellyfin | Gray poster with title text or blurred generic art | Placeholder-as-apology; the design assumes art will arrive |
| ES-DE / EmulationStation | Theme-dependent text-list fallback; carousel with text labels | Text-first CAN feel like a console when typography and spatial rhythm carry the design |
| Calibre | Procedurally generated typographic covers (title + author on colored ground) | Deterministic typographic covers are legible and honest, but Calibre's look is widely read as utilitarian, not beautiful — execution quality is everything |
| Letterboxd | Gray poster, film title set in the poster area | Acceptable because it is rare; at 100% of items it would collapse |
| iTunes/Music pre-artwork era | Note glyph on soft gradient tile | A single repeated glyph at scale = wallpaper; zero scannability |
| Notion / Linear / Height | Typographic-first rows and cards, small colored accents, no imagery at all | Modern proof that an imageless information surface can feel premium: type scale, spacing, and restrained accent color do the work |
| Roon / DJ software (Rekordbox, Serato) | Dense typographic tables with strong filtering, tiny art optional | Ethos names DJ library management as an influence: rapid filtering + recency/queue collections in a dense, type-led surface |

**Synthesis:** every product that treats missing art as a *placeholder* looks broken; products that design a *typographic identity* (Notion, Linear, ES-DE text themes, editorial design generally) look intentional. Phase 3 must do the latter: artwork absence is the design, not a gap.

### Options — card identity

| Option | Pros | Cons | Complexity | Recommendation |
|---|---|---|---|---|
| A. Typographic tile: large title, per-**system** accent color, small system monogram/badge | Intentional, editorial, calm; system color groups shelves coherently; scales to web console with plain CSS; nothing to regenerate when real art arrives | Needs genuinely good type discipline (truncation, hyphenation, long No-Intro titles); many same-system tiles look uniform | SwiftUI card view + design tokens shared conceptually with Tailwind console — Risk: long-title truncation, dynamic type | **Rec (primary).** Reads as designed-for-text, not waiting-for-art |
| B. Per-title hash color (letter-avatar style, Dicebear/identicon family) | Every game visually distinct; deterministic; cheap | Color confetti at 500 items destroys shelf calm; hue carries no meaning (violates non-color-only encoding spirit); identicon aesthetic reads gimmicky/dev-tool, not console | Same surface as A — Risk: visual noise, accessibility of random hues on dark ground | Rec only as a *subtle* secondary differentiator (e.g., hashed ornament), never as the primary tile identity |
| C. Procedural placeholder "art" (generated patterns, fake box shapes, per-system cartridge silhouettes) | Playful; nods to hardware nostalgia | High kitsch risk; fake boxes imply real boxes are missing; expensive to make tasteful across 7 systems and 2 renderers (SwiftUI + HEEx); throwaway once enrichment ships | Custom asset pipeline in two stacks — Risk: taste, duplicated implementation, dark/light variants | Avoid for Phase 3. Revisit only if a designer produces something that survives the "would we keep this even with art?" test |
| D. No tiles at all — list/table only | Cheapest; densest; DJ-software lineage | Grid-of-shelves is much of what makes a "console" feel like a console; Continue/Favorites as a table feels like a file manager — the exact failure mode PROJECT.md names | Minimal — Risk: fails the "beautifully designed console" bar for the home surface | Rec as the *browse-all density mode*, not the identity |

### Options — grid vs list vs both

| Option | Pros | Cons | Complexity | Recommendation |
|---|---|---|---|---|
| Grid only | Console-like; big focus targets for controller | Weak at 500+ text-only items; scanning a text grid is slower than a text column (eyes must travel 2 axes) | One layout — Risk: scannability at scale | Rec if library ≤ ~100 and curation rows dominate |
| List only | Fast vertical scanning; sortable columns; dense | Home surface feels like Finder; horizontal shelves impossible | One layout — Risk: identity | Not alone |
| **Both: horizontal typographic-tile shelves for curated rows (Continue, Favorites, Recent, Queue) + vertical list for system/all-games browsing, with a grid/list toggle** | Matches ethos §15 (lead with curation, make exhaustive views excellent); each layout used where it wins; mirrors Music.app/OpenEmu duality | Two layouts to build and keep accessible in both clients | 2 layout components × 2 clients — Risk: parity drift, double focus-engine testing | **Rec (primary).** Curation = shelf ritual; browsing 500+ = scan ritual |

**Density guidance:** tiles ~180–220 pt wide on Mac (≥ 5 visible per shelf row at default window), 16:11-ish landscape ratio (deliberately NOT box-art portrait — portrait tiles promise covers); list rows 44–52 pt with title, system chip, tags, one status slot. Web console: same shelves collapse to horizontally scrollable rows; list is the mobile default.

---

## Decision Point 2 — Information hierarchy per item

D-23 gives per item: display_title, system, status(complete|incomplete), tags{region, languages, version, dev_status}, recognition status, attention flag. CACH-02 adds six local states: server-only, queued, partial, verified-local, pinned-offline, safe-to-evict (plus WEB-AND-CLIENT-ARCHITECTURE's missing-dependency and launch-preflight gating).

### The clutter trap (adversarial finding)

Worst case per card: title + system + region + language + version + dev_status + "Not yet identified" + cache state + pinned + incomplete-set + attention = 11 signals. Any design that shows them all fails "quiet by default." Rule: **each card gets exactly one primary status slot + one identity line + tags on demand.**

### Options

| Option | Pros | Cons | Complexity | Recommendation |
|---|---|---|---|---|
| **A. Three-zone card: (1) Title dominant, max 2 lines; (2) meta line = system monogram chip + region/version as quiet text chips; (3) single status slot = highest-priority state as glyph+shape (+ text label in list view)** | One glance = what it is, where it runs, whether it can play now; scales to 500+; quiet when healthy | Requires a strict state-priority ladder; some info (languages, dev_status) pushed to hover/detail | Priority ladder function shared by both clients — Risk: ladder disagreements between Mac and web | **Rec.** |
| B. Show all states as a badge row | Complete information | Alert-stream aesthetic; violates ethos §3; scan speed collapses | Simple — Risk: noise | Avoid |
| C. Color-coded card borders/backgrounds per state | Instant at distance | Color-only encoding fails QUAL-01/WCAG 1.4.1; 6 states exceed reliable hue discrimination; wrecks the calm system-color identity from DP1 | Simple — Risk: accessibility failure | Avoid as sole channel; a border may *accompany* the glyph |

### State-priority ladder for the single status slot (highest wins)

1. Attention required (humane, rare — D-26 keeps this small)
2. Missing dependency / incomplete set (blocks play)
3. Downloading (progress ring with % — motion explains state)
4. Queued (hollow ring)
5. Verified locally / Ready (subtle filled check; **quiet** — the healthy state is the least decorated)
6. Pinned offline (pin glyph, may coexist with Ready as a compound "pinned check")
7. Server-only (small cloud outline — the default for a fresh pairing, so it must read as normal, not as a problem)
8. Safe-to-evict is NOT a card badge — it is a storage-view concept (area D presentation); on cards it appears only in the detail/context menu ("Remove local copy — re-downloadable")

**Non-color encoding:** every state = distinct glyph + distinct shape (cloud / hollow ring / partial ring / check / pin), text label in list rows and on focus/hover in grid, full sentence for VoiceOver ("Chrono Cross, PlayStation, two discs, downloading, 40 percent"). "Not yet identified" stays exactly the D-26 web treatment: quiet inline text badge on the meta line, never in the status slot, never a warning.

**Scannability at 500+:** list view is the scan surface — sortable by title/system/recency/local-availability, type-select jumps, and LIBR-02 filters (system, availability, tag). Title tail-truncates with full title on tooltip/focus; No-Intro parenthetical junk is already stripped into tags by D-22, which is precisely what makes typographic-first viable.

---

## Decision Point 3 — Navigation model

### Options — IA container

| Option | Pros | Cons | Complexity | Recommendation |
|---|---|---|---|---|
| **A. Sidebar (source list): Home/Continue, Favorites, Collections, Queue, Recent, then Systems (non-empty only), then Storage/Settings** | Native Mac idiom (Music, Finder, TV.app); LIBR-04 hiding is natural; collections grow without re-architecture; maps 1:1 to a collapsible LiveView sidebar → mobile nav drawer/tabs | Sidebar is pointer/keyboard-native; controller needs an explicit section-cycling affordance | NavigationSplitView + focusSection — Risk: controller/sidebar interplay | **Rec.** |
| B. Top-level tabs (console dashboard style, à la Switch/PS5) | Extremely controller-legible | Caps section count; unusual on Mac; collections don't fit tabs; diverges from LiveView layout | Custom — Risk: Mac-convention violation, parity | Avoid as the container; steal its *shoulder-button section cycling* |
| C. Single scrolling home of shelves, no persistent nav | Most console-like first screen | Search/filter/systems browsing needs a home anyway; hides the IA | — | Fold in: the sidebar's default selection IS a shelf-based Home |

### Controller model (Mac, Game Controller framework)

- **Spatial focus:** d-pad/left-stick moves focus; SwiftUI `.focusable()` + `@FocusState` + `.focusSection()` per shelf and per sidebar group so vertical movement crosses shelves predictably (tvOS-style grid logic even though this is macOS — grid/linear layouts keep the engine predictable).
- **LB/RB (shoulders): cycle sidebar sections** without entering the sidebar — the console-dashboard trick grafted onto a Mac sidebar. Left stick click or a dedicated button focuses the sidebar directly for fine navigation.
- **A/Cross = activate; B/Circle = back; Menu = context actions** (favorite, queue, download here, pin) via a controller-reachable context sheet — parity with right-click and the keyboard Action menu.
- **Visible focus everywhere (QUAL-01):** 2 pt accent ring + slight scale on tiles; row highlight in lists; focus ring identical in meaning for keyboard Tab/arrow users. Never controller-only: every controller path has a keyboard/pointer/VoiceOver equivalent, and controller disconnect never strands (ethos §8 — pointer/keyboard remain live at all times).
- **Search with a controller (LIBR-02):** a search *button* in scope (Y/Triangle shortcut) opens a search overlay: on Mac, physical keyboard is the expected 99% path (it's a computer); the overlay also offers filter chips (system, availability, recently added) that are pure d-pad targets, so a controller-only user filters instead of typing. An on-screen keyboard is explicitly deferred — filter chips + curation shelves keep controller users un-stranded without building one. Adversarial note: do NOT auto-focus a text field when opened by controller; focus the chip row first.

### Web console mapping

Same IA nouns, same order: LiveView gets a responsive sidebar (collapses to a drawer/top nav under `lg:`), same shelves on Home, same list for systems, same status-slot component vocabulary in HEEx. No controller support promised in the browser for Phase 3 (keyboard/pointer/screen-reader are QUAL-01's web surface); the IA parity is what keeps the two clients feeling like one product. The existing `library_live.ex` list is the seed of the system-browse list view; it gains the meta-line/status-slot vocabulary rather than being replaced by something alien.

---

## Decision Point 4 — Empty states & first-run

| Situation | Treatment | Rationale |
|---|---|---|
| Newly paired Mac, nothing downloaded | **Not an empty state.** LIBR-01 means the full catalogue appears immediately, every card quietly cloud-marked server-only. One-time dismissible banner: "Your library lives on your server. Download the games you want to play here." + a small "recommended first downloads" shelf (smallest verified titles) honoring ethos §17's new-computer ritual | The migration story is "browse first, fetch on demand"; an empty grid would betray the core promise |
| Server library has zero imports | Single calm card: "Nothing in your library yet" + primary action linking to import (web: `/import`; Mac: the drop-to-import flow) — mirrors existing `library-empty` card | One invitation, no tutorial theater |
| Continue/Recent before any play | Shelf hidden entirely (not shown empty) until first launch/play event exists | Quiet by default; empty shelves are noise |
| Favorites/Queue/Collections empty | Shelf hidden on Home; noun still present in sidebar with a one-line explainer when visited ("Favorites you mark appear here — press ♥ or Menu on any game") | Nouns must be discoverable (they're the curation contract) but never nag |
| Empty/unconfigured systems (LIBR-04) | Hidden from sidebar by default. Footer affordance "Show all systems" reveals them with counts (0) and, where relevant, readiness notes; a system auto-appears the moment it gains its first title | Counts/readiness "when useful," not always |
| Unknown-system items | A single "Unidentified" bucket at the bottom of Systems, visible only when non-empty, carrying the D-26 quiet badge philosophy and the one dismissible reference-pack hint | Keeps 312 mystery files from colonizing the sidebar |
| Progressive settings disclosure | System/core/BIOS/controller settings surface *in context*: at first download of a system, and in the preflight panel as remedies ("This game needs a BIOS — validate one now"), not as a global settings maze. Advanced/diagnostics behind a Details disclosure per ethos §11 | Readiness-before-failure places configuration where the need appears |

Adversarial: the recommended-downloads shelf must never auto-download (custody principle — nothing moves bytes without an explicit choice), and the first-run banner must not reappear per-device-pairing on the web console (it is a Mac-client ritual).

---

## Decision Point 5 — Motion & performance

**What motion explains here (ethos §9, Kowalski test — each animation must answer "what does this explain?"):**

| Moment | Motion | Explains |
|---|---|---|
| Download progress | Determinate progress ring filling in the status slot | How much remains; work is alive |
| Verify completion | Ring completes → morphs to check with a single subtle settle (no confetti) | The bytes are now proven; the moment CACH-02 state changes |
| Queued → downloading | Hollow ring begins filling | Your request was picked up |
| Focus movement | ~120 ms ring/scale transition following spatial direction | Where you are; spatial continuity for controller users |
| Shelf → detail | Standard navigation transition (push/zoom from card) | Cause and effect; where detail came from |
| Eviction/removal | Card status crossfades to cloud state in place — item does NOT vanish | Removing a local copy is not removing the game (repository vs cache promise, ethos §16) |
| Attention arrival | None on the card grid; the Needs-attention count updates quietly | Exceptions are humane, not startling |

**Banned:** ambient idle motion on tiles, staggered shelf fly-ins on every open, bouncing badges, marquee/auto-scrolling titles (scroll title on focus only, if at all — prefer tooltip/two-line wrap), any animation that delays input.

**Reduced motion (QUAL-01):** progress rings keep animating fill (that is state, and it's the convention even under reduce-motion — but strip the completion morph to an instant swap), focus changes become instant ring moves without scale, navigation transitions become crossfades. Implement via `accessibilityReduceMotion` / `prefers-reduced-motion` on the two clients with one shared spec table so behavior matches.

**Performance:** the app opens from local read models with zero network wait (WEB-AND-CLIENT-ARCHITECTURE §Mac client) — therefore **no skeleton screens on any previously synced view**; skeletons/placeholders appear only on genuinely-first catalogue sync. Typographic tiles are a performance gift: no image decode, no thumbnail cache, trivially virtualized (`LazyVGrid`/`LazyHStack`; LiveView streams for the list). Target: library window interactive in < 1 s cold, shelf scrolling at display refresh with 500+ items. Text rendering is cheap; guard instead against layout thrash from variable-height titles (fix tile heights, clamp to 2 lines).

---

## Adversarial pass (cross-cutting)

1. **"Tasteful typographic" is carried entirely by execution.** The difference between Linear-quality and Calibre-quality is type scale, spacing, and restraint — budget a real design pass (UI hint: yes / gsd-ui-phase) before implementation; the option choice alone doesn't buy beauty.
2. **System accent colors must not become state colors.** Reserve one accent family for identity (system tint) and a separate neutral+semantic set for status glyphs, or the two vocabularies collide.
3. **Seven systems + unknown = 8 hues max — fine; but hues must pass contrast on the dark console ground and carry a redundant monogram (GBA, SNES…) since color is never the only channel.**
4. **Parity drift is the biggest long-term risk.** Two renderers (SwiftUI, HEEx/Tailwind) implementing one vocabulary will diverge unless the status ladder, state glyph set, IA nouns/order, and empty-state copy live in one shared spec document that both implementations cite.
5. **Don't let area B/D leak in:** shelves present curation nouns without implying sync behavior ("Favorites" shows a heart, not a sync icon); safe-to-evict presentation defers to area D's storage view.
6. **Long No-Intro titles** ("Legend of Zelda, The - A Link to the Past (USA) (Rev 1)") — D-22 already strips tags into structured fields; confirm the "The" article handling for sort order (sort by transposed article, display as-is) so alphabetic scanning works.
7. **Launch affordance discipline:** Play appears enabled only post-verified-preflight; on server-only cards the primary action is "Download," never a grayed Play that reads as broken.

## Sources

- Project documents cited inline: PROJECT.md (Experience Constitution), EXPERIENCE-ETHOS.md (§3, §8, §9, §15, §16, §17), ROADMAP.md §Phase 3, REQUIREMENTS.md LIBR-01…05/CACH-02/QUAL-01, 02-CONTEXT.md D-22/D-23/D-26, WEB-AND-CLIENT-ARCHITECTURE.md §Mac client interaction model, `playstead_web/live/library_live.ex`
- tvOS focus engine and 10-foot focus design: https://www.oxagile.com/article/tvos-focus-engine-navigation-guide/ ; https://blakecrosley.com/blog/tvos-focus-engine-swiftui ; https://www.tothenew.com/blog/how-to-control-focus-in-swiftui-for-apple-tv-apps/
- Apple HIG game controls (via ethos): https://developer.apple.com/design/human-interface-guidelines/game-controls
- Motion restraint: https://emilkowal.ski/ui/you-dont-need-animations ; https://emilkowal.ski/ui/great-animations
- Deterministic letter-avatar/identicon pattern and its limits: https://en.wikipedia.org/wiki/Identicon ; https://www.dicebear.com/ ; https://morgancarter.com.au/design-solutions/placeholder-avatars ; https://dev.to/joshuaslate/deterministic-react-avatar-fallbacks-5ghb
- Media-server placeholder-as-apology pattern: https://github.com/jellyfin/jellyfin/issues/15849 ; https://github.com/ilarramendi/BetterCovers ; https://github.com/fscorrupt/Posterizarr
- Non-color state encoding: WCAG 1.4.1 Use of Color (W3C)
