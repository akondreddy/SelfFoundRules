--[[-------------------------------------------------------------------
    Journal.lua

    The append-only record: what level was reached, when, on which
    build, under which rules.

    This file knows nothing about mailboxes, auction houses or
    enforcement. It records what happened. Keep it that way -- if
    something in here starts needing to know what a violation is,
    the seam is in the wrong place.
-------------------------------------------------------------------]]--

local ADDON, SFR = ...

-- Pulling the Core helpers into file-locals here means the function
-- bodies below need no edits at all: they still say Say(...) and
-- Stamp(), exactly as they did in the single-file version. This is
-- what makes the split a move rather than a rewrite.
local Say, Warn = SFR.Say, SFR.Warn

-- WOW_PROJECT_ID answers "which flavor is this client" directly, which
-- is the question we have. Feature detection is the right
-- default for capabilities, but not for identity,
--
-- Verified in-game 2026-11-10: Forever = 18, Classic Era = 2, Retail = 1.
-- TBC Anniversary = 
--
local PROJECT_NAMES = {
    [1] = "Retail",
    [2] = "Classic Era",
    [18] = "Forever",
    [5] = "TBC",
}

----------------------------------------------------------------------
-- Build and rules context
----------------------------------------------------------------------

local function CurrentExpansion()
    local version = GetBuildInfo()
    local project = WOW_PROJECT_ID
    local name = PROJECT_NAMES[project] or ("Project " .. tostring(project))
    return name, version, project
end

-- States the current rules that will be recorded in the log
local function CurrentRules()
    if SFR_Data.paused then return "paused" end
    return SFR_Data.strict and "strict" or "warn"
end

----------------------------------------------------------------------
-- Writing to the record
----------------------------------------------------------------------

local function LogEvent(kind, level, detail)
    local expansion, build, project = CurrentExpansion()
    table.insert(SFR_Data.history, {
        kind        = kind,
        level       = level,
        time        = time(),   -- In Unix, not formatted
        build       = build,
        expansion   = expansion,
        project     = project,  -- raw WOW_PROJECT_ID; the label above is derived
        zone        = GetRealZoneText() or "?",
        rules       = CurrentRules(),
        played      = nil,      -- filled in by TIME_PLAYED_MSG if it arrives
        detail      = detail,
    })
end

----------------------------------------------------------------------
-- Reading the record
----------------------------------------------------------------------

local function FormatPlayed(seconds)
    if not seconds then return "played unknown" end
    local d, hr = math.floor(seconds / 86400), math.floor((seconds % 86400) / 3600)
    return ("%dd %dh played"):format(d, hr)
end

-- The shape that we want to structure the event:
-- Level 60 - TBC 2.5.6 - 2027-03-14 - 6d 11h played - rules: strict
local function FormatEvent(e)
    local head
    if e.kind == "level" then
        head = ("Level %s"):format(tostring(e.level or "?"))
    elseif e.kind == "gap" then
        local d = e.detail or {}
        head = ("|cffFFB74DUnobserved: level %s -> %s|r"):format(
            tostring(d.from or "?"), tostring(d.to or "?"))
    elseif e.kind == "reset" then
        local d = e.detail or {}
        head = ("|cffFF5252 - run %s ended -|r %s"):format(
            tostring(d.run or "?"), tostring(d.message or "no message"))
    else
        head = tostring(e.kind or "?")
    end
    return ("%s — %s %s — %s — %s — rules: %s"):format(
        head, e.expansion or "?", e.build or "?",
        date("%Y-%m-%d", e.time or 0), FormatPlayed(e.played), e.rules or "?")
end

local function PrintHistory()
    local h, b = SFR_Data.history, (SFR_Data.historyBegins or {})
    Say(("The chronicle (%d):"):format(#h))
    print(("  Begins at level %s; earlier levels were played but not observed."):format(
        tostring(b.level or "?")))
    for _, e in ipairs(h) do
        print("  " .. FormatEvent(e))
    end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

local journal = CreateFrame("Frame", ADDON .. "JournalFrame")

journal:RegisterEvent("PLAYER_LOGIN")
journal:RegisterEvent("PLAYER_LEVEL_UP")
journal:RegisterEvent("TIME_PLAYED_MSG")

journal:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "PLAYER_LOGIN" then
        SFR.EnsureRun()
        -- Levels gained with the addon off are real but unobserved.
        -- Record the gap; never fabricate the individual level-ups.
        local lvl, lastLevel = UnitLevel("player"), nil
        for i = #SFR_Data.history, 1, -1 do
            if SFR_Data.history[i].kind == "level" then
                -- Break on the first level entry
                lastLevel = SFR_Data.history[i].level
                break
            end
        end
        local from = lastLevel or SFR_Data.historyBegins.level
        if lvl > from then
            -- Log the gapped level
            LogEvent("gap", lvl, { from = from, to = lvl })
        end

        elseif event == "PLAYER_LEVEL_UP" then
        LogEvent("level", arg1)
        RequestTimePlayed()
        Say(("Level %d recorded - %s, rules: %s"): format(
            arg1, select(1, CurrentExpansion()), CurrentRules()))

    elseif event == "TIME_PLAYED_MSG" then
        -- arg1 is the total seconds played. Attaches to the newest entry that
        -- lacks it; if this never fires, played stays nil rather than a guess
        local last = SFR_Data.history[#SFR_Data.history]
        if last and not last.played then last.played = arg1 end
    end
end)

----------------------------------------------------------------------
-- Exports
----------------------------------------------------------------------

SFR.LogEvent         = LogEvent
SFR.CurrentExpansion = CurrentExpansion
SFR.CurrentRules     = CurrentRules
SFR.FormatEvent      = FormatEvent
SFR.PrintHistory     = PrintHistory
