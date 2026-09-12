local ADDON, ns = ...

-- Locale is resolved at the bottom of this file, not here: the saved language
-- preference lives in SavedVariables, which are not populated until every Lua
-- file has finished executing.
local L = setmetatable({}, { __index = function(t, k) return k end })
ns.L = L

-- English defaults (fallback for any locale)
local en = {
    ["Match recorded"]         = "Match recorded",
    ["Players in DB"]          = "Players in DB",
    ["Samples"]                = "samples",
    ["Matches"]                = "matches",
    ["No data yet"]            = "No data yet",
    ["Not in a BG"]            = "Not in a BG",
    ["DB reset"]               = "DB reset.",
    ["Debug on"]               = "debug mode ON",
    ["Debug off"]              = "debug mode OFF",
    ["Confirm reset"]          = "Really wipe the PremadeIQ database? Type /piq reset confirm to proceed.",

    -- Premade alert
    ["PremadeDetected"]        = "PREMADE on the enemy team!",
    ["PremadePossible"]        = "Possible premade on the enemy team",
    ["PremadeNoLeader"]        = "PREMADE on the enemy team (leader not here)!",
    ["PremadeLeaderLine"]      = "Leader %s — with %d of their players",
    ["PremadeNoLeaderLine"]    = "%s's premade — %d regulars, leader not in BG",
    ["PremadeMore"]            = "…and %d more",
    ["PremadeGroups"]          = "Enemy group leaders spotted: %d",
    -- Marked as "takes raid lead, runs no premade": a separate, neutral
    -- notice. Never phrased as an accusation — the metric it comes from
    -- catches deliberate raid leaders too, the owner included.
    ["RaidLeadDetected"]       = "Usually takes raid lead: %s",
    -- Odds line. Two strings, never one: the percentage alone reads as a
    -- verdict, and it is a 72%-accurate guess. English like the rest of the
    -- banner (FORCE_EN) because the same text is what people paste into chat.
    ["ForecastOdds"]           = "Chances: us %d%% — enemy %d%%",
    ["ForecastNote"]           = "PremadeIQ forecast — right about %d%% of the time",
    ["ForecastCopy"]           = "Chances %d/%d (PremadeIQ forecast, ~%d%% right)",
    -- /piq odds: says why there is no number, so "nothing appeared" can be
    -- told apart from "the scoreboard has not finished loading".
    ["ForecastNoData"]         = "not enough known players yet: %d of %d on our side, %d of %d on theirs (need %d each)",
    ["ForecastNotInBG"]        = "odds are only available inside a battleground",
    ["ForecastNotEBG"]         = "odds are only available in epic battlegrounds",
    ["ForecastNoCache"]        = "no winrate data installed yet — the Uploader ships it",
    -- Compact form for the targets panel, which is narrow and lives on
    -- screen for the whole match.
    -- ASCII-safe separators only. U+00B7 MIDDLE DOT came out as empty boxes
    -- in game (the same trap PremadeTargets documents for its own marks);
    -- the em dash below does render, which is why it stays.
    ["ForecastPanelWorking"]   = "Odds %d%% — %d%%   (WR %d vs %d, new %d%% vs %d%%)   calculating...",
    ["ForecastPanelDone"]      = "Odds %d%% — %d%%   (WR %d vs %d, new %d%% vs %d%%)   final",
    -- The panel stays up for the whole battleground, so it has to say
    -- something while the scoreboard is still filling.
    ["ForecastPending"]        = "Odds: reading the scoreboard...",
    -- Tooltip on that line: the forecast shows its working, because a bare
    -- percentage cannot be argued with and therefore cannot be judged.
    ["ForecastTipTitle"]       = "Win chances for this match",
    ["ForecastTipSides"]       = "Us %d%%  —  Enemy %d%%",
    ["ForecastTipWr"]          = "Average winrate: %d%% vs %d%%",
    ["ForecastTipNew"]         = "Never seen before: %d%% vs %d%%",
    ["ForecastTipKnown"]       = "Found in the database: %d of %d vs %d of %d",
    ["ForecastTipAcc"]         = "Right about %d%% of the time — a forecast, not a verdict.",
    ["ForecastTipLocked"]      = "Locked on the starting roster — the line-up this forecast was measured against.",
    ["ForecastTipWorking"]     = "Still moving: the scoreboard is filling up.",
    ["ForecastTipCopy"]        = "Click to copy for chat",
    ["ForecastCopyFull"]       = "[PremadeIQ] Odds %d/%d — avg WR %d vs %d, never-seen %d%% vs %d%% (forecast, ~%d%% right)",
    ["PremadeLeaders"]         = "Premade leaders",
    ["PremadeMembers"]         = "Premade members",
    ["PremadeNone"]            = "No known premade leader in this match",
    ["PremadeCatalogLoaded"]   = "premade catalog: %d leaders (tier: %s)",
    ["PremadeCatalogAge"]      = "list refreshed %d days ago",
    ["PremadeCatalogMissing"]  = "premade catalog is empty — the warnings have nothing to match against yet. It ships with the Uploader: %s",
    -- Printed on entering an Epic BG, at most once a week. Two branches:
    -- the Uploader was never here, or it was and the access has lapsed.
    ["CatalogHintNoUploader"]  = "Premade warnings are silent: the known-premade list comes with the Uploader — %s",
    ["CatalogHintStale"]       = "Premade warnings are silent: your access lapsed. Upload one finished Epic BG to reopen it.",
    ["CatalogOutdated"]        = "The premade list you are playing against is %d days old — new premades and new members are missing from it.",
    ["CatalogOutdatedFix"]     = "Start PremadeIQ Uploader: it refreshes the list. Silence on entering a BG currently means \"nothing known\", not \"nobody there\".",
    -- The Uploader stopped running: battles pile up locally and the player
    -- has no way to notice. %d = battles waiting, %d = days since it last ran.
    ["UploadSilent"]           = "%d battles have not been sent — the Uploader has not run in %d days.",
    ["UploadSilentSoon"]       = "Catalog access needs one upload every %d days — about %d left.",
    ["UploadSilentLapsed"]     = "Catalog access has likely lapsed: it needs one upload every %d days. Start the Uploader to reopen it.",
    -- Shown by /piq on demand, including the healthy case. %d = battles
    -- waiting, %d = days since the Uploader last wrote its watermark.
    ["UploadPending"]          = "Waiting to be sent: %d battles (the Uploader last wrote %d days ago).",
    ["UploadUpToDate"]         = "Every recorded battle has been sent.",
    -- Printed after a recorded match, while no upload has ever been seen.
    ["MatchNeedsReload"]       = "Type /reload (or log out) so WoW writes this match to disk — until then the Uploader can't see it.",
    ["PremadeCopyTip"]         = "Click «Copy premade alert» (or /piq copy) to copy this for chat",
    ["PremadeCopyHint"]        = "Ctrl+C to copy, then paste into chat (e.g. /rw):",
    ["PremadeCopyNone"]        = "No recent premade alert to copy.",
    ["PremadeCopyBtn"]         = "Copy premade alert",
    ["PremadeCopyBtnTip"]      = "Left-click: copy the enemy-premade line (box opens, Ctrl+C, paste into /rw or Discord). Right-click: hide. Drag to move.",
    ["PremadeTargetsHeader"]    = "Tracked players",
    ["PremadeTargetLeader"]    = "Known premade leader",
    ["PremadeTargetMember"]    = "Known premade member",
    -- One tier below a member: the server has shared history for them but not
    -- enough of it to say "member". Worded as an observation, never a verdict.
    ["PremadeTargetLikely"]    = "Possible premade member",
    ["PremadeTargetLikelyWith"] = "Possibly with",
    -- Marked "takes raid lead, runs no premade". A plain fact, never an
    -- accusation — and never mutually exclusive with premade membership.
    ["PremadeTargetRaidLead"]  = "Takes raid lead, no premade",
    ["PremadeTargetRaidLeadAlso"] = "Also takes raid lead",
    -- Personal watchlist: the owner asked to see this player. Says nothing
    -- about premades, and must not be worded as if it did.
    ["PremadeTargetWatched"]   = "On your watchlist",
    ["PremadeTargetGroups"]    = "Premades",
    ["PremadeTargetClick"]     = "Left-click: target this player. Right-click: set focus (keeps your current target)",
    ["PremadeTargetsEnemySection"] = "Enemy team",
    ["PremadeTargetsAllySection"]  = "Your team",
    ["PremadeTargetsEnemyShort"]   = "enemy",
    ["PremadeTargetsAllyShort"]    = "your team",
    ["PremadeTargetSideEnemy"]     = "On the enemy team",
    ["PremadeTargetSideAlly"]      = "On your team",
    ["PremadeTargetsMinimize"]     = "Minimize to a small button",
    ["PremadeTargetsTrayHint"]     = "Left-click: restore the panel. Drag to move.",

    -- Options: targets panel sizing
    ["OptTargetsHeader"]        = "In-match players panel",
    ["OptLanguage"]             = "Language",
    ["OptLanguageTooltip"]      = "Language of the addon interface. \"Auto\" follows your game client. Battleground alerts stay English on every setting, because they are read by a mixed-language battleground.",
    ["OptMinimapButton"]        = "Show the minimap button",
    ["OptMinimapButtonTooltip"] = "A button on the minimap that opens these settings. Drag it around the minimap to move it.",
    ["MinimapTooltipClick"]     = "Click: open settings",
    ["MinimapTooltipDrag"]      = "Drag: move around the minimap",
    ["OptWatchHeader"]         = "Your watchlist",
    ["OptWatchHint"]           = "Players you want to notice in a battleground. Paste a name (copy it in game) and press Add. Kept on this computer only — never uploaded, never shown to anyone else. Names are matched exactly, so a rename breaks the entry.",
    ["OptWatchAdd"]            = "Add",
    ["OptWatchCount"]          = "In your list",
    ["OptWatchDuplicate"]      = "Already in your list.",
    ["OptWatchFull"]           = "The list is full.",
    ["OptWatchBadName"]        = "Could not read that name. Expected Name or Name-Realm.",
    ["OptTargetsScale"]         = "Panel size",
    ["OptTargetsColumns"]       = "Columns",
    ["OptTargetsScaleTooltip"]  = "Scale of the in-match panel listing tracked players of both teams.",
    ["OptTargetsColumnsTooltip"] = "How many name columns each team section is laid out in.",

    -- Commands help
    ["CmdHelp"] = "|cff33ff99PremadeIQ|r commands:\n"
        .. "  /piq status           — show DB size\n"
        .. "  /piq uploader         — show Uploader download URL\n"
        .. "  /piq snapshot         — force snapshot (in BG)\n"
        .. "  /piq premade          — check enemy team for known premades\n"
        .. "  /piq odds             — win chances for this match\n"
        .. "  /piq copy             — copy the last premade alert for chat\n"
        .. "  /piq debug on|off     — toggle verbose debug\n"
        .. "  /piq reset confirm    — wipe DB\n"
        .. "  /piq version          — print version",

    -- Welcome dialog
    ["WelcomeTitle"]   = "PremadeIQ installed!",
    ["WelcomeBody"]    = "PremadeIQ records post-match Epic BG stats into your SavedVariables.\n\n"
        .. "The premade warnings stay silent until you connect: the list of known\n"
        .. "premades is community data, and it arrives with the Uploader.\n\n"
        .. "  1. Install PremadeIQ Uploader (a Discord account is enough —\n"
        .. "     you don't have to join anything)\n"
        .. "  2. Play one Epic BG and let it upload\n\n"
        .. "One finished Epic BG a week keeps it open: premade warnings, the full\n"
        .. "leaderboard and deserters. Free.\n\n"
        .. "Five a week open the rest of the site: player search, match\n"
        .. "breakdowns, enemy leaders. Also free — no subscription anywhere.\n"
        .. "Use /piq uploader to see the link again.",
    -- /go, not /install, and that is deliberate: this short path is
    -- printed by the addon and by nothing else, so a hit on it means
    -- "came from in-game". WoW has no clickable links — chat text
    -- cannot even be selected — so the marker has to survive being
    -- retyped by hand, which a ?from= parameter would not. The server
    -- redirects it to /install. Do NOT "fix" it back, and do not put
    -- /go in any other channel: exclusivity is the whole signal.
    ["UploaderURL"]    = "Uploader download:\nhttps://premadeiq.duckdns.org/go",
    -- Bare address for the copy box: the line above carries a caption and a
    -- newline, which an edit box would show verbatim.
    ["UploaderURLBare"] = "https://premadeiq.duckdns.org/go",
    -- Title of the copy box. Deliberately English everywhere, like the rest
    -- of the copy-out flow (see INTENTIONALLY_EN).
    ["UploaderCopyTitle"] = "Ctrl+C to copy, then open it in your browser:",
    ["DiscordURL"]     = "Discord: https://discord.gg/KGPKRWt4MG",

    ["Got it"]         = "Got it",
    ["Later"]          = "Later",

    -- Options panel (/piq options)
    ["OptionsSubtitle"]      = "Statistics for Epic Battlegrounds",
    ["OptDebug"]             = "Debug mode",
    ["OptDebugTooltip"]      = "Print verbose chat messages on every collected sample. Equivalent to /piq debug on.",
    ["OptPremadeAlert"]        = "Warn me about enemy premades",
    ["OptPremadeAlertTooltip"] = "On entering a battleground, announce known premade leaders (and members, if your tier includes them) on the enemy team. Data comes from the PremadeIQ Uploader.",
    ["OptPremadeSound"]        = "Play a sound on premade alert",
    ["OptPremadeSoundTooltip"] = "Play the raid-warning sound when a premade is detected.",
    ["OptForecast"]            = "Show win chances for the match",
    ["OptForecastTooltip"]     = "Show a win-chance line in the players panel during epic battlegrounds, worked out from both teams' history. Right about 72% of the time — a hint, not a verdict. Costs about 1 MB of memory and no measurable time.",
    ["OptStatsHeader"]       = "Local database",
    ["OptResetBtn"]          = "Wipe local database…",
    ["OptResetConfirm"]      = "This will erase EVERY player, match, and sample stored in PremadeIQ_DB.\n\nThis cannot be undone.",
    ["OptLinksHeader"]       = "Links",
    ["No options panel"]     = "Options panel not available on this client",
}

-- Russian localization
local ruRU = {
    ["Match recorded"]         = "Матч записан",
    ["Players in DB"]          = "Игроков в базе",
    ["Samples"]                = "сэмплов",
    ["Matches"]                = "матчей",
    ["No data yet"]            = "Данных пока нет",
    ["Not in a BG"]            = "Вы не на поле боя",
    ["DB reset"]               = "База очищена.",
    ["Debug on"]               = "режим отладки ВКЛ",
    ["Debug off"]              = "режим отладки ВЫКЛ",
    ["Confirm reset"]          = "Вы уверены, что хотите стереть всю базу? Напишите /piq reset confirm для подтверждения.",

    -- Premade alert
    ["PremadeDetected"]        = "Во вражеской команде ПРЕМЕЙД!",
    ["PremadePossible"]        = "Во вражеской команде возможный премейд",
    ["PremadeNoLeader"]        = "Во вражеской команде ПРЕМЕЙД (лидера нет)!",
    ["PremadeLeaderLine"]      = "Лидер %s — с ним игроков: %d",
    ["PremadeNoLeaderLine"]    = "Премейд %s — регуляров: %d, лидера нет в бою",
    ["PremadeMore"]            = "…и ещё %d",
    ["PremadeGroups"]          = "Замечено лидеров групп у противника: %d",
    ["PremadeLeaders"]         = "Лидеры премейда",
    ["PremadeMembers"]         = "Участники премейда",
    ["PremadeNone"]            = "Известного лидера премейда в этом бою нет",
    ["PremadeCatalogLoaded"]   = "каталог премейдов: %d лидеров (тир: %s)",
    ["PremadeCatalogAge"]      = "список обновлялся %d дней назад",
    ["PremadeCatalogMissing"]  = "каталог премейдов пуст — предупреждениям пока не с чем сверяться. Каталог приходит вместе с Uploader: %s",
    ["CatalogHintNoUploader"]  = "Предупреждения о премейдах молчат: список известных премейдов приходит с Uploader — %s",
    ["CatalogHintStale"]       = "Предупреждения о премейдах молчат: доступ протух. Выгрузи один доигранный эпический бой, и он откроется снова.",
    ["CatalogOutdated"]        = "Список премейдов, по которому идёт сверка, обновлялся %d дней назад — новых премейдов и новых участников в нём нет.",
    ["CatalogOutdatedFix"]     = "Запусти PremadeIQ Uploader — он обновит список. Сейчас тишина на входе в бой значит «мы не знаем», а не «их тут нет».",
    ["UploadSilent"]           = "Не отправлено боёв: %d. Uploader не запускался %d дн.",
    ["UploadSilentSoon"]       = "Доступ к каталогу держится на выгрузке раз в %d дн. — осталось примерно %d.",
    ["UploadSilentLapsed"]     = "Доступ к каталогу, скорее всего, протух: нужна выгрузка раз в %d дн. Запусти Uploader, и он откроется снова.",
    ["UploadPending"]          = "Ждут отправки: %d боёв (Uploader последний раз писал %d дн. назад).",
    ["UploadUpToDate"]         = "Все записанные бои отправлены.",
    ["MatchNeedsReload"]       = "Набери /reload (или выйди из игры) — только тогда WoW запишет этот бой на диск, до этого Uploader его не увидит.",
    -- Copy-flow strings are intentionally English even on a ruRU client: the
    -- premade call-out is pasted into the English-facing community (/rw, Discord).
    ["PremadeCopyTip"]         = "Click «Copy premade alert» (or /piq copy) to copy this for chat",
    ["PremadeCopyHint"]        = "Ctrl+C to copy, then paste into chat (e.g. /rw):",
    ["PremadeCopyNone"]        = "No recent premade alert to copy.",
    ["PremadeCopyBtn"]         = "Copy premade alert",
    ["PremadeCopyBtnTip"]      = "Left-click: copy the enemy-premade line (box opens, Ctrl+C, paste into /rw or Discord). Right-click: hide. Drag to move.",
    ["PremadeTargetLeader"]    = "Известный лидер премейда",
    ["PremadeTargetMember"]    = "Известный участник премейда",
    ["PremadeTargetWatched"]   = "В твоём личном списке",
    ["PremadeTargetGroups"]    = "Премейды",
    ["PremadeTargetClick"]     = "ЛКМ: выбрать в цель. ПКМ: назначить фокусом (текущая цель сохранится)",
    ["PremadeTargetsEnemySection"] = "Команда противника",
    ["PremadeTargetsAllySection"]  = "Твоя команда",
    ["PremadeTargetsEnemyShort"]   = "у противника",
    ["PremadeTargetsAllyShort"]    = "у тебя",
    ["PremadeTargetSideEnemy"]     = "В команде противника",
    ["PremadeTargetSideAlly"]      = "В твоей команде",
    ["PremadeTargetsMinimize"]     = "Свернуть в маленькую кнопку",
    ["PremadeTargetsTrayHint"]     = "ЛКМ — развернуть панель. Перетащить для перемещения.",

    ["OptTargetsHeader"]        = "Панель участников премейдов",
    ["OptLanguage"]             = "Язык",
    ["OptLanguageTooltip"]      = "Язык интерфейса аддона. «Auto» — как в игровом клиенте. Предупреждения в бою остаются английскими при любом выборе: их читает поле боя, говорящее на разных языках.",
    ["OptMinimapButton"]        = "Показывать кнопку на миникарте",
    ["OptMinimapButtonTooltip"] = "Кнопка на миникарте, открывающая эти настройки. Её можно перетаскивать по краю миникарты.",
    ["MinimapTooltipClick"]     = "Клик: открыть настройки",
    ["MinimapTooltipDrag"]      = "Перетаскивание: двигать по миникарте",
    ["OptWatchHeader"]         = "Твой список",
    ["OptWatchHint"]           = "Игроки, которых ты хочешь замечать в бою. Вставь имя (скопируй его в игре) и нажми «Добавить». Хранится только на этом компьютере — никуда не отправляется и никому не видно. Имя сверяется точно, поэтому переименование рвёт запись.",
    ["OptWatchAdd"]            = "Добавить",
    ["OptWatchCount"]          = "В списке",
    ["OptWatchDuplicate"]      = "Уже в списке.",
    ["OptWatchFull"]           = "Список заполнен.",
    ["OptWatchBadName"]        = "Не удалось разобрать имя. Ожидается Имя или Имя-Реалм.",
    ["OptTargetsScale"]         = "Размер панели",
    ["OptTargetsColumns"]       = "Колонки",
    ["OptTargetsScaleTooltip"]  = "Масштаб панели, которая в бою показывает известных участников премейдов обеих команд.",
    ["OptTargetsColumnsTooltip"] = "Сколько колонок с именами в каждой секции.",

    ["CmdHelp"] = "|cff33ff99PremadeIQ|r команды:\n"
        .. "  /piq status           — размер базы\n"
        .. "  /piq uploader         — ссылка на скачивание Uploader'а\n"
        .. "  /piq snapshot         — снять снимок вручную (в BG)\n"
        .. "  /piq premade          — проверить врага на известные премейды\n"
        .. "  /piq odds             — шансы на победу в этом бою\n"
        .. "  /piq copy             — скопировать последнее уведомление для чата\n"
        .. "  /piq debug on|off     — режим отладки\n"
        .. "  /piq reset confirm    — стереть базу\n"
        .. "  /piq version          — версия",

    ["WelcomeTitle"]   = "PremadeIQ установлен!",
    ["WelcomeBody"]    = "PremadeIQ записывает статистику эпических боёв в ваши SavedVariables.\n\n"
        .. "Предупреждения о премейдах будут молчать, пока ты не подключишься:\n"
        .. "список известных премейдов — это данные сообщества, и приносит их Uploader.\n\n"
        .. "  1. Установи PremadeIQ Uploader (хватит аккаунта Discord —\n"
        .. "     вступать никуда не нужно)\n"
        .. "  2. Сыграй один эпический бой и дай ему выгрузиться\n\n"
        .. "Один доигранный эпический бой в неделю держит доступ открытым:\n"
        .. "предупреждения о премейдах, полный лидерборд, дезертиры. Бесплатно.\n\n"
        .. "Пять боёв за неделю открывают остальной сайт: поиск игрока,\n"
        .. "разбор матчей, вражеские лидеры. Тоже бесплатно, без подписки.\n"
        .. "Команда /piq uploader покажет ссылку ещё раз.",
    ["UploaderURL"]    = "Скачать Uploader:\nhttps://premadeiq.duckdns.org/go",
    ["DiscordURL"]     = "Discord: https://discord.gg/KGPKRWt4MG",

    ["Got it"]         = "Понятно",
    ["Later"]          = "Позже",

    -- Options panel (/piq options)
    ["OptionsSubtitle"]      = "Статистика для эпических полей боя",
    ["OptDebug"]             = "Режим отладки",
    ["OptDebugTooltip"]      = "Подробные сообщения в чат на каждый собранный сэмпл. Эквивалент /piq debug on.",
    ["OptPremadeAlert"]        = "Предупреждать о вражеских премейдах",
    ["OptPremadeAlertTooltip"] = "При заходе на поле боя показывать известных лидеров премейдов (и участников, если позволяет ваш тир) во вражеской команде. Данные — от PremadeIQ Uploader.",
    ["OptPremadeSound"]        = "Звук при обнаружении премейда",
    ["OptPremadeSoundTooltip"] = "Проигрывать звук рейд-предупреждения при обнаружении премейда.",
    ["OptForecast"]            = "Показывать шансы на победу",
    ["OptForecastTooltip"]     = "Строка в панели игроков с шансами обеих команд в эпических полях боя, посчитанная по их прошлым боям. Верна примерно в 72% случаев — это подсказка, а не приговор. Занимает около 1 МБ памяти, на производительность не влияет.",
    ["ForecastPanelWorking"]      = "Шансы %d%% — %d%%   (ВР %d против %d, новых %d%% против %d%%)   считаю...",
    ["ForecastPanelDone"]         = "Шансы %d%% — %d%%   (ВР %d против %d, новых %d%% против %d%%)   итог",
    ["ForecastPending"]           = "Шансы: читаю табло...",
    ["ForecastTipTitle"]          = "Шансы на победу в этом бою",
    ["ForecastTipSides"]          = "Мы %d%%  —  Враг %d%%",
    ["ForecastTipWr"]             = "Средний винрейт: %d%% против %d%%",
    ["ForecastTipNew"]            = "Впервые в базе: %d%% против %d%%",
    ["ForecastTipKnown"]          = "Нашлось в базе: %d из %d против %d из %d",
    ["ForecastTipAcc"]            = "Верно примерно в %d%% случаев — это прогноз, а не приговор.",
    ["ForecastTipLocked"]         = "Зафиксировано по стартовому составу — именно на нём прогноз и проверяли.",
    ["ForecastTipWorking"]        = "Ещё меняется: табло пока заполняется.",
    ["ForecastTipCopy"]           = "Клик — скопировать для чата",
    ["ForecastNoData"]            = "известных игроков пока мало: %d из %d у нас, %d из %d у врага (нужно по %d)",
    ["ForecastNotInBG"]           = "шансы считаются только на поле боя",
    ["ForecastNotEBG"]            = "шансы считаются только в эпических полях боя",
    ["ForecastNoCache"]           = "данных о винрейтах ещё нет — их приносит Uploader",
    ["OptStatsHeader"]       = "Локальная база",
    ["OptResetBtn"]          = "Стереть локальную базу…",
    ["OptResetConfirm"]      = "Это удалит ВСЕХ игроков, матчи и сэмплы из PremadeIQ_DB.\n\nДействие необратимо.",
    ["OptLinksHeader"]       = "Ссылки",
    ["No options panel"]     = "Панель настроек недоступна в этом клиенте",
}

-- German localization
local deDE = {
    ["Match recorded"]         = "Match aufgezeichnet",
    ["Players in DB"]          = "Spieler in der DB",
    ["Samples"]                = "Samples",
    ["Matches"]                = "Matches",
    ["No data yet"]            = "Noch keine Daten",
    ["Not in a BG"]            = "Du bist nicht im BG",
    ["DB reset"]               = "DB zurückgesetzt.",
    ["Debug on"]               = "Debug-Modus AN",
    ["Debug off"]              = "Debug-Modus AUS",
    ["Confirm reset"]          = "Willst du wirklich die gesamte DB löschen? /piq reset confirm zum Bestätigen.",

    ["CmdHelp"] = "|cff33ff99PremadeIQ|r Befehle:\n"
        .. "  /piq status           — DB-Größe anzeigen\n"
        .. "  /piq uploader         — Uploader-Download-Link anzeigen\n"
        .. "  /piq snapshot         — manueller Snapshot (im BG)\n"
        .. "  /piq debug on|off     — Debug-Modus umschalten\n"
        .. "  /piq reset confirm    — DB löschen\n"
        .. "  /piq version          — Version",

    ["WelcomeTitle"]   = "PremadeIQ installiert!",
    ["WelcomeBody"]    = "PremadeIQ zeichnet Statistiken epischer Schlachtfelder in deinen SavedVariables auf.\n\n"
        .. "Die Premade-Hinweise bleiben stumm, bis du dich verbindest: Die Liste\n"
        .. "bekannter Premades sind Community-Daten und kommt mit dem Uploader.\n\n"
        .. "  1. Installiere PremadeIQ Uploader (ein Discord-Konto genügt —\n"
        .. "     du musst nirgendwo beitreten)\n"
        .. "  2. Spiel ein episches BG und lass es hochladen\n\n"
        .. "Ein zu Ende gespieltes episches BG pro Woche hält alles offen:\n"
        .. "Premade-Hinweise, das volle Leaderboard, Deserteure. Kostenlos.\n\n"
        .. "Fünf pro Woche öffnen den Rest der Seite: Spielersuche,\n"
        .. "Match-Analysen, feindliche Anführer. Ebenfalls kostenlos.\n"
        .. "Mit /piq uploader siehst du den Link erneut.",
    ["UploaderURL"]    = "Uploader herunterladen:\nhttps://premadeiq.duckdns.org/go",
    ["DiscordURL"]     = "Discord: https://discord.gg/KGPKRWt4MG",

    ["Got it"]         = "Verstanden",
    ["Later"]          = "Später",
    ["MinimapTooltipClick"]        = "Klick: Einstellungen öffnen",
    ["MinimapTooltipDrag"]         = "Ziehen: um die Minikarte bewegen",
    ["No options panel"]           = "Einstellungsfenster auf diesem Client nicht verfügbar",
    ["OptDebug"]                   = "Debug-Modus",
    ["OptDebugTooltip"]            = "Ausführliche Chatmeldungen zu jeder erfassten Zeile. Entspricht /piq debug on.",
    ["OptLanguage"]                = "Sprache",
    ["OptLanguageTooltip"]         = "Sprache der Addon-Oberfläche. »Auto« folgt deinem Spielclient. Schlachtfeld-Warnungen bleiben in jeder Einstellung englisch, weil sie von einem gemischtsprachigen Schlachtfeld gelesen werden.",
    ["OptLinksHeader"]             = "Links",
    ["OptMinimapButton"]           = "Minikarten-Knopf anzeigen",
    ["OptMinimapButtonTooltip"]    = "Ein Knopf an der Minikarte, der diese Einstellungen öffnet. Zum Verschieben um die Minikarte ziehen.",
    ["OptPremadeAlert"]            = "Vor gegnerischen Premades warnen",
    ["OptPremadeAlertTooltip"]     = "Beim Betreten eines Schlachtfelds bekannte Premade-Anführer melden (und Mitglieder, sofern deine Stufe sie enthält). Die Daten stammen vom PremadeIQ Uploader.",
    ["OptPremadeSound"]            = "Ton bei Premade-Warnung",
    ["OptPremadeSoundTooltip"]     = "Den Schlachtzugswarnungs-Ton abspielen, wenn ein Premade erkannt wird.",
    ["OptForecast"]            = "Siegchancen anzeigen",
    ["OptForecastTooltip"]     = "Eine Zeile im Spielerfenster mit den Chancen beider Teams in epischen Schlachtfeldern, berechnet aus ihren früheren Schlachten. In etwa 72% der Fälle richtig — ein Hinweis, kein Urteil. Braucht rund 1 MB Speicher und kostet keine messbare Leistung.",
    ["ForecastPanelWorking"]      = "Chancen %d%% — %d%%   (SR %d zu %d, neu %d%% zu %d%%)   rechne...",
    ["ForecastPanelDone"]         = "Chancen %d%% — %d%%   (SR %d zu %d, neu %d%% zu %d%%)   endgültig",
    ["ForecastPending"]           = "Chancen: lese die Wertung...",
    ["ForecastTipTitle"]          = "Siegchancen für dieses Match",
    ["ForecastTipSides"]          = "Wir %d%%  —  Gegner %d%%",
    ["ForecastTipWr"]             = "Durchschnittliche Siegrate: %d%% zu %d%%",
    ["ForecastTipNew"]            = "Noch nie gesehen: %d%% zu %d%%",
    ["ForecastTipKnown"]          = "In der Datenbank gefunden: %d von %d zu %d von %d",
    ["ForecastTipAcc"]            = "In etwa %d%% der Fälle richtig — eine Prognose, kein Urteil.",
    ["ForecastTipLocked"]         = "Auf die Startaufstellung festgelegt — genau daran wurde die Prognose gemessen.",
    ["ForecastTipWorking"]        = "Noch in Bewegung: die Wertung füllt sich gerade.",
    ["ForecastTipCopy"]           = "Klicken zum Kopieren für den Chat",
    ["ForecastNoData"]            = "noch zu wenige bekannte Spieler: %d von %d bei uns, %d von %d beim Gegner (je %d nötig)",
    ["ForecastNotInBG"]           = "Chancen gibt es nur im Schlachtfeld",
    ["ForecastNotEBG"]            = "Chancen gibt es nur in epischen Schlachtfeldern",
    ["ForecastNoCache"]           = "noch keine Siegraten-Daten — der Uploader liefert sie",
    ["OptResetBtn"]                = "Lokale Datenbank löschen…",
    ["OptResetConfirm"]            = "Dies löscht JEDEN Spieler, jedes Match und jede Zeile aus PremadeIQ_DB.\n\nDas lässt sich nicht rückgängig machen.",
    ["OptStatsHeader"]             = "Lokale Datenbank",
    ["OptTargetsColumns"]          = "Spalten",
    ["OptTargetsColumnsTooltip"]   = "In wie vielen Namensspalten jeder Teamabschnitt angeordnet wird.",
    ["OptTargetsHeader"]           = "Spielerleiste im Match",
    ["OptTargetsScale"]            = "Leistengröße",
    ["OptTargetsScaleTooltip"]     = "Skalierung der Leiste, die beobachtete Spieler beider Teams auflistet.",
    ["OptWatchAdd"]                = "Hinzufügen",
    ["OptWatchBadName"]            = "Dieser Name war nicht lesbar. Erwartet wird Name oder Name-Realm.",
    ["OptWatchCount"]              = "In deiner Liste",
    ["OptWatchDuplicate"]          = "Steht schon in deiner Liste.",
    ["OptWatchFull"]               = "Die Liste ist voll.",
    ["OptWatchHeader"]             = "Deine Liste",
    ["OptWatchHint"]               = "Spieler, die du im Schlachtfeld bemerken willst. Namen einfügen (im Spiel kopieren) und »Hinzufügen« drücken. Bleibt nur auf diesem Rechner — wird nie hochgeladen und niemandem gezeigt. Namen werden exakt verglichen, eine Umbenennung bricht den Eintrag.",
    ["OptionsSubtitle"]            = "Statistiken für epische Schlachtfelder",
    ["PremadeCatalogLoaded"]       = "Premade-Katalog: %d Anführer (Stufe: %s)",
    ["PremadeCatalogAge"]          = "Liste vor %d Tagen aktualisiert",
    ["PremadeCatalogMissing"]      = "Premade-Katalog ist leer — die Hinweise haben noch nichts zum Abgleichen. Er kommt mit dem Uploader: %s",
    ["CatalogHintNoUploader"]      = "Premade-Hinweise bleiben stumm: Die Liste bekannter Premades kommt mit dem Uploader — %s",
    ["CatalogHintStale"]           = "Premade-Hinweise bleiben stumm: Dein Zugang ist abgelaufen. Lade ein zu Ende gespieltes episches BG hoch, dann geht er wieder auf.",
    ["CatalogOutdated"]            = "Die Premade-Liste, gegen die geprüft wird, ist %d Tage alt — neue Premades und neue Mitglieder fehlen darin.",
    ["CatalogOutdatedFix"]         = "Starte den PremadeIQ Uploader, er frischt die Liste auf. Schweigen beim BG-Start heißt derzeit \"nichts bekannt\", nicht \"niemand da\".",
    ["UploadSilent"]               = "%d Schlachten wurden nicht gesendet — der Uploader lief seit %d Tagen nicht.",
    ["UploadSilentSoon"]           = "Der Katalogzugang braucht alle %d Tage einen Upload — noch etwa %d.",
    ["UploadSilentLapsed"]         = "Der Katalogzugang ist wahrscheinlich abgelaufen: er braucht alle %d Tage einen Upload. Starte den Uploader, dann geht er wieder auf.",
    ["UploadPending"]              = "Warten auf Versand: %d Schlachten (der Uploader schrieb zuletzt vor %d Tagen).",
    ["UploadUpToDate"]             = "Alle aufgezeichneten Schlachten wurden gesendet.",
    ["MatchNeedsReload"]           = "Gib /reload ein (oder logge dich aus) — erst dann schreibt WoW dieses Match auf die Festplatte, vorher sieht der Uploader es nicht.",
    ["PremadeLeaders"]             = "Premade-Anführer",
    ["PremadeMembers"]             = "Premade-Mitglieder",
    ["PremadeNone"]                = "Kein bekannter Premade-Anführer in diesem Match",
}

-- French localization
local frFR = {
    ["Match recorded"]         = "Match enregistré",
    ["Players in DB"]          = "Joueurs dans la base",
    ["Samples"]                = "échantillons",
    ["Matches"]                = "matchs",
    ["No data yet"]            = "Pas encore de données",
    ["Not in a BG"]            = "Vous n'êtes pas en BG",
    ["DB reset"]               = "Base réinitialisée.",
    ["Debug on"]               = "mode debug ACTIVÉ",
    ["Debug off"]              = "mode debug DÉSACTIVÉ",
    ["Confirm reset"]          = "Effacer vraiment toute la base ? Tapez /piq reset confirm pour confirmer.",

    ["CmdHelp"] = "|cff33ff99PremadeIQ|r commandes :\n"
        .. "  /piq status           — taille de la base\n"
        .. "  /piq uploader         — lien de téléchargement de l'Uploader\n"
        .. "  /piq snapshot         — capture manuelle (en BG)\n"
        .. "  /piq debug on|off     — mode debug\n"
        .. "  /piq reset confirm    — effacer la base\n"
        .. "  /piq version          — version",

    ["WelcomeTitle"]   = "PremadeIQ installé !",
    ["WelcomeBody"]    = "PremadeIQ enregistre les stats des BG épiques dans vos SavedVariables.\n\n"
        .. "Les alertes premade restent muettes tant que vous n'êtes pas connecté :\n"
        .. "la liste des premades connus vient de la communauté, via l'Uploader.\n\n"
        .. "  1. Installez PremadeIQ Uploader (un compte Discord suffit —\n"
        .. "     inutile de rejoindre quoi que ce soit)\n"
        .. "  2. Jouez un BG épique et laissez-le s'envoyer\n\n"
        .. "Un BG épique terminé par semaine garde tout ouvert : alertes premade,\n"
        .. "classement complet, déserteurs. Gratuit.\n\n"
        .. "Cinq par semaine ouvrent le reste du site : recherche de joueur,\n"
        .. "analyse des matchs, leaders adverses. Gratuit aussi.\n"
        .. "La commande /piq uploader réaffiche le lien.",
    ["UploaderURL"]    = "Télécharger l'Uploader :\nhttps://premadeiq.duckdns.org/go",
    ["DiscordURL"]     = "Discord : https://discord.gg/KGPKRWt4MG",

    ["Got it"]         = "Compris",
    ["Later"]          = "Plus tard",
    ["MinimapTooltipClick"]        = "Clic : ouvrir les réglages",
    ["MinimapTooltipDrag"]         = "Glisser : déplacer autour de la minicarte",
    ["No options panel"]           = "Fenêtre de réglages indisponible sur ce client",
    ["OptDebug"]                   = "Mode débogage",
    ["OptDebugTooltip"]            = "Afficher des messages détaillés pour chaque ligne collectée. Équivaut à /piq debug on.",
    ["OptLanguage"]                = "Langue",
    ["OptLanguageTooltip"]         = "Langue de l'interface de l'addon. « Auto » suit votre client de jeu. Les alertes de champ de bataille restent en anglais quel que soit le réglage, car elles sont lues par un champ de bataille multilingue.",
    ["OptLinksHeader"]             = "Liens",
    ["OptMinimapButton"]           = "Afficher le bouton de minicarte",
    ["OptMinimapButtonTooltip"]    = "Un bouton sur la minicarte qui ouvre ces réglages. Faites-le glisser autour de la minicarte pour le déplacer.",
    ["OptPremadeAlert"]            = "M'avertir des premades ennemis",
    ["OptPremadeAlertTooltip"]     = "À l'entrée dans un champ de bataille, annoncer les chefs de premade connus (et les membres, si votre palier les inclut) dans l'équipe adverse. Les données viennent de PremadeIQ Uploader.",
    ["OptPremadeSound"]            = "Jouer un son lors d'une alerte",
    ["OptPremadeSoundTooltip"]     = "Jouer le son d'avertissement de raid quand un premade est détecté.",
    ["OptForecast"]            = "Afficher les chances de victoire",
    ["OptForecastTooltip"]     = "Une ligne dans le panneau des joueurs avec les chances des deux équipes dans les champs de bataille épiques, calculées d'après leurs batailles passées. Juste environ 72% du temps — une indication, pas un verdict. Environ 1 Mo de mémoire, aucun coût mesurable.",
    ["ForecastPanelWorking"]      = "Chances %d%% — %d%%   (TV %d contre %d, nouveaux %d%% contre %d%%)   calcul...",
    ["ForecastPanelDone"]         = "Chances %d%% — %d%%   (TV %d contre %d, nouveaux %d%% contre %d%%)   final",
    ["ForecastPending"]           = "Chances : lecture du tableau...",
    ["ForecastTipTitle"]          = "Chances de victoire pour ce match",
    ["ForecastTipSides"]          = "Nous %d%%  —  Ennemi %d%%",
    ["ForecastTipWr"]             = "Taux de victoire moyen : %d%% contre %d%%",
    ["ForecastTipNew"]            = "Jamais vus : %d%% contre %d%%",
    ["ForecastTipKnown"]          = "Trouvés dans la base : %d sur %d contre %d sur %d",
    ["ForecastTipAcc"]            = "Juste environ %d%% du temps — une prévision, pas un verdict.",
    ["ForecastTipLocked"]         = "Figé sur la composition de départ — celle sur laquelle la prévision a été mesurée.",
    ["ForecastTipWorking"]        = "Encore en mouvement : le tableau se remplit.",
    ["ForecastTipCopy"]           = "Cliquer pour copier vers le chat",
    ["ForecastNoData"]            = "trop peu de joueurs connus : %d sur %d chez nous, %d sur %d en face (il en faut %d de chaque côté)",
    ["ForecastNotInBG"]           = "les chances ne sont disponibles que dans un champ de bataille",
    ["ForecastNotEBG"]            = "les chances ne sont disponibles que dans les champs de bataille épiques",
    ["ForecastNoCache"]           = "pas encore de données de taux de victoire — l'Uploader les apporte",
    ["OptResetBtn"]                = "Effacer la base locale…",
    ["OptResetConfirm"]            = "Ceci effacera CHAQUE joueur, match et ligne stockés dans PremadeIQ_DB.\n\nCette action est irréversible.",
    ["OptStatsHeader"]             = "Base de données locale",
    ["OptTargetsColumns"]          = "Colonnes",
    ["OptTargetsColumnsTooltip"]   = "Nombre de colonnes de noms dans chaque section d'équipe.",
    ["OptTargetsHeader"]           = "Panneau des joueurs en match",
    ["OptTargetsScale"]            = "Taille du panneau",
    ["OptTargetsScaleTooltip"]     = "Échelle du panneau listant les joueurs suivis des deux équipes.",
    ["OptWatchAdd"]                = "Ajouter",
    ["OptWatchBadName"]            = "Nom illisible. Format attendu : Nom ou Nom-Royaume.",
    ["OptWatchCount"]              = "Dans votre liste",
    ["OptWatchDuplicate"]          = "Déjà dans votre liste.",
    ["OptWatchFull"]               = "La liste est pleine.",
    ["OptWatchHeader"]             = "Votre liste",
    ["OptWatchHint"]               = "Joueurs que vous voulez repérer en champ de bataille. Collez un nom (copiez-le en jeu) puis appuyez sur Ajouter. Conservé sur cet ordinateur uniquement — jamais envoyé, jamais montré à personne. Les noms sont comparés à l'identique, un changement de nom casse l'entrée.",
    ["OptionsSubtitle"]            = "Statistiques des champs de bataille épiques",
    ["PremadeCatalogLoaded"]       = "catalogue premade : %d chefs (palier : %s)",
    ["PremadeCatalogAge"]          = "liste mise à jour il y a %d jours",
    ["PremadeCatalogMissing"]      = "le catalogue premade est vide — les alertes n'ont rien à comparer. Il arrive avec l'Uploader : %s",
    ["CatalogHintNoUploader"]      = "Les alertes premade sont muettes : la liste des premades connus vient avec l'Uploader — %s",
    ["CatalogHintStale"]           = "Les alertes premade sont muettes : votre accès a expiré. Envoyez un BG épique terminé pour le rouvrir.",
    ["CatalogOutdated"]            = "La liste de premades utilisée pour la comparaison date de %d jours — les nouvelles premades et les nouveaux membres n'y sont pas.",
    ["CatalogOutdatedFix"]         = "Lancez PremadeIQ Uploader : il met la liste à jour. Pour l'instant, le silence à l'entrée d'un BG signifie « on ne sait pas », pas « il n'y a personne ».",
    ["UploadSilent"]               = "%d batailles n'ont pas été envoyées — l'Uploader n'a pas tourné depuis %d jours.",
    ["UploadSilentSoon"]           = "L'accès au catalogue demande un envoi tous les %d jours — il en reste environ %d.",
    ["UploadSilentLapsed"]         = "L'accès au catalogue a probablement expiré : il demande un envoi tous les %d jours. Lancez l'Uploader pour le rouvrir.",
    ["UploadPending"]              = "En attente d'envoi : %d batailles (l'Uploader a écrit il y a %d jours).",
    ["UploadUpToDate"]             = "Toutes les batailles enregistrées ont été envoyées.",
    ["MatchNeedsReload"]           = "Tapez /reload (ou déconnectez-vous) : c'est seulement là que WoW écrit ce match sur le disque, avant cela l'Uploader ne le voit pas.",
    ["PremadeLeaders"]             = "Chefs de premade",
    ["PremadeMembers"]             = "Membres de premade",
    ["PremadeNone"]                = "Aucun chef de premade connu dans ce match",
}

-- Spanish localization
local esES = {
    ["Match recorded"]         = "Partida registrada",
    ["Players in DB"]          = "Jugadores en la base",
    ["Samples"]                = "muestras",
    ["Matches"]                = "partidas",
    ["No data yet"]            = "Aún no hay datos",
    ["Not in a BG"]            = "No estás en un BG",
    ["DB reset"]               = "Base reiniciada.",
    ["Debug on"]               = "modo debug ACTIVADO",
    ["Debug off"]              = "modo debug DESACTIVADO",
    ["Confirm reset"]          = "¿Borrar realmente toda la base? Escribe /piq reset confirm para confirmar.",

    ["CmdHelp"] = "|cff33ff99PremadeIQ|r comandos:\n"
        .. "  /piq status           — tamaño de la base\n"
        .. "  /piq uploader         — enlace de descarga del Uploader\n"
        .. "  /piq snapshot         — captura manual (en BG)\n"
        .. "  /piq debug on|off     — modo debug\n"
        .. "  /piq reset confirm    — borrar base\n"
        .. "  /piq version          — versión",

    ["WelcomeTitle"]   = "¡PremadeIQ instalado!",
    ["WelcomeBody"]    = "PremadeIQ registra las estadísticas de los BG épicos en tus SavedVariables.\n\n"
        .. "Los avisos de premade seguirán en silencio hasta que te conectes:\n"
        .. "la lista de premades conocidos es dato de la comunidad y llega con el Uploader.\n\n"
        .. "  1. Instala PremadeIQ Uploader (basta una cuenta de Discord —\n"
        .. "     no hace falta entrar en ningún sitio)\n"
        .. "  2. Juega un BG épico y deja que se suba\n\n"
        .. "Un BG épico terminado por semana lo mantiene abierto: avisos de premade,\n"
        .. "clasificación completa, desertores. Gratis.\n\n"
        .. "Cinco por semana abren el resto del sitio: búsqueda de jugador,\n"
        .. "análisis de partidas, líderes enemigos. También gratis.\n"
        .. "El comando /piq uploader vuelve a mostrar el enlace.",
    ["UploaderURL"]    = "Descargar Uploader:\nhttps://premadeiq.duckdns.org/go",
    ["DiscordURL"]     = "Discord: https://discord.gg/KGPKRWt4MG",

    ["Got it"]         = "Entendido",
    ["Later"]          = "Más tarde",
    ["MinimapTooltipClick"]        = "Clic: abrir ajustes",
    ["MinimapTooltipDrag"]         = "Arrastrar: mover alrededor del minimapa",
    ["No options panel"]           = "Panel de ajustes no disponible en este cliente",
    ["OptDebug"]                   = "Modo de depuración",
    ["OptDebugTooltip"]            = "Mostrar mensajes detallados por cada línea recogida. Equivale a /piq debug on.",
    ["OptLanguage"]                = "Idioma",
    ["OptLanguageTooltip"]         = "Idioma de la interfaz del addon. «Auto» sigue a tu cliente de juego. Los avisos de campo de batalla siguen en inglés con cualquier ajuste, porque los lee un campo de batalla multilingüe.",
    ["OptLinksHeader"]             = "Enlaces",
    ["OptMinimapButton"]           = "Mostrar el botón del minimapa",
    ["OptMinimapButtonTooltip"]    = "Un botón en el minimapa que abre estos ajustes. Arrástralo alrededor del minimapa para moverlo.",
    ["OptPremadeAlert"]            = "Avisarme de premades enemigos",
    ["OptPremadeAlertTooltip"]     = "Al entrar en un campo de batalla, anunciar a los líderes de premade conocidos (y a los miembros, si tu nivel los incluye) en el equipo rival. Los datos vienen de PremadeIQ Uploader.",
    ["OptPremadeSound"]            = "Sonido al detectar un premade",
    ["OptPremadeSoundTooltip"]     = "Reproducir el sonido de aviso de banda cuando se detecta un premade.",
    ["OptForecast"]            = "Mostrar probabilidades de victoria",
    ["OptForecastTooltip"]     = "Una línea en el panel de jugadores con las probabilidades de ambos equipos en campos de batalla épicos, calculadas a partir de sus batallas anteriores. Acierta cerca del 72% de las veces: es una pista, no un veredicto. Ocupa alrededor de 1 MB y no afecta al rendimiento.",
    ["ForecastPanelWorking"]      = "Probabilidades %d%% — %d%%   (TV %d contra %d, nuevos %d%% contra %d%%)   calculando...",
    ["ForecastPanelDone"]         = "Probabilidades %d%% — %d%%   (TV %d contra %d, nuevos %d%% contra %d%%)   final",
    ["ForecastPending"]           = "Probabilidades: leyendo la tabla...",
    ["ForecastTipTitle"]          = "Probabilidades de victoria en este combate",
    ["ForecastTipSides"]          = "Nosotros %d%%  —  Enemigo %d%%",
    ["ForecastTipWr"]             = "Tasa de victoria media: %d%% contra %d%%",
    ["ForecastTipNew"]            = "Nunca vistos: %d%% contra %d%%",
    ["ForecastTipKnown"]          = "Encontrados en la base: %d de %d contra %d de %d",
    ["ForecastTipAcc"]            = "Acierta cerca del %d%% de las veces: es un pronóstico, no un veredicto.",
    ["ForecastTipLocked"]         = "Fijado con la alineación inicial, la misma con la que se midió el pronóstico.",
    ["ForecastTipWorking"]        = "Todavía cambia: la tabla se está llenando.",
    ["ForecastTipCopy"]           = "Clic para copiar al chat",
    ["ForecastNoData"]            = "aún hay pocos jugadores conocidos: %d de %d en nuestro lado, %d de %d en el suyo (hacen falta %d en cada uno)",
    ["ForecastNotInBG"]           = "las probabilidades solo están disponibles dentro de un campo de batalla",
    ["ForecastNotEBG"]            = "las probabilidades solo están disponibles en campos de batalla épicos",
    ["ForecastNoCache"]           = "todavía no hay datos de tasas de victoria: los trae el Uploader",
    ["OptResetBtn"]                = "Borrar la base local…",
    ["OptResetConfirm"]            = "Esto borrará TODOS los jugadores, partidas y líneas guardados en PremadeIQ_DB.\n\nNo se puede deshacer.",
    ["OptStatsHeader"]             = "Base de datos local",
    ["OptTargetsColumns"]          = "Columnas",
    ["OptTargetsColumnsTooltip"]   = "Cuántas columnas de nombres tiene cada sección de equipo.",
    ["OptTargetsHeader"]           = "Panel de jugadores en partida",
    ["OptTargetsScale"]            = "Tamaño del panel",
    ["OptTargetsScaleTooltip"]     = "Escala del panel que lista a los jugadores seguidos de ambos equipos.",
    ["OptWatchAdd"]                = "Añadir",
    ["OptWatchBadName"]            = "No se pudo leer ese nombre. Se espera Nombre o Nombre-Reino.",
    ["OptWatchCount"]              = "En tu lista",
    ["OptWatchDuplicate"]          = "Ya está en tu lista.",
    ["OptWatchFull"]               = "La lista está llena.",
    ["OptWatchHeader"]             = "Tu lista",
    ["OptWatchHint"]               = "Jugadores que quieres detectar en un campo de batalla. Pega un nombre (cópialo en el juego) y pulsa Añadir. Se guarda solo en este ordenador: nunca se envía ni se muestra a nadie. Los nombres se comparan exactamente, así que un cambio de nombre rompe la entrada.",
    ["OptionsSubtitle"]            = "Estadísticas de campos de batalla épicos",
    ["PremadeCatalogLoaded"]       = "catálogo de premades: %d líderes (nivel: %s)",
    ["PremadeCatalogAge"]          = "lista actualizada hace %d días",
    ["PremadeCatalogMissing"]      = "el catálogo de premades está vacío — los avisos no tienen con qué comparar. Llega con el Uploader: %s",
    ["CatalogHintNoUploader"]      = "Los avisos de premade están en silencio: la lista de premades conocidos llega con el Uploader — %s",
    ["CatalogHintStale"]           = "Los avisos de premade están en silencio: tu acceso caducó. Sube un BG épico terminado y se abre otra vez.",
    ["CatalogOutdated"]            = "La lista de premades con la que se compara tiene %d días — le faltan las premades y los miembros nuevos.",
    ["CatalogOutdatedFix"]         = "Abre PremadeIQ Uploader: él actualiza la lista. Ahora mismo el silencio al entrar en un BG significa «no lo sabemos», no «no hay nadie».",
    ["UploadSilent"]               = "%d batallas no se han enviado: el Uploader no se ejecuta desde hace %d días.",
    ["UploadSilentSoon"]           = "El acceso al catálogo necesita una subida cada %d días: quedan unos %d.",
    ["UploadSilentLapsed"]         = "El acceso al catálogo probablemente caducó: necesita una subida cada %d días. Abre el Uploader y se reabre.",
    ["UploadPending"]              = "Pendientes de envío: %d batallas (el Uploader escribió hace %d días).",
    ["UploadUpToDate"]             = "Todas las batallas registradas se han enviado.",
    ["MatchNeedsReload"]           = "Escribe /reload (o cierra sesión): solo entonces WoW escribe este partido en el disco, antes el Uploader no lo ve.",
    ["PremadeLeaders"]             = "Líderes de premade",
    ["PremadeMembers"]             = "Miembros de premade",
    ["PremadeNone"]                = "Ningún líder de premade conocido en esta partida",
}

-- ── Language resolution ─────────────────────────────────────────────────
--
-- The alert lines are broadcast into /rw and read by a mixed-language
-- battleground, so they stay English on every client — the same lingua-franca
-- convention the server's roster_analyzer follows. The targets panel sits on
-- screen during the match and is read by stream viewers, so it stays English
-- too (owner call).
--
-- A NAMED table, not an inline list inside the loop: two tests parse this file
-- as text to check the rule is still applied, and an anonymous list forced them
-- to split on source fragments — which silently stops matching the moment the
-- file is restructured, leaving a green test that guards nothing.
-- Italian. Added 2026-08-14: Pozzo dell'Eternità and Nemesis are the two
-- Italian realms in our data, together 1.3% of everyone we have seen.
local itIT = {
    ["DB reset"]                   = "database locale cancellato",
    ["DiscordURL"]                 = "Discord: https://discord.gg/KGPKRWt4MG",
    ["Later"]                      = "Più tardi",
    ["Match recorded"]             = "Partita registrata",
    ["Matches"]                    = "partite",
    ["MinimapTooltipClick"]        = "Clic: apri le impostazioni",
    ["MinimapTooltipDrag"]         = "Trascina: sposta attorno alla minimappa",
    ["No data yet"]                = "Ancora nessun dato",
    ["No options panel"]           = "Pannello impostazioni non disponibile su questo client",
    ["Not in a BG"]                = "Non sei in un campo di battaglia",
    ["OptDebug"]                   = "Modalità debug",
    ["OptDebugTooltip"]            = "Mostra messaggi dettagliati per ogni riga raccolta. Equivale a /piq debug on.",
    ["OptLanguage"]                = "Lingua",
    ["OptLanguageTooltip"]         = "Lingua dell'interfaccia dell'addon. «Auto» segue il client di gioco. Gli avvisi del campo di battaglia restano in inglese con qualsiasi impostazione, perché li legge un campo di battaglia multilingue.",
    ["OptLinksHeader"]             = "Collegamenti",
    ["OptMinimapButton"]           = "Mostra il pulsante sulla minimappa",
    ["OptMinimapButtonTooltip"]    = "Un pulsante sulla minimappa che apre queste impostazioni. Trascinalo attorno alla minimappa per spostarlo.",
    ["OptPremadeAlert"]            = "Avvisami dei premade nemici",
    ["OptPremadeAlertTooltip"]     = "All'ingresso in un campo di battaglia, segnala i capi premade noti (e i membri, se il tuo livello li include) nella squadra avversaria. I dati arrivano da PremadeIQ Uploader.",
    ["OptPremadeSound"]            = "Suono all'avviso premade",
    ["OptPremadeSoundTooltip"]     = "Riproduce il suono di avviso incursione quando viene rilevato un premade.",
    ["OptForecast"]            = "Mostra le probabilità di vittoria",
    ["OptForecastTooltip"]     = "Una riga nel pannello giocatori con le probabilità di entrambe le squadre nei campi di battaglia epici, calcolate dalle loro battaglie precedenti. Corretta circa il 72% delle volte: un suggerimento, non un verdetto. Occupa circa 1 MB e non incide sulle prestazioni.",
    ["ForecastPanelWorking"]      = "Probabilità %d%% — %d%%   (TV %d contro %d, nuovi %d%% contro %d%%)   calcolo...",
    ["ForecastPanelDone"]         = "Probabilità %d%% — %d%%   (TV %d contro %d, nuovi %d%% contro %d%%)   finale",
    ["ForecastPending"]           = "Probabilità: leggo il tabellone...",
    ["ForecastTipTitle"]          = "Probabilità di vittoria in questa battaglia",
    ["ForecastTipSides"]          = "Noi %d%%  —  Nemico %d%%",
    ["ForecastTipWr"]             = "Percentuale di vittorie media: %d%% contro %d%%",
    ["ForecastTipNew"]            = "Mai visti prima: %d%% contro %d%%",
    ["ForecastTipKnown"]          = "Trovati nel database: %d su %d contro %d su %d",
    ["ForecastTipAcc"]            = "Corretta circa il %d%% delle volte: una previsione, non un verdetto.",
    ["ForecastTipLocked"]         = "Fissata sulla formazione iniziale, quella su cui la previsione è stata misurata.",
    ["ForecastTipWorking"]        = "Ancora in movimento: il tabellone si sta riempiendo.",
    ["ForecastTipCopy"]           = "Clic per copiare nella chat",
    ["ForecastNoData"]            = "ancora pochi giocatori noti: %d su %d da noi, %d su %d dai nemici (ne servono %d per parte)",
    ["ForecastNotInBG"]           = "le probabilità sono disponibili solo dentro un campo di battaglia",
    ["ForecastNotEBG"]            = "le probabilità sono disponibili solo nei campi di battaglia epici",
    ["ForecastNoCache"]           = "nessun dato sulle percentuali di vittoria: li porta l'Uploader",
    ["OptResetBtn"]                = "Cancella il database locale…",
    ["OptResetConfirm"]            = "Questo cancellerà OGNI giocatore, partita e riga salvati in PremadeIQ_DB.\n\nL'operazione non è reversibile.",
    ["OptStatsHeader"]             = "Database locale",
    ["OptTargetsColumns"]          = "Colonne",
    ["OptTargetsColumnsTooltip"]   = "Quante colonne di nomi ha ogni sezione di squadra.",
    ["OptTargetsHeader"]           = "Pannello giocatori in partita",
    ["OptTargetsScale"]            = "Dimensione del pannello",
    ["OptTargetsScaleTooltip"]     = "Scala del pannello che elenca i giocatori seguiti di entrambe le squadre.",
    ["OptWatchAdd"]                = "Aggiungi",
    ["OptWatchBadName"]            = "Nome non leggibile. Atteso Nome oppure Nome-Reame.",
    ["OptWatchCount"]              = "Nella tua lista",
    ["OptWatchDuplicate"]          = "È già nella tua lista.",
    ["OptWatchFull"]               = "La lista è piena.",
    ["OptWatchHeader"]             = "La tua lista",
    ["OptWatchHint"]               = "Giocatori che vuoi notare in un campo di battaglia. Incolla un nome (copialo in gioco) e premi Aggiungi. Resta solo su questo computer: non viene mai inviato né mostrato a nessuno. I nomi vengono confrontati esattamente, quindi un cambio di nome rompe la voce.",
    ["OptionsSubtitle"]            = "Statistiche per i campi di battaglia epici",
    ["Players in DB"]              = "Giocatori nel database",
    ["PremadeCatalogLoaded"]       = "catalogo premade: %d capi (livello: %s)",
    ["PremadeCatalogAge"]          = "elenco aggiornato %d giorni fa",
    ["PremadeCatalogMissing"]      = "il catalogo premade è vuoto — gli avvisi non hanno ancora nulla con cui confrontare. Arriva con l'Uploader: %s",
    ["CatalogHintNoUploader"]      = "Gli avvisi premade restano muti: l'elenco dei premade noti arriva con l'Uploader — %s",
    ["CatalogHintStale"]           = "Gli avvisi premade restano muti: il tuo accesso è scaduto. Carica un BG epico portato a termine e si riapre.",
    ["CatalogOutdated"]            = "L'elenco delle premade con cui confrontiamo ha %d giorni — mancano le premade e i membri nuovi.",
    ["CatalogOutdatedFix"]         = "Avvia PremadeIQ Uploader: aggiorna l'elenco. Per ora il silenzio all'ingresso in un BG significa «non lo sappiamo», non «non c'è nessuno».",
    ["UploadSilent"]               = "%d battaglie non sono state inviate — l'Uploader non parte da %d giorni.",
    ["UploadSilentSoon"]           = "L'accesso al catalogo richiede un invio ogni %d giorni — ne restano circa %d.",
    ["UploadSilentLapsed"]         = "L'accesso al catalogo è probabilmente scaduto: richiede un invio ogni %d giorni. Avvia l'Uploader e si riapre.",
    ["UploadPending"]              = "In attesa di invio: %d battaglie (l'Uploader ha scritto %d giorni fa).",
    ["UploadUpToDate"]             = "Tutte le battaglie registrate sono state inviate.",
    ["MatchNeedsReload"]           = "Digita /reload (o esci dal gioco): solo allora WoW scrive questa partita su disco, prima l'Uploader non la vede.",
    ["PremadeLeaders"]             = "Capi premade",
    ["PremadeMembers"]             = "Membri premade",
    ["PremadeNone"]                = "Nessun capo premade noto in questa partita",
    ["Samples"]                    = "righe",
    ["UploaderURL"]                = "Download dell'Uploader:\nhttps://premadeiq.duckdns.org/go",
    ["WelcomeBody"]                = "PremadeIQ registra le statistiche dei BG epici nei tuoi SavedVariables.\n\nGli avvisi sui premade restano muti finché non ti colleghi: l'elenco dei premade noti è un dato della comunità e arriva con l'Uploader.\n\n  1. Installa PremadeIQ Uploader (basta un account Discord — non devi entrare da nessuna parte)\n  2. Gioca un BG epico e lascialo caricare\n\nUn BG epico portato a termine a settimana tiene tutto aperto: avvisi sui premade, classifica completa, disertori. Gratis.\n\nCinque a settimana aprono il resto del sito: ricerca giocatore, analisi delle partite, capi nemici. Anche questo gratis.\nUsa /piq uploader per rivedere il link.",
    ["WelcomeTitle"]               = "PremadeIQ installato!",
    ["CmdHelp"]                    = "|cff33ff99PremadeIQ|r comandi:\n  /piq status           — mostra la dimensione del database\n  /piq uploader         — mostra il link di download dell'Uploader\n  /piq snapshot         — forza l'acquisizione (in campo di battaglia)\n  /piq premade          — controlla i premade noti nella squadra avversaria\n  /piq copy             — copia l'ultimo avviso premade per la chat\n  /piq debug on|off     — attiva o disattiva il debug\n  /piq reset confirm    — cancella il database\n  /piq version          — mostra la versione",
    ["Confirm reset"]              = "Vuoi davvero cancellare il database di PremadeIQ? Scrivi /piq reset confirm per procedere.",
    ["Debug off"]                  = "modalità debug DISATTIVA",
    ["Debug on"]                   = "modalità debug ATTIVA",
    ["Got it"]                     = "Ho capito",
}

local FORCE_EN = {
    "PremadeDetected", "PremadePossible", "PremadeNoLeader",
    "PremadeLeaderLine", "PremadeNoLeaderLine", "PremadeMore",
    "PremadeGroups", "RaidLeadDetected",
    "ForecastOdds", "ForecastNote", "ForecastCopy",
    "ForecastCopyFull",
    "PremadeTargetsHeader",
    "PremadeTargetLeader",
    "PremadeTargetMember",
    "PremadeTargetLikely",
    "PremadeTargetLikelyWith",
    "PremadeTargetWatched",
    "PremadeTargetRaidLead",
    "PremadeTargetRaidLeadAlso",
    "PremadeTargetGroups",
    "PremadeTargetClick",
    "PremadeTargetsEnemySection",
    "PremadeTargetsAllySection",
    "PremadeTargetsEnemyShort",
    "PremadeTargetsAllyShort",
    "PremadeTargetSideEnemy",
    "PremadeTargetSideAlly",
    "PremadeTargetsMinimize",
    "PremadeTargetsTrayHint",
}
ns.FORCE_EN = FORCE_EN

-- A SECOND kind of deliberately-English string, and the distinction matters.
-- These are not forced back — a locale may translate them — but nobody has, on
-- purpose: they describe the copy-out flow whose payload is English anyway. The
-- completeness test has to know they are allowed to be missing, or it reports a
-- debt that is not a debt.
ns.INTENTIONALLY_EN = {
    "PremadeCopyHint", "PremadeCopyTip", "PremadeCopyNone",
    "PremadeCopyBtn", "PremadeCopyBtnTip",
    -- Same flow, same reason: the payload is a URL, and "Ctrl+C" reads the
    -- same in every language this addon ships.
    "UploaderCopyTitle",
    -- A bare address is not translatable text.
    "UploaderURLBare",
}

local locales = {
    ruRU = ruRU, deDE = deDE, frFR = frFR, esES = esES, esMX = esES,
    itIT = itIT,
}
ns.LOCALES = locales

-- Short code (what the setting stores, what a human recognises) -> WoW's code.
-- The dictionaries above are keyed the way GetLocale() spells things; the
-- setting is keyed the way a language picker should read.
local SHORT_TO_WOW = {
    en = nil, ru = "ruRU", de = "deDE", fr = "frFR", es = "esES", it = "itIT",
}
ns.LANGUAGE_CODES = { "auto", "en", "ru", "de", "fr", "es", "it" }
ns.LANGUAGE_NAMES = {
    auto = "Auto", en = "English", ru = "Русский",
    de = "Deutsch", fr = "Français", es = "Español", it = "Italiano",
}

-- Rebuild the strings in place for the given short code ("auto" follows the
-- game client).
--
-- IN PLACE is the whole point: every file captured this table once, as
-- `local L = ns.L`, at load time. Assigning ns.L a fresh table would leave all
-- of them holding the old dictionary and the language would change in half the
-- addon — a failure with no error message.
--
-- No wipe() needed, and deliberately so: every locale dictionary is a strict
-- subset of `en` (measured), and nothing anywhere writes into ns.L, so pouring
-- en over the top cannot leave a stale value behind. That also keeps this file
-- free of wipe(), which does not exist in the Lua the CI tests run on.
function ns.ApplyLanguage(short)
    for k, v in pairs(en) do L[k] = v end
    local wow = SHORT_TO_WOW[short]
    if short == nil or short == "auto" then
        wow = GetLocale and GetLocale() or nil
    end
    local active = wow and locales[wow]
    if active then
        for k, v in pairs(active) do L[k] = v end
    end
    -- Applied LAST, and on every rebuild: without this a language switch would
    -- drag the battleground-wide strings along with it.
    for _, k in ipairs(FORCE_EN) do L[k] = en[k] end
    return short or "auto"
end

-- Initial pass follows the client. The saved preference cannot be read here —
-- SavedVariables are populated after every Lua file has executed — so Main
-- re-applies on ADDON_LOADED.
ns.ApplyLanguage("auto")
