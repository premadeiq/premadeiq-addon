local ADDON, ns = ...

local locale = GetLocale()
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
    ["PremadeLeaders"]         = "Premade leaders",
    ["PremadeMembers"]         = "Premade members",
    ["PremadeNone"]            = "No known premade leader in this match",
    ["PremadeCatalogLoaded"]   = "premade catalog: %d leaders (tier: %s)",
    ["PremadeCatalogMissing"]  = "premade catalog not loaded (upload once via the Uploader, then /reload)",
    ["PremadeCopyTip"]         = "Click «Copy premade alert» (or /piq copy) to copy this for chat",
    ["PremadeCopyHint"]        = "Ctrl+C to copy, then paste into chat (e.g. /rw):",
    ["PremadeCopyNone"]        = "No recent premade alert to copy.",
    ["PremadeCopyBtn"]         = "Copy premade alert",
    ["PremadeCopyBtnTip"]      = "Left-click: copy the enemy-premade line (box opens, Ctrl+C, paste into /rw or Discord). Right-click: hide. Drag to move.",

    -- Commands help
    ["CmdHelp"] = "|cff33ff99PremadeIQ|r commands:\n"
        .. "  /piq status           — show DB size\n"
        .. "  /piq uploader         — show Uploader download URL\n"
        .. "  /piq snapshot         — force snapshot (in BG)\n"
        .. "  /piq premade          — check enemy team for known premades\n"
        .. "  /piq copy             — copy the last premade alert for chat\n"
        .. "  /piq debug on|off     — toggle verbose debug\n"
        .. "  /piq reset confirm    — wipe DB\n"
        .. "  /piq version          — print version",

    -- Welcome dialog
    ["WelcomeTitle"]   = "PremadeIQ installed!",
    ["WelcomeBody"]    = "PremadeIQ collects post-match BG stats into your SavedVariables.\n\n"
        .. "To contribute to the community database and access the website:\n"
        .. "  1. Install PremadeIQ Uploader\n"
        .. "  2. Join our Discord\n"
        .. "  3. Link Discord to your Patreon (King of EBG tier)\n\n"
        .. "Use /piq uploader to get the download link.",
    ["UploaderURL"]    = "Uploader download: https://github.com/premadeiq/premadeiq-uploader/releases/latest",
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
    ["PremadeCatalogMissing"]  = "каталог премейдов не загружен (загрузи бой через Uploader, затем /reload)",
    -- Copy-flow strings are intentionally English even on a ruRU client: the
    -- premade call-out is pasted into the English-facing community (/rw, Discord).
    ["PremadeCopyTip"]         = "Click «Copy premade alert» (or /piq copy) to copy this for chat",
    ["PremadeCopyHint"]        = "Ctrl+C to copy, then paste into chat (e.g. /rw):",
    ["PremadeCopyNone"]        = "No recent premade alert to copy.",
    ["PremadeCopyBtn"]         = "Copy premade alert",
    ["PremadeCopyBtnTip"]      = "Left-click: copy the enemy-premade line (box opens, Ctrl+C, paste into /rw or Discord). Right-click: hide. Drag to move.",

    ["CmdHelp"] = "|cff33ff99PremadeIQ|r команды:\n"
        .. "  /piq status           — размер базы\n"
        .. "  /piq uploader         — ссылка на скачивание Uploader'а\n"
        .. "  /piq snapshot         — снять снимок вручную (в BG)\n"
        .. "  /piq premade          — проверить врага на известные премейды\n"
        .. "  /piq copy             — скопировать последнее уведомление для чата\n"
        .. "  /piq debug on|off     — режим отладки\n"
        .. "  /piq reset confirm    — стереть базу\n"
        .. "  /piq version          — версия",

    ["WelcomeTitle"]   = "PremadeIQ установлен!",
    ["WelcomeBody"]    = "PremadeIQ собирает постматчевую статистику BG в ваши SavedVariables.\n\n"
        .. "Чтобы вносить данные в общую базу и получить доступ к сайту:\n"
        .. "  1. Установи PremadeIQ Uploader\n"
        .. "  2. Зайди в наш Discord\n"
        .. "  3. Привяжи Discord к Patreon (тир King of EBG)\n\n"
        .. "Команда /piq uploader покажет ссылку на скачивание.",
    ["UploaderURL"]    = "Скачать Uploader: https://github.com/premadeiq/premadeiq-uploader/releases/latest",
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
    ["WelcomeBody"]    = "PremadeIQ sammelt Post-Match-BG-Statistiken in deinen SavedVariables.\n\n"
        .. "Um zur Community-Datenbank beizutragen und die Website zu nutzen:\n"
        .. "  1. Installiere PremadeIQ Uploader\n"
        .. "  2. Tritt unserem Discord bei\n"
        .. "  3. Verknüpfe Discord mit Patreon (Stufe King of EBG)\n\n"
        .. "Nutze /piq uploader für den Download-Link.",
    ["UploaderURL"]    = "Uploader herunterladen: https://github.com/premadeiq/premadeiq-uploader/releases/latest",
    ["DiscordURL"]     = "Discord: https://discord.gg/KGPKRWt4MG",

    ["Got it"]         = "Verstanden",
    ["Later"]          = "Später",
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
    ["WelcomeBody"]    = "PremadeIQ collecte les stats post-match des BG dans vos SavedVariables.\n\n"
        .. "Pour contribuer à la base commune et accéder au site :\n"
        .. "  1. Installez PremadeIQ Uploader\n"
        .. "  2. Rejoignez notre Discord\n"
        .. "  3. Liez Discord à Patreon (palier King of EBG)\n\n"
        .. "La commande /piq uploader affiche le lien de téléchargement.",
    ["UploaderURL"]    = "Télécharger l'Uploader : https://github.com/premadeiq/premadeiq-uploader/releases/latest",
    ["DiscordURL"]     = "Discord : https://discord.gg/KGPKRWt4MG",

    ["Got it"]         = "Compris",
    ["Later"]          = "Plus tard",
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
    ["WelcomeBody"]    = "PremadeIQ recopila estadísticas post-match de BG en tus SavedVariables.\n\n"
        .. "Para contribuir a la base común y acceder al sitio:\n"
        .. "  1. Instala PremadeIQ Uploader\n"
        .. "  2. Únete a nuestro Discord\n"
        .. "  3. Vincula Discord a Patreon (nivel King of EBG)\n\n"
        .. "El comando /piq uploader muestra el enlace de descarga.",
    ["UploaderURL"]    = "Descargar Uploader: https://github.com/premadeiq/premadeiq-uploader/releases/latest",
    ["DiscordURL"]     = "Discord: https://discord.gg/KGPKRWt4MG",

    ["Got it"]         = "Entendido",
    ["Later"]          = "Más tarde",
}

-- Apply: merge en first (fallback), then override with the active locale.
for k, v in pairs(en) do L[k] = v end
local locales = { ruRU = ruRU, deDE = deDE, frFR = frFR, esES = esES, esMX = esES }
local active = locales[locale]
if active then
    for k, v in pairs(active) do L[k] = v end
end

-- The premade alert is broadcast into /rw, read by a mixed-language BG, so its
-- lines stay English on every client — same lingua-franca convention as the
-- server's roster_analyzer (_format_message). Force the en values back after
-- the locale merge so a non-English client still shows/copies English.
for _, k in ipairs({
    "PremadeDetected", "PremadePossible", "PremadeNoLeader",
    "PremadeLeaderLine", "PremadeNoLeaderLine", "PremadeMore",
    "PremadeGroups",
}) do
    L[k] = en[k]
end
