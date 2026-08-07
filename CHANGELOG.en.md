# Changelog

All notable changes are documented here. Format — [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning — [SemVer](https://semver.org/).

## [0.9.34] — 2026-08-08

### Added
- **The premade targets panel now covers both teams.** It used to list known
  premade players on the enemy side only; there is now a second section, "Your
  team". Buttons behave identically in both: left-click to target, right-click
  to set focus. An empty section is not drawn at all.
- **The panel minimizes to a small button.** The close button in the top-right
  corner puts the panel away entirely and leaves a compact button with the
  counts in its place — drag it anywhere, click it to bring the panel back. It
  works in combat, not just outside it.
- **Size settings** (Esc → Options → AddOns → PremadeIQ): panel scale 70–150%
  and 1–6 name columns.

### Fixed
- **The leader mark no longer renders as an empty box.** The stars in the list
  (and the separators in the header) now use characters the game font can
  actually draw.
- **Long names are no longer clipped.** Column width is measured from the
  longest name on screen, so a full `Name-Realm` fits on its plate.
- **Your own team is identified correctly under mercenary mode.** The side now
  comes from the same battlefield API the scoreboard itself uses rather than
  from the character's faction, which would swap the two sections around.

## [0.9.33] — 2026-08-07

### Fixed
- **Matches you joined late no longer disappear.** If you dropped into a battle
  already in progress (Wintergrasp, Alterac Valley and Ashran all allow it), the
  server concluded you had been in two matches at once and threw the whole match
  away: absent from the site, absent from premade detection. The cause is that
  the duration the game reports measures the **battle**, not how long you were
  in it. The addon now reports when it entered. On prod this was losing 2.5% of
  all matches.

### Added
- **A separate notice for people who take raid lead but run no premade.** They
  no longer raise a premade alert; instead one neutral line reads "Usually takes
  raid lead". No roster, no count, no verdict — the metric that marks them
  catches ordinary raid leaders too.
- **The addon records who was on the scoreboard before substitutions.** Combat
  numbers for players who left cannot be recovered in 12.0.x, but names are
  always readable, so one snapshot is taken once the scoreboard has demonstrably
  finished loading. This lets the site tell late joiners again, and stops the
  "deserter" mark from sticking to someone who merely arrived later. The
  snapshot rides the scoreboard updates the addon already receives and switches
  itself off the moment it is captured, so it adds no polling.

## [0.9.32] — 2026-08-03

### Fixed
- **The final scoreboard no longer ships empty.** In 12.0.x the combat numbers
  (damage, healing, killing blows, deaths) are sometimes handed back as "secret
  values": they cannot be read, and an `or 0` check does not catch them because
  a secret is truthy in Lua. The row was then stored empty, making a player who
  fought the whole match look like they did nothing. The addon now waits for the
  numbers to become readable before saving (up to 4 attempts) and explicitly
  zeroes only what genuinely could not be read.
- The objective-point sum was computed on a possibly-secret value, which could
  abort the whole end-of-match capture.

### Added
- The addon now tells the server how many scoreboard rows stayed unreadable.
  The server no longer draws conclusions about who left early from such a match.

## [0.9.31] — 2026-08-01

### Fixed
- **The panel could revert to an outdated roster.** If the roster changed during
  combat and then went back to what was already on screen, the obsolete queued
  update was not dropped — and leaving combat applied it over a correct list.
  A roster matching the display now clears any pending update.
- Scan timers scheduled at match start no longer survive into the next match:
  they are cancelable now, and every callback checks the match generation.
- The internal scanning flag is cleared even on error — a failure in filtering
  could previously wedge every later panel update.

### Added
- **A "•" marker in the header** while an update waits for combat to end, so the
  list on screen never lies about how fresh it is. It clears the moment the
  roster is applied.
- A 2-second out-of-combat check, so the short lulls between fights are used to
  apply deferred updates instead of waiting for the next scoreboard event.

### Changed
- Requesting scoreboard data is now separate from reading the cache: the event
  handler no longer fires a second request that could push the server's response
  under its own throttle.
- The startup scan burst is shorter (0.5–10s); the periodic check covers the rest.
- The panel is fully English now: its tooltips (player role, premade list, click
  hint) follow the header and stay English on every client.

## [0.9.30] — 2026-08-01

### Fixed
- **Clicks on the known-premade panel now work.** The buttons responded to
  neither left- nor right-click: the game picks which click edge performs the
  action from the `useOnKeyDown` attribute, falling back to the
  `ActionButtonUseKeyDown` setting. That setting is on by default, so the action
  was expected on key-down while the buttons were registered for key-up only —
  the click was swallowed silently, with no error. The attribute is now set
  explicitly and always matches the edge the buttons register for.

### Added
- **Right-click sets the player as focus** without dropping your current target
  (right-click was not wired up at all before). Tooltip hint updated.

### Changed
- **Panel styling.** The near-black plate with white borders is replaced by a
  muted dark background and a soft warm border. Buttons highlight on hover,
  premade leaders get a warmer plate, and the header is gold.
- The panel header now stays English on every client, like the premade alert
  lines.

## [0.9.29] — 2026-07-17

### Fixed
- The enemy group-leader ("crown") counter no longer fires spuriously in the
  open world after an abnormal battleground exit (kick / disconnect / leaving
  without a match-complete): on such an exit the Collector now stops its timers
  instead of continuing to poll nameplates with a stale "this is an EBG" flag.

## [0.9.28] — 2026-07-17

### Fixed
- The known-premade panel now uses only the database's strict confirmed roster:
  at least five shared matches and a share strictly above 25%. The loose legacy
  `members` list can no longer add incidental co-players.
- When a player is linked to multiple premades, the website, catalog, and addon
  use one canonical winner. Shared mercenary entries receive triple weight.

## [0.9.27] — 2026-07-16

### Added
- **Clickable known-premade target panel.** During a battleground, PremadeIQ now
  shows only enemy players present in the catalog as premade leaders or members.
  Left-clicking a compact button securely selects that player with an exact
  `/targetexact`; leaders are starred, names use class colors, and tooltips list
  the associated premades.
- The panel can be dragged out of combat. Secure buttons are pre-created, while
  roster and layout changes during combat lockdown are deferred until combat
  ends, avoiding taint and blocked-action errors.

## [0.9.26] — 2026-07-15

### Changed
- Copied premade alerts now start with `[PremadeIQ]`, making the message source
  immediately visible in chat.

## [0.9.25] — 2026-07-04

### Added
- **Enemy group-leader counter.** Every party that queued together keeps its
  leader crowned inside the raid — so several simultaneous crowns on the
  enemy team mean pre-formed groups. The addon counts those crowns on visible
  enemy nameplates, and when there are two or more, the alert gains an
  "Enemy group leaders spotted: N" line (it also appears without a catalog
  premade in the match). Only visible nameplates are counted, so the real
  number of groups is always ≥ the shown one; enemy nameplates must be
  enabled (default V key).
- **Group leaders in match stats.** The match record now includes your own
  team's group leaders and the maximum simultaneously visible enemy crowns —
  one more premade signal for the community database and the website.

## [0.9.24] — 2026-06-28

### Changed
- **Premade alert is now multi-line.** The on-screen premade warning now shows
  the full breakdown — each enemy premade leader and how many of their players
  are in the match (top 3, plus an "…and N more" line) — in its own banner, so
  you no longer have to fish it out of chat. It fades on its own after a few
  seconds and never intercepts a click or your movement keys.

## [0.9.23] — 2026-06-23

### Changed
- **Housekeeping.** Removed unused legacy code and settings and simplified the
  options panel. No change to how your data is handled — PremadeIQ still records
  match stats only to your local SavedVariables and sends nothing out by itself;
  contributing to the community database stays a separate, optional step via the
  PremadeIQ Uploader.

## [0.9.22] — 2026-06-21

### Added
- **Leaderless premade alert.** The start-of-match alert now also fires when a
  premade's marked leader isn't in the battleground but six or more of their
  confirmed regulars are on the enemy team — catching a premade whose leader sat
  out or queued on an unmarked alt. It shows a distinct "leader not here" wording
  and is treated as a confirmed premade. Requires full access (the confirmed
  roster ships only to patrons) and the latest Uploader; on an older catalog the
  alert simply behaves as before (leader-present only).

### Changed
- **Premades are tracked by a stable id, not a display name.** A leader's alts
  no longer split or double-count one premade, and presence is judged per group.

### Fixed
- **Silent premade alert at match start.** A spurious `Reset()` from
  `PLAYER_ENTERING_WORLD` (while `IsBattleground()` was still `false` during world
  load) killed both auto-scan channels for the rest of the match. Added a 15-second
  grace gate from `PVP_MATCH_ACTIVE`: a false "left the BG" in the opening seconds no
  longer resets state. Committed `03ea999`, verified in-game 2026-06-18. (0.9.21 not
  cut/published yet — the fix lives only in source.)

## [0.9.20] — 2026-06-14

### Added
- **Precise cleanup via the Uploader handshake** (`Database.lua`, new
  `UploadState.lua`). The Uploader writes a file into the addon folder with a
  cursor saying "samples are server-confirmed up to point X" (per account, by
  `installId`), and on world-enter the addon deletes exactly the confirmed
  samples (`PruneUploaded`) instead of guessing by age. The 0.9.19 heuristic
  (30-day window + cap of 4000) stays as a **backstop** for when there is no
  cursor / it's stale. Safety: with a missing/mismatched `installId`, or a
  stale, lowered or future cursor, the addon deletes **less**, never losing
  un-uploaded data; your own character is untouched; samples without `endedAt`
  are kept. The cursor is monotonic (`lastSamplesUploadedThrough`) and clamped
  against future values. The first handshake needs one `/reload` cycle (the
  addon generates `installId`, the Uploader sees it after SavedVariables are
  flushed to disk).

### Fixed
- **Crash generating `installId`** (`Database.lua`): the code called
  `math.randomseed`, which is absent from the WoW sandbox, and errored out.
  Fixed (shipped in the published 0.9.20 zip).

## [0.9.19] — 2026-06-14

### Fixed
- **SavedVariables no longer grows without bound** (`Database.lua`). The
  `players` table kept every player ever seen in an Epic BG forever (in
  production: 29,587 entries, `PremadeIQ.lua` ≈46 MB), which made WoW slow to
  write it on logout (slow close) and slow to load on login. It now keeps a
  rolling window: players not seen for more than 30 days are evicted, and the
  total is capped at 4000 (LRU by `lastSeen`); your own character is untouched.
  The sweep runs on world-enter (once `UnitGUID("player")` is known) and after
  each match. This data is only needed for the Uploader — in-game the premade
  alert reads `KnownPremades.lua`, not this table. `rawStats` is left alone
  (deferred to a follow-up). Marker `PremadeIQ_DB.pruneVersion`, one diagnostic
  line in `collectorLog`.

## [0.9.18] — 2026-06-14

### Changed
- **`## Interface` bumped `120000 → 120005`** for the current live client 12.0.5
  (build 67823) — no "out of date" flag in addon managers.
- **Clearer first-run wording**: the welcome dialog now spells out that the
  addon writes match stats locally to SavedVariables, and that contributing to
  the community database is a separate, optional step via the Uploader app. Text
  localized (en/ruRU).

### Added
- `LICENSE` (All Rights Reserved) bundled; vendored libraries keep their own
  licenses.

## [0.9.17] — 2026-06-13

### Changed
- **The "Copy premade alert" button and its strings are now English even on a
  ruRU client** (`Locales.lua`). The premade call-out is pasted into the
  English-facing community (`/rw`, Discord), so the copy flow (button, its
  tooltip, the `PremadeCopyTip`/`PremadeCopyHint`/`PremadeCopyNone` hints) is
  fixed to English regardless of client language. The premade alert itself
  (`PremadeDetected`, etc.) stays localized.

## [0.9.16] — 2026-06-06

### Added
- **EBG filter: the addon collects Epic BGs only** (plan:
  `docs/ebg-map-filter-plan.md`, externally reviewed). Whitelisted instance map
  ids (`ns.EBG_INSTANCE_IDS` — a mirror of the server's `EBG_MAP_NAMES`):
  Alterac, Isle of Conquest, Ashran, Wintergrasp, Korrak's Revenge, Deephaul
  Ravine. Arenas / normal BGs / blitz are no longer written to SavedVariables
  or sent to the server (previously ~17% of uploads were quarantined as
  `non_ebg_map`). The gate is three-layered: PVP_MATCH_ACTIVE (Deserter/
  PremadeAlert don't start), UPDATE_BATTLEFIELD_SCORE (stale windows from a past
  Epic don't scan the wrong scoreboard), PVP_MATCH_COMPLETE + a hard guard in
  SnapshotMatch itself (which also covers manual `/piq snapshot`).
- Diagnostic ring buffer `PremadeIQ_DB.collectorLog` (50 lines) — gate
  decisions are recoverable from SavedVariables.

### Fixed
- **Real Epics are no longer lost to an id-space collision** (Collector.lua). If
  `GetInstanceInfo()` no longer returned an instance id at snapshot time
  (teleport to a capital), the code substituted **UiMapID** from
  `C_Map.GetBestMapForUnit` — a different id space the server whitelist doesn't
  know → ~3% of real Epics (30 matches in production) were quarantined with a
  `map_name` like "Silvermoon". The instance id is now captured on
  PVP_MATCH_ACTIVE and used as the fallback; the UiMapID fallback was removed.
- `/piq version` and the load line showed a hardcoded `0.9.2` — the version is
  now read from the toc (`C_AddOns.GetAddOnMetadata`).

## [0.9.15] — 2026-06-06

### Security
- **The distribution zip no longer carries the live premade catalog**
  (package_addon.py). The working copy of `KnownPremades.lua` is GOD-tier data
  that the owner's Uploader rewrites hourly; it was leaking into the public
  archive and bypassing the server's tier-gating. The zip now always ships a
  neutral stub (`leaders = {}`), plus a hard guard that fails the build if
  anything but the stub slips into the archive. Each user gets the catalog their
  own tier earns, only through their own Uploader.

## [0.9.14] — 2026-06-04

### Changed
- **Deserter detection stops re-capturing the roster once your whole group is
  collected** (Deserter.lua). The early-stop threshold used to be hardcoded at
  `60`, but after the move to raid tokens (≤40 in an Epic) it became
  unreachable, so the event re-capture spun the full 30s for nothing. The
  threshold is now the current group size (`GetNumGroupMembers`); the enemy
  scoreboard is an optional bonus.

## [0.9.13] — 2026-06-04

### Fixed
- **Deserter detection: the starting roster is now taken from your own team via
  raid/party unit tokens, not the scoreboard** (Deserter.lua). GUIDs on the live
  scoreboard in 12.0.x become secret values and drop out during serialization to
  SavedVariables, so the server-side "start vs final" diff found nobody (in
  production: 0 deserters from this source across 909 matches). Raid GUIDs are
  plain and survive serialization. The scoreboard is still read as an extra name
  source while its GUIDs are still plain.
- **The final scoreboard snapshot clears the faction filter** before reading
  (`SetBattlefieldScoreFaction(-1)` in Collector.lua). `RequestBattlefieldScoreData`
  alone doesn't clear it — without this ~1% of matches arrived single-faction.

## [0.9.12] — 2026-06-02

### Fixed
- **Premade alert text is now always English** (header + leader lines). The
  alert is broadcast into `/rw`, read by a mixed-language BG — English as the
  lingua franca, same logic as the server. Previously it was Russian on a
  Russian client.
- **The copy button can be dismissed with a right-click** (previously it didn't
  disappear if the alert fired outside normal combat — e.g. a manual `/piq
  premade` check: the BG enter/leave events didn't fire and the button lingered).
  In normal combat it still hides on leaving the BG. Tooltip updated: left-click
  copy, right-click hide, drag to move.

## [0.9.11] — 2026-06-02

### Added
- **A "Copy alert" button appears with the premade alert.** When the alert
  fires, a button pops up under the central banner — clicking it opens a box
  with the last enemy-premade line (Ctrl+C → paste into `/rw` or Discord).
  Previously you had to type `/piq copy`. The button lives in the **main addon**
  (which everyone downloads), not in the owner-only `PremadeIQ_Leader` toolbar —
  otherwise only the owner would get the feature. **It's a button, not an
  auto-popup:** the dialog focuses its input field, and auto-popping in combat
  would steal WASD; the click opens it at the right moment. The button is
  draggable, its position is saved (`PremadeIQ_DB.copyBtnPos`), and it hides on
  leaving combat.

## [0.9.10] — 2026-05-31

### Changed
- **Premades are detected by leader, with confidence grading.** Previously the
  alert shouted "Premade" at any catalog player — including a lone regular. New
  rule: **a premade without a leader is not a premade.** A known leader on the
  enemy side = "possible premade" (yellow); a leader + **>5 of their regulars**
  (`CONFIRM_MIN_MEMBERS = 6`) nearby = "PREMADE" (red). Lone members without a
  leader are no longer flagged.
- **Output to the point:** one line per leader — "Leader X — with N of their
  players", where N is how many of their known regulars are present. The
  banner/chat/copy and sound use the same text. Catalog matching was rewritten
  for multi-membership (a player can belong to several leaders — each gets the
  credit). The `alertLog` diagnostic line gained a `ldr` field (number of
  leaders on the enemy side).

## [0.9.9] — 2026-05-31

### Fixed
- **In-combat lag — scan throttling.** `UPDATE_BATTLEFIELD_SCORE` on an
  80-player Epic fires many times a second, and on each one we scanned the whole
  scoreboard AND called `SetBattlefieldScoreFaction(-1)`, which itself fires a
  synchronous score update reprocessed by the whole UI (a heavy rebuild of
  Blizzard's native 80-player scoreboard) and by addons — a per-frame storm.
  Added throttling: `autoScan` runs at most once per `SCAN_THROTTLE_SEC = 1.5`
  (`lastScanAt`/`GetTime`, reset in `OnMatchActive`/`Reset`). One scan per ~1.5s
  is plenty to catch a roster that loads over seconds; manual `/piq premade`
  ignores the throttle.

## [0.9.8] — 2026-05-31

### Changed
- **Scan window extended for the enemy team loading late.** The enemy roster
  isn't shown until the match starts and only appears a few seconds in, and on
  an 80-player Epic the scoreboard loads gradually (in `alertLog`, even our own
  half grew `16→35` over ~50s). The old 60s window / timers up to 45s could end
  before the enemy half appeared. Timers are now
  `{4,8,14,22,32,45,60,80,105,135,170}` with `SCAN_WINDOW_SEC = 180`. The
  announcement is one-shot (`fired`), so on a hit the scans stop immediately —
  the long window only costs anything when there's no premade. Names are
  `NeverSecret`, so reading deeper into the match is safe.

## [0.9.7] — 2026-05-31

### Fixed
- **Faction un-filtering didn't work — wrong argument.** In 0.9.4–0.9.6
  `detect()` called `SetBattlefieldScoreFaction()` with no argument (nil), but
  nil does NOT show both factions — `alertLog` proved it: `n` stuck at ≈35 (own
  team only), `enemy=0`, even though the server confirmed enemy premades in most
  matches. The "All" tab in Blizzard's native scoreboard passes `factionEnum =
  -1` (`PVPMatchResults.xml`; 1 = Alliance, 0 = Horde). We now call
  `SetBattlefieldScoreFaction(-1)` — and on every scan, since calling it on an
  early `n=0` tick didn't "stick". The 0.9.6 re-entrancy guard makes the repeated
  call safe; the `factionUnfiltered` flag was removed.

## [0.9.6] — 2026-05-31

### Fixed
- **C stack overflow in combat (crash from 0.9.4).** `SetBattlefieldScoreFaction()`,
  added to `detect()`, fires `UPDATE_BATTLEFIELD_SCORE` **synchronously**; our
  `OnBattlefieldScoreUpdate` handler → `autoScan` → `detect()` re-entered, and so
  on until the C stack overflowed (`RequestBattlefieldScoreData` was async, which
  is why it didn't recurse before). Added a re-entrancy guard: `detect()` is now
  a wrapper over `detectImpl` with a `scanning` flag (an inner re-entry is a
  no-op) and `pcall` (the flag is always reset). Plus
  `SetBattlefieldScoreFaction` is called at most once per match
  (`factionUnfiltered`, reset in `OnMatchActive`/`Reset`) — the filter is
  persistent anyway, no need to poke the event on every scan.

## [0.9.5] — 2026-05-31

### Added
- **Prominent premade alert + copy.** Besides the chat lines, the alert now
  shows a large center-screen banner via `RaidWarningFrame`
  (`RaidNotice_AddMessage`, like the native `/rw`) — so it isn't missed in Epic
  spam. The new **`/piq copy`** command opens a dialog with a ready-to-paste
  line ("Premade on the enemy team! — Leaders: … — Members: …"), text selected,
  press Ctrl+C and paste into `/rw` or raid chat yourself. Chat from insecure
  code is blocked in 12.0.x (`ADDON_ACTION_BLOCKED`), so copying is manual; the
  dialog doesn't auto-popup (it won't hijack WASD in combat) and is opened by the
  command instead. After every alert a `/piq copy` hint is added to chat.

## [0.9.4] — 2026-05-31

### Fixed
- **The alert saw only our own half of the scoreboard.** After the name fix
  (0.9.3), premades on OUR side were found but the enemy's weren't. Server
  ground truth: premades were on the enemy side in 13 of the last 15 matches,
  while `alertLog` gave `enemy=0`. Root cause:
  `GetScoreInfo`/`GetNumBattlefieldScores` return rows only for the faction last
  selected by `SetBattlefieldScoreFaction`; the default after
  `PVP_MATCH_ACTIVE` is the local faction, so the enemy half (exactly what we're
  looking for) is invisible. In the log this is `n≈38` on misses vs `n≈75` in
  the one match that fired. `detect()` now calls `SetBattlefieldScoreFaction()`
  (= both factions) before reading — the same call Blizzard's native scoreboard
  makes when switching team tabs (`PVPMatchScoreboard.lua`).

## [0.9.3] — 2026-05-30

### Fixed
- **Premade alert didn't fire at all — matching on a secret GUID.** The
  `alertLog` diagnostics found the root cause: in live Epics
  `C_PvP.GetScoreInfo(i).guid` arrives as a secret value already in the opening
  window (`str=0 sec=77 hit=0`), and `detect()` looked up only `lookup[guid]` →
  skipping every row. The `name`, `faction`, `className`, `raceName` fields of
  the `PVPScoreInfo` struct are marked `NeverSecret = true`
  (Blizzard_APIDocumentationGenerated/PvpInfoDocumentation.lua), i.e. they stay
  plain even in an active match. `detect()` now matches the enemy roster by
  normalized `Name-Realm` (guid only as an exact shortcut while it's plain), and
  determines the enemy side by `faction`. `ensureLookup` builds a second
  name→entry index; `normName` appends the viewer's realm to bare same-realm
  names. Dedup by the catalog entry's name. Taint-safe: secret values are never
  compared.

### Changed
- The `alertLog` line now carries an `nm` field (number of plain names on the
  scoreboard) alongside `str`/`sec` — to confirm name readability within one
  match.

## [0.9.2] — 2026-05-27

### Added
- **Premade-alert diagnostics in SavedVariables.** `PremadeAlert` writes a ring
  log to `PremadeIQ_DB.alertLog` (100 lines): on `PVP_MATCH_ACTIVE` — catalog
  state (`catalog_leaders`, `lookup`, `tier`); on each scan — `bg / cat / n /
  str / sec / hit / enemy / mine` (in a BG, catalog size, scoreboard rows,
  readable guids vs secret, catalog hits, enemies, own faction); and `ANNOUNCE`
  when it fires. Lines are deduplicated. With `/piq debug on` they're mirrored to
  chat in grey. The goal: diagnose "the alert doesn't fire" from an on-disk dump,
  without relying on reading chat live.

## [0.9.1] — 2026-05-26

### Fixed
- **The premade alert didn't fire in Epics.** Three fixed scans (4/8/14s) often
  all landed while the enemy half of the scoreboard on an 80-player Epic hadn't
  loaded yet (or enemy guids read as secret and `detect()` skipped them) → a miss
  every time. `PremadeAlert` now catches the `UPDATE_BATTLEFIELD_SCORE` event and
  re-scans on every update within a 60s window (the accumulating strategy that
  makes `Deserter` reliable), plus the timers were extended to
  `{4,8,14,22,32,45}`. One announcement per match is preserved.

### Added
- `/piq` now prints a catalog status line (loaded / not loaded, how many
  leaders, tier) — you can check the alert feed any time without waiting for the
  login line. New localized string `PremadeCatalogMissing`.

## [0.9.0] — 2026-05-25

### Added
- **In-game premade alert.** On entering a battleground the addon compares the
  enemy roster against known premades and warns the player via chat + sound.
  - New module `PremadeAlert.lua`: on `PVP_MATCH_ACTIVE` it starts a multi-shot
    roster capture (4/8/14s — the early window where names/guids still read
    plain, like `Deserter`; on a deep match they're secret, but we don't go
    there). It checks the **enemy** side (faction ≠ ours → also catches
    mercenaries) against the catalog. Every read is guarded by `issecretvalue`.
  - Data comes from a new catalog the Uploader downloads from the server
    (`GET /api/addon/known-premades`) and writes to `KnownPremades.lua`; the
    addon loads it on login/`/reload`.
  - **Server-side tiering.** A contributor gets the list of leaders; a patron
    gets leaders + rosters. The shape of the data in `KnownPremades.lua` dictates
    what to show (has `members` → roster, otherwise leader only); there's no tier
    logic in the addon. You can't fake an upgrade by editing the file — the
    server doesn't put what your tier hasn't earned into the file.
  - `/piq premade` — manually check the current match.
  - Options: "warn about premades" and "sound" toggles (on by default).
- **`KnownPremades.lua`** — a shipped stub, overwritten by the Uploader. A
  toc-data file (not a SavedVariable): WoW loads it at startup and never writes
  to it, so the Uploader's update is never clobbered by the client.

### Related (server / uploader)
- Server: `GET /api/addon/known-premades` (tier-gated, `catalog.py` with a 30-min
  TTL cache). Builds leaders from `enemy_leaders` + co-players (≥3 shared clean
  matches on the home side) for patrons. `+1` test (`test_addon_catalog`).
- Uploader: `ApiClient.fetch_catalog()` + `catalog_writer.py` +
  `resolve_addon_dir`, writes the file into the addon folder once an hour after
  upload. `+6` tests (`test_catalog_writer`).

### Pending
- Live test in EBG (confirm guids read in the early window for real).
- Server deploy + Uploader rebuild (Nuitka `--standalone`).

## [0.8.2] — 2026-05-23

### Disabled
- **Mid-match snapshots disabled** (`MID_SNAPSHOT_INTERVAL = 0`). An empirical
  check on a real match (retail 12.0.x): not only the numeric fields
  (`damageDone`, etc.) are protected as secret values, but also **`info.guid`** —
  and the Lua serializer silently drops secret strings from SavedVariables. The
  result: snapshots arrived at the server with no guid and zeroed metrics,
  useless for off-board metric recovery. Worse — without a guid the server
  rejected the whole upload as a 422 validation error, and a backlog of matches
  got stuck.

  The snapshot code is left in place: once we find an alternative source (combat
  log parser or a secure-context hook), we just restore a non-zero interval.

## [0.8.1] — 2026-05-23

### Fixed
- **Secret-value taint in the mid-snapshot.** Retail 12.0.x protects live
  scoreboard numbers (`pvpStatValue`, `damageDone`, `healingDone`, …) during an
  active match — arithmetic on them crashed `TakeMidSnapshot()` with "attempt to
  perform arithmetic on a secret number value". The final snapshot from
  `PVP_MATCH_COMPLETE` survived this because Blizzard drops the protection on the
  completion event; the mid-snapshot runs mid-match and hit the guard. Every
  numeric read is now wrapped in a `safeNum()` helper that returns 0 for
  protected values (via `issecretvalue`) instead of crashing. Some snapshot
  fields will be zero (the protected ones), but the snapshot is saved and at
  least guid+faction signals the player's presence on that tick.

## [0.8.0] — 2026-05-23

### Added
- **Mid-match snapshots every 300s.** A new `Collector:TakeMidSnapshot()` via
  `C_Timer.NewTicker` periodically snapshots the scoreboard during the match.
  Saved as `snapshots = {{takenAt, players = [...]}, ...}` inside a matchLog
  entry. This lets us recover the metrics of players who left before the end and
  were substituted — they're no longer in Blizzard's final scoreboard (always 40
  per side).
- **Schema v3.** A `snapshots` field added to matchLog entries. Old v2 entries
  without snapshots are fine — the server treats absence as "no timeline
  available for this match".

### Why
In long Epic BGs (30–90 min stall-wars) player rotation is common. Before this
release we only saw the 40 who finished the match; those who left earlier had
only a name in the `deserters` table, with no dmg/heal/etc. Now we have data
points every 5 minutes, and an off-board deserter usually lands in at least one
snapshot.

## [0.7.3] — 2026-05-04

### Added
- **Capture our raid leader's GUID at scoreboard snapshot.** New
  `findRaidLeaderGUID()` in `Collector.lua` iterates `GetRaidRosterInfo` for
  rank=2 (raid) or `UnitIsGroupLeader` (party) and stashes the GUID on the match
  payload as `leaderGUID`. The server stores it on `Match.leader_guid` and
  recomputes per-player `leader_count` like `desertion_count` is recomputed.

## [0.7.2] — 2026-05-04

### Removed
- **Removed dead legacy scaffolding.** Cleaned out unused inter-addon
  communication libraries and a leftover debug slash command that no longer did
  anything, trimming the `Libs.xml` and `.toc` load list accordingly.
  `LibSerialize` and `LibDeflate` are kept — they may be useful later, and sit as
  one `LibStub` module load each with no active work.

## [0.7.0] — 2026-05-01

### Added
- **Deserter detection via start vs end comparison.** New module `Deserter.lua`
  (~80 lines) does a single replay-of-the-data trick: at `+6s` after
  `PVP_MATCH_ACTIVE` it snapshots the scoreboard — who came in to fight; the
  final scoreboard on `PVP_MATCH_COMPLETE` is already taken by `Collector`. On
  ingest the server diffs the sets and, for each "present at start / absent at
  end", checks faction vs `match.winner` — if the faction lost, it flags the
  player as a deserter.
- Late-join guard: if `C_PvP.GetActiveMatchDuration()` > 60s at
  `PVP_MATCH_ACTIVE`, we set `lateJoin=true` and the server skips the diff for
  that match (so we don't false-positive everyone who left before we joined).
- The match payload gains a `startRoster: { lateJoin, takenAt, players: [{guid,
  name, faction}] }` field. The server computes deserters; in the DB they go to a
  `deserters` table with a natural key `(reporter_id, ended_at, guid)` for
  dedup across reports.

### Changed
- Version: 0.6.2 → 0.7.0.
- No new events registered in `Main.lua` — we make do with the same
  `PVP_MATCH_ACTIVE` / `PVP_MATCH_COMPLETE` / `PLAYER_ENTERING_WORLD` /
  `UPDATE_BATTLEFIELD_SCORE`. No chat parsing, no locales, no debuff watching.

### Design notes
- The "the faction lost" heuristic is deliberately asymmetric: leaving a won
  match isn't flagged. This surgically cuts out disconnects (technically
  indistinguishable from desertion to us), while still catching serial AFKers by
  the law of large numbers: they leave losing matches more often than winning
  ones, and every encountered addon user independently contributes a record to
  the shared database.
- Self-desertion (when the reporter themselves left) is **not detected directly**
  — for us that match simply doesn't exist. But other reporters in the same
  match will see and record it. A pattern over time from multiple reporters
  covers the gap without an aura watch.

## [0.6.2] — 2026-04-29

### Fixed
- On AV/IoC the match-end scoreboard contained only our own team (40 rows
  instead of 80), so the opposite faction's data didn't reach the server. Cause:
  WoW fills the client scoreboard cache lazily — only for the tabs the player
  actually opened during the match, and on these maps the fast post-cap teleport
  leaves no chance for a manual view. Added `Collector:ScheduleSnapshotMatch`:
  two `RequestBattlefieldScoreData()` calls 0.7s apart guarantee both sides are
  cached before iterating. Total delay before the snapshot is 1.4s (was 1.0).
  The same logic applies to the manual `/piq snapshot` command.

## [0.6.1] — 2026-04-27

### Fixed
- `/piq options` crashed with `bad argument #1 to 'OpenSettingsPanel' (outside
  of expected range)`. The code set `category.ID = "PremadeIQ"`, overwriting the
  auto-generated numeric ID with a string; `OpenSettingsPanel` accepts only an
  integer. Removed the manual assignment, keep the category object and pass
  `category:GetID()`.

## [0.6.0] — 2026-04-27

### Added
- GUI settings panel: Esc → Options → AddOns → PremadeIQ. debug
  checkbox, local-database stats, a "Wipe database" button with confirmation,
  Uploader/Discord links, addon version. Registered via
  `Settings.RegisterCanvasLayoutCategory` (retail 11.0+).
- Slash command `/piq options` (aliases `/piq config`, `/piq settings`) — open
  the panel programmatically.
- Panel localization: ru / en (other locales fall back to en).

## [0.5.1] — 2026-04-27

### Fixed
- Players from your own realm reached the server without a realm suffix (the WoW
  API returns a short name for same-realm players). Because of that ~7 players in
  our database were stuck at `enrichment_status='error'`. The collector now
  always appends the local realm via `GetRealmName()` if it's missing from
  `info.name`.

## [0.5.0] — 2026-04-27

### Added
- The player's race (`info.raceName`) is now shipped in every sample. The server
  uses it to detect mercenaries: a match card will show "played for Alliance,
  actually Horde" and vice versa.

## [0.4.0] — 2026-04-23

### Added
- A welcome dialog on first launch with instructions for joining the shared
  database (Uploader + Discord + Patreon).
- Unified slash commands: `/piq status | uploader | snapshot |
  debug on|off | reset confirm | version`.
- SavedVariables schema `version 2` + automatic migration from v1.
- A `PremadeIQ_DB.settings` table for user settings (debug flag, hints).
- Helper methods `Database:GetSetting/SetSetting`, `Database:CountSamples`.
- Full ruRU / enUS locales with fallback to enUS.

### Changed
- toc version → `0.4.0`, added `IconTexture`, `X-Website`, an
  `X-Curse-Project-ID` placeholder.
- `/piq reset` now requires `confirm` to guard against a typo.
- The debug dump is hidden behind the `/piq debug on` flag — no longer spamming
  chat for normal players.
- Consolidated the debug output behind that single flag.

### Fixed
- Settings access is now guarded against nil access before init.

## [0.3.0] — 2026-04-21

- Collect the PvP scoreboard on `PVP_MATCH_COMPLETE`.
- Support reading objective ownership from the Leader module.
- Ring buffer: 30 samples for other players, 500 for your own character.
- Deserter tracker: chat parsing + UPDATE_BATTLEFIELD_SCORE fallback.
- i18n for the objective tracker's chat text (ruRU/enUS).

## [0.2.0] — 2026-04-15

- Instance mapID resolver via `select(8, GetInstanceInfo())`.
- `C_PvP.GetActiveMatchWinner` instead of `GetBattlefieldWinner`.
- Fixed a bug with `won = nil` for lost matches.

## [0.1.0] — 2026-04-10

- First internal version: basic Collector, Database, Comm.
