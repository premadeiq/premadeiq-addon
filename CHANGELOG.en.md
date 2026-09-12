# Changelog

All notable changes are documented here. Format — [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning — [SemVer](https://semver.org/).

## [0.9.50] — 2026-09-12

### Fixed
- **The welcome screen no longer offers a paid tier — there isn't one.** The
  first-run text said the King of EBG tier on Patreon adds deeper dashboard
  tools. Since 12 September that is not true: there is no paid access any more,
  and the rest of the site — player search, match breakdowns, enemy leaders —
  is opened by five matches a week. The text is corrected in all six languages;
  nothing else in the addon changed.

## [0.9.49] — 2026-09-09

### Fixed
- **The odds are now an epic-battleground feature only.** The line used to
  appear in any battleground, 15-a-side ones included — but the winrates behind
  it were collected in epics, and so was the accuracy printed next to it. In a
  regular battleground the number looked just as confident with nothing behind
  it.
- **A locked forecast is no longer spoiled at the moment it locks.** When the
  scoreboard started emptying, the number was first recomputed without the
  players who had left and only then frozen — so the spoiled one was what got
  kept. It now freezes what was computed on the full roster. "How full is the
  board" is also measured by the smaller of the two teams: our half filling
  while theirs emptied left the total unchanged, and the forecast settled early.
- **The "Show win chances" switch now silences all three places.** It removed
  the line from the players panel while the standalone pop-up and the premade
  banner kept announcing odds. An explicit `/piq odds` still answers — that is a
  question asked out loud.
- **The addon refuses to compute from an unusable winrate cache.** A file of an
  unknown version, older than 45 days, or with no coefficients now reads as "no
  data". A zero model used to produce not silence but a flat "50% — 50%"
  captioned "0% accurate" — zero times anything is a coin flip.

## [0.9.48] — 2026-09-07

### Changed
- **The odds no longer drift during the battle.** They used to be recomputed on
  every scoreboard scan, and a scoreboard changes as people leave — so the
  number crept toward an outcome that was already visible, looking wiser than it
  was. It is now computed while the scoreboard fills and locked once it stops
  growing, on the starting roster the accuracy was measured against.
- **The line says what it is doing:** "reading the scoreboard", then
  "calculating", and a locked result is marked "final".
- **The forecast strings are translated** into every language the addon ships.
  Only the premade warning and the copy-for-chat text stay English — those are
  read by a mixed-language battleground.

### Added
- A "show win chances" switch in the settings (`/piq options`), on by default.
  Not for performance: the whole winrate cache is about 1 MB of memory and a
  single forecast takes hundredths of a millisecond, over rows the panel has
  already read.

## [0.9.47] — 2026-09-06

### Changed
- **The players panel now stays up for the whole battle.** It used to vanish
  when the scoreboard held no premades and nobody you had marked — taking the
  odds line with it, though that line has something to say in every match.
  While the scoreboard is still loading it says so. Outside a battleground the
  panel is hidden as before.
- The odds now keep updating during combat: the line used to freeze, because
  the panel's whole update path stops in combat for its protected buttons.

### Fixed
- The separators in the odds line no longer render as empty boxes — the UI font
  does not draw the character that was there.

## [0.9.46] — 2026-09-06

### Fixed
- **Reloading mid-battle no longer loses the match.** A `/reload` wipes the
  match context, and restoring it never worked: the battle fingerprint was
  stamped when we landed in the instance — one to two minutes before the gates
  open — and then disagreed with the real battle start by exactly the length of
  that prep phase. On Epics that meant the restore failed every single time,
  taking the match start time, the premade warning and the odds line with it.
- **The "usually takes raid lead" notice is no longer suppressed by an empty
  catalog.** Those players live in their own list, but the "catalog is empty"
  check only looked at premade leaders and bailed out before reaching them. With
  raid leads marked and no premades, the notice never appeared at all.
- The copy dialog's title no longer freezes on whichever language was active
  when the game started.

## [0.9.45] — 2026-09-06

### Added
- **Win chances for the match.** The addon reads both teams off the scoreboard,
  looks them up in the winrate table the Uploader ships, and shows which side is
  favoured — before the battle decides it. The line lives in the tracked-players
  panel and updates as the scoreboard fills; hover it to see what the number is
  made of (each side's average winrate and the share of players the database has
  never seen), click it to copy that for chat. `/piq odds` answers on demand and
  says plainly when there is not enough data.
- It is all computed **inside the game**, with no server round trip: WoW only
  hands data out on an interface reload, so asking mid-match is impossible.

### Notes
- The forecast is right about **72%** of the time — a hint, not a verdict: it is
  wrong roughly every third or fourth match, which is stated under the number
  itself. That figure is measured on starting rosters, the same partial
  scoreboard the addon actually reads.
- Requires **Uploader 0.9.2 or newer** — it is what delivers the winrate table.
  Per-player winrates are never shown in game; only the team summary.

## [0.9.44] — 2026-09-04

### Added
- **The addon now warns when your premade list has gone stale.** The list comes
  from the Uploader, and if that has not run for a while the addon keeps working
  quietly — on data from two weeks ago. The worst part is how it looks: silence
  on entering a battleground reads as "no premade here", when it actually means
  "we do not know". Entering an Epic BG with a list older than two weeks now
  says so plainly: how many days old it is and what to do about it. At most once
  a week, switched off in the same place as premade warnings.
- **`/piq status` shows the age of the list.** The passive hint only fires
  inside a battleground and only after two weeks of silence, so there was no way
  to check on purpose. This line answers immediately — including when everything
  is fresh.
- **A third confidence level in the targets panel: "possible premade member".**
  Until now a player was either a premade member or nobody, with nothing in
  between — so a single game could drop someone off the panel and the next one
  put them back, though they had changed nothing. A player we have shared
  history for, just not enough of it to say so with confidence, now shows with a
  `?` mark and the caption "Possible premade member", and the tooltip names
  whose premade they were seen beside. The mark is deliberately unlike `*`
  (leader) and `~` (takes raid lead, runs no premade): it is a question, not a
  statement. Such players ride in their own list and never join the confirmed
  roster — not in the panel, not in announcements.

## [0.9.43] — 2026-08-26

### Added
- **The addon now notices when your battles stop leaving your machine.** The
  Uploader is a separate program and it fails quietly: the addon keeps
  recording, nothing goes out, and you find out when your access to the premade
  catalog lapses. The previous hint could not help here — it only spoke to
  players whose catalog was empty, which is precisely the wrong audience. On
  entering an Epic BG the addon now counts the battles logged since the last
  upload, and if the Uploader has not run for three days or more, it says so.
  At most once every three days, and it switches off with the premade warnings.
- **And it says what that costs you.** Catalog access needs one upload every
  seven days. Under a week of silence, the addon tells you roughly how long is
  left; over it, that access has most likely lapsed and how to reopen it. Until
  now you found out afterwards and without an explanation.
- **`/piq` reports the upload state** — how many battles are waiting and when
  the Uploader last ran. The passive hint only appears after days of silence
  and only inside a battleground, so there was no way to check it on purpose.
  This line answers immediately, including when everything is fine.

### Changed
- **The install address is shorter.** WoW has no
  clickable links and chat text cannot even be selected, so the address gets
  retyped by hand. A shorter one is less to type, and it leads to the same page.

## [0.9.42] — 2026-08-16

### Fixed
- **The Uploader link led nowhere — and had since the first public release.**
  `/piq uploader` printed the address of a repository that does not exist, so
  everyone who wanted to share their matches hit a 404. It now points at the
  install page: https://premadeiq.duckdns.org/install — and opens a small box
  with the address already selected, because chat text cannot be selected in
  this client and retyping a URL by hand is nobody's idea of a good time.

### Added
- **The addon no longer stays quiet about an empty premade list.** It ships
  with that list empty and cannot fetch anything on its own — the list is
  community-contributed data and arrives with the Uploader. Until now that
  looked exactly like a feature that doesn't work. On entering an Epic
  battleground the addon now says once (at most weekly) what is missing and
  what fixes it. If the Uploader has run before and access simply lapsed, the
  wording is different — "upload one match", not "install the app". Those are
  two different situations and conflating them would be dishonest.
- **A `/reload` reminder after a recorded match.** "Match recorded" means
  "kept in memory", not "sent": the game only writes SavedVariables to disk on
  `/reload` or logout. Until then the Uploader genuinely sees nothing and looks
  broken. Shown only to accounts that have never uploaded.

### Changed
- **The welcome dialog was rewritten.** Step three used to be "link Discord to
  your Patreon", which made the whole thing read as "paid from here on". It
  isn't: one finished Epic BG a week opens premade warnings, the full
  leaderboard and deserters, for free. Joining a Discord server is no longer
  required either — any Discord account works. Patreon is still there, in the
  place it belongs: one optional line.
- `/piq status` on an empty catalog now shows where to get one.

## [0.9.41] — 2026-08-15

### Fixed
- **The minimap button has its own emblem now.** Yesterday's button drew a green
  question mark — the texture the game substitutes for anything it cannot find.
  The icon path pointed at a Blizzard icon that does not exist, and the client
  says nothing about that: no error, no warning, just the question mark. The
  button now carries the PremadeIQ logo, and so does the addon list and the
  game's own addon compartment.

## [0.9.40] — 2026-08-14

### Added
- **Your own watchlist.** The addon options now have an input box: copy a
  character name in game, paste it, and that player is marked in the targets
  panel whenever they turn up in your battleground. The list is **yours**: it is
  stored in a separate file on your computer only, is never uploaded, and nobody
  else can see it. It has no effect on premade detection either — it is your
  note, not our data. Such a row is captioned "on your watchlist" rather than
  "known premade member", because the addon does not claim what it does not
  know. Names are matched exactly, so after a rename the entry stops matching
  and has to be added again.
- **Solo raid leaders now show up in the panel.** Players who take raid lead but
  run no premade were only ever mentioned in the warning line; the targets panel
  did not list them at all. Now it does, marked `~` and captioned "takes raid
  lead, no premade". They are a separate category, not a premade: such a player
  never gets the leader star. And when someone both takes raid lead and belongs
  to somebody's premade — roughly half of them do — the panel states both facts
  instead of picking one.
- **A minimap button.** Opens the addon settings, drags around the minimap edge,
  and can be switched off in those same settings. PremadeIQ also shows up in the
  game's own addon menu on the minimap, for people who dislike extra buttons.
- **An addon language setting.** The options now have a "Language" row: it
  follows your game client by default, but you can force any of the six. The
  first reason it exists is verification — on a Russian client there was no way
  to see what English-speaking players read, and they are 45% of the players in
  our data. Battleground alerts stay English whatever you pick: they are read by
  a battleground that does not share a language.
- **German, French and Spanish are finally complete.** The addon declared five
  languages while three of them were 22% translated: the whole settings window,
  the tooltips and the links showed in English. German players are 22% of our
  data, the second largest group after English.
- **Italian added** as a sixth language, translated in full.

### Fixed
- **The settings window no longer drifts apart.** The "Columns" row and the
  stats and links blocks crept rightwards into the next column, and the links ran
  off the edge of the window. The cause was in the layout: each row anchored
  itself to a button inside the row above rather than to the start of the column,
  so the offset accumulated.
- **The panel could go silent until you reloaded the interface.** An error while
  reading the premade list left an internal "scan in progress" flag raised, and
  every later refresh was skipped without a word. Such an error is now handled
  and the panel recovers on the next update by itself.
- **The panel heading is honest again** — "Tracked players" instead of "Known
  premade targets": it has been listing more than premade members for a while.

## [0.9.39] — 2026-08-14

### Fixed
- **Players whose identifier could not be read are no longer mistaken for
  leavers.** A final-scoreboard row with an unreadable identifier was skipped
  silently, and on the server it looked exactly like the row of somebody who had
  left the battleground. The addon now marks the player by NAME (a name is
  something the game never hides) before the row can be dropped, and separately
  reports how many rows it had to drop.

### Added
- **The site now shows who did not make it to the end of a match.** The data was
  already there, but only the opposite half of it was used — the "joined late"
  badge. The match page's "Left the battlefield" section is no longer empty: an
  Epic battleground turns over half its roster, and both sides of that trade are
  visible now.

## [0.9.38] — 2026-08-12

### Fixed
- **The addon no longer breaks the game's own combat announcements.** The
  premade headline was posted to the same centre-screen frame the game uses for
  its own warnings ("The gate has been destroyed" and the like). In 12.1 that
  became unsafe: after our message the frame stayed flagged as addon-touched and
  then errored — not only on our text, but on the game's own announcements too.
  The failure could not be caught, because it happened after the addon had
  already finished. That frame is no longer used at all. Nothing is lost: the
  PremadeIQ banner shows the same headline in the same colours (red = premade
  confirmed, amber = possible) and additionally lists the leaders, which the
  single-line frame could never do.

## [0.9.37] — 2026-08-12

### Changed
- **Support for patch 12.1 "Curse of Ula'tek".** The addon is no longer flagged
  as out of date.

### Fixed
- **Enemy "crowns" no longer report zero where the truth is "cannot see".** In
  12.1 the game stopped telling addons which enemies lead a group, so the old
  counter honestly returned zero simply because it is no longer allowed to look.
  On the site that would have read as "the enemy team brought no pre-formed
  groups" — a claim the addon never made. It now counts separately the enemies
  the game refused to answer for, and in that case the server publishes no
  estimate at all instead of publishing a zero. Crowns actually seen (if the
  game does answer) still count as a lower bound, and your own side is
  unaffected: the game places no such limits there, so enemy group leaders keep
  being recovered from reports by players of the opposite faction.

## [0.9.36] — 2026-08-08

### Fixed
- **A player tagged as "usually takes raid lead" no longer disappears from the
  warning when a premade is in the match too.** Their line was printed only when
  there were no premades at all — that is, exactly in the matches where it
  matters least. It now comes last in the regular warning and is repeated in the
  banner, and the premade verdict itself is unchanged.

### Changed
- **The standalone notice about such a player is easier to catch:** with no
  premade in the match it now shows on the centre of the screen and in the
  banner, not only in chat. Still no sound — it is context, not an alarm.

## [0.9.35] — 2026-08-08

### Fixed
- **A `/reload` mid-match no longer costs you the match.** The addon only
  recorded when you joined a battle at the moment it started, and reloading the
  interface wiped that with no way to get it back. The server then concluded you
  had been in two matches at once and quarantined the match — it simply vanished
  from the site. Your join time now survives a `/reload`: it is stored together
  with a fingerprint of the battle itself and restored only when that
  fingerprint matches, so two back-to-back matches on the same map cannot be
  confused for one another.
- **The "who was here from the start" roster is no longer replaced by the final
  scoreboard.** After an interface reload the addon could capture the starting
  roster from the end-of-match board. Such a list contains everyone who made it
  to the end, so players who joined as replacements stopped counting as late
  arrivals — which is exactly what protects them from being marked as having
  left the match. The starting roster is now never captured after the match is
  over.

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
