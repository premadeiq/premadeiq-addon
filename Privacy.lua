local ADDON, ns = ...
local L = ns.L

-- Persisted under PremadeIQ_DB.privacy: { firstSeenAt, welcomeSeen }
--
-- The addon only ever writes match stats LOCALLY to SavedVariables; it never
-- sends anything out of the game by itself. Contributing to the community
-- database is a deliberate, separate act through the PremadeIQ Uploader app,
-- which has its own flow — so there is no in-game data-sharing toggle here.
local Privacy = {}
ns.Privacy = Privacy

function Privacy:Init()
    local db = PremadeIQ_DB
    db.privacy = db.privacy or {}
    if not db.privacy.firstSeenAt then db.privacy.firstSeenAt = time() end
    self.db = db.privacy
end

function Privacy:HasSeenWelcome() return self.db and self.db.welcomeSeen end
function Privacy:MarkWelcomeSeen() self.db.welcomeSeen = true end

-- One-time welcome with 3-step onboarding to community service.
function Privacy:MaybeShowWelcome()
    if self:HasSeenWelcome() then return end

    StaticPopupDialogs["PREMADEIQ_WELCOME"] = {
        text = L["WelcomeBody"],
        button1 = L["Got it"],
        button2 = L["Later"],
        OnAccept = function() Privacy:MarkWelcomeSeen() end,
        OnCancel = function() end, -- Don't mark seen on "Later" — show again next login
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("PREMADEIQ_WELCOME")
end
