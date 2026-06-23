# PremadeIQ

An addon that collects **Epic Battleground** statistics in World of Warcraft
(Midnight 12.0.x) and lets you contribute to a shared community table.

## What it does

- Records the post-match scoreboard of every Epic BG (kills, damage, healing,
  objective points) into `SavedVariables`.
- Tracks the base/objective ownership timeline (Alterac Valley, Isle of
  Conquest, Ashran, Wintergrasp).
- Optionally shows a short notice when you enter a battleground if known
  organized groups (premades) are present on the enemy team — based on
  community-contributed data. Informational only.

The addon **never sends anything out by itself** — it only writes statistics to
your local `SavedVariables`. To share them with the community and see the table
on the website, you install a separate app — **PremadeIQ Uploader** (optional).

## Installation

### CurseForge / Wago (recommended)
1. Install an addon manager (CurseForge App, WowUp, …).
2. Search for **PremadeIQ** and click Install.

### Manual install
1. Download the zip from [GitHub Releases](https://github.com/premadeiq/premadeiq-addon/releases).
2. Extract it into `World of Warcraft\_retail_\Interface\AddOns\`.
3. You should end up with an `AddOns\PremadeIQ\` folder.

## Sharing data with the community

1. Install **PremadeIQ Uploader** — a separate app that reads your
   `SavedVariables` and sends the statistics to the PremadeIQ server.
   [Download](https://github.com/premadeiq/premadeiq-uploader/releases/latest)
2. Join the [Discord](https://discord.gg/KGPKRWt4MG).
3. (optional) The **King of EBG** Patreon tier grants a Discord role and
   extended access to the stats.
4. Run the Uploader → it starts syncing.

Don't want to share? Just don't install the Uploader — the addon stays purely
local.

## Commands

| Command | Action |
|---------|--------|
| `/piq status` | players, samples and matches in your local database |
| `/piq uploader` | link to download the Uploader and the Discord |
| `/piq snapshot` | manual snapshot (in a BG only) |
| `/piq premade` | check the current enemy team against community data |
| `/piq copy` | copy the last notice for chat |
| `/piq debug on\|off` | debug mode |
| `/piq reset confirm` | wipe the local database |
| `/piq version` | addon version |

## Privacy

- Statistics are stored locally in
  `WTF/Account/<ACCOUNT>/SavedVariables/PremadeIQ.lua`.
- The addon **sends nothing out by itself**. Data only reaches the PremadeIQ
  server if you separately install the **Uploader**.
- To delete your data from the server: ask in Discord `#support` (or `POST
  /api/me/delete`).

## Version

The version lives in `PremadeIQ.toc` (`## Version:`) — the single source of
truth. Changelog: [CHANGELOG.en.md](CHANGELOG.en.md)

## Support

- Discord: the [EPIC](https://discord.gg/KGPKRWt4MG) server
- GitHub Issues: https://github.com/premadeiq/premadeiq-addon/issues
