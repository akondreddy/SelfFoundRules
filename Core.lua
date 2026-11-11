--[[-------------------------------------------------------------------
    Core.lua

    The shared table, the saved-variable defaults, and the output
    helpers everything else is built on.

    Loads first. Nothing here may depend on another SFR file.
-------------------------------------------------------------------]]--

-- WoW passes every file in an addon two things at the top level:
-- the addon's folder name, and a private table that is THE SAME table
-- for all files in the addon. That table is how files share things
-- without creating globals.
local ADDON, SFR = ...

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------

-- Stays a file-local. Only Say needs it.

local SHORT = "|cff4FC3F7[Self-Found]|r"


----------------------------------------------------------------------
-- Defaults
----------------------------------------------------------------------

local DEFAULTS = {
    strict      = true,   -- auto-close restricted windows
    paused      = false,  -- temporarily disable enforcement
    violations  = {},     -- { time, level, zone, what }
    blocks      = 0,      -- how many times we stopped you
    started     = nil,    -- { level, time }
    resets      = {},     -- archived runs, newest last
    version     = 2,
    history     = {},     -- append-only: { kind, level, time, build, expansion, project, zone, played, rules, detail }
    schema      = 1,      -- data shape, separate from the addon's release version
    screenshots = true,   -- 
}

-- Table shape only. Safe at ADDON_LOADED because it touches nothing
-- but SFR_Data itself.
local function InitDB()
    if type(SFR_Data) ~= "table" then SFR_Data = {} end
    for k, v in pairs(DEFAULTS) do
        if SFR_Data[k] == nil then
            SFR_Data[k] = (type(v) == "table") and {} or v
        end
    end
end

-- Needs the player to exist, so it cannot run before PLAYER_LOGIN.
-- historyBegins is written once and never again -- recording level 0
-- here would be a permanent lie in the one field that exists to be
-- honest about where the record starts.
local function EnsureRun()
    if not SFR_Data.started then
        SFR_Data.started = { level = UnitLevel("player"), time = time() }
    end
    if not SFR_Data.historyBegins then
        SFR_Data.historyBegins = { level = UnitLevel("player"), time = time() }
    end
end



----------------------------------------------------------------------
-- Output helpers
----------------------------------------------------------------------

local function Say(msg)
    print(SHORT .. " " .. msg)
end

local function Warn(msg)
    print("|cffFF5252[Self-Found]|r " .. msg)
    if SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage(msg, 1.0, 0.3, 0.3, 1.0, 6)
    end
end

----------------------------------------------------------------------
-- Small shared utilities
----------------------------------------------------------------------

local function Stamp()
    return date("%Y-%m-%d %H:%M"), UnitLevel("player"), (GetRealZoneText() or "?")
end

-- Lua tables are references. If we just stored SFR_Data.violations
-- in the archive and then set SFR_Data.violations = {}, the archive
-- would be fine -- but if we instead wiped it in place, the archive
-- would empty too. Copying defensively keeps archives immutable.
local function CopyList(src)
    local out = {}
    for i, v in ipairs(src or {}) do
        out[i] = { time = v.time, level = v.level, zone = v.zone, what = v.what }
    end
    return out
end

----------------------------------------------------------------------
-- Database init
----------------------------------------------------------------------

-- ADDON_LOADED rather than PLAYER_LOGIN on purpose.
--
-- Journal.lua's gap check reads SFR_Data.history at login, so InitDB
-- has to have run first. Several frames all registering PLAYER_LOGIN
-- would fire in load order, which happens to be the order we want --
-- but that is a coincidence, and coincidences rot. ADDON_LOADED always
-- fires before PLAYER_LOGIN, so the game guarantees the ordering for us.
local core = CreateFrame("Frame", ADDON .. "CoreFrame")
core:RegisterEvent("ADDON_LOADED")
core:SetScript("OnEvent", function(self, event, loadedAddon)
    -- ADDON_LOADED fires once per addon, for every addon. Ignore the
    -- ones that are not us.
    if loadedAddon ~= ADDON then return end
    InitDB()
    -- Nothing else to do here, so stop listening.
    self:UnregisterEvent("ADDON_LOADED")
end)

----------------------------------------------------------------------
-- Exports
----------------------------------------------------------------------

-- Everything above is a file-local and invisible to the other files.
-- These lines are the entire public surface of Core.lua. Keep the list
-- short: each name added here is a name any other file can now break.

SFR.Say         = Say
SFR.Warn        = Warn
SFR.Stamp       = Stamp
SFR.CopyList    = CopyList
SFR.InitDB      = InitDB
SFR.EnsureRun   = EnsureRun
