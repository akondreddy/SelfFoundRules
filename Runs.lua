--[[-------------------------------------------------------------------
    Runs.lua

    Resets and archives. A reset works like a git commit: it requires a
    message, it snapshots the run being ended, and it does NOT erase
    what came before.

    "Mutable rules. Immutable history." -- notes/rules.md

    Loads after Journal.lua, because ArchiveAndReset logs the boundary
    event.
-------------------------------------------------------------------]]--

local ADDON, SFR = ...

local Say, Stamp, CopyList = SFR.Say, SFR.Stamp, SFR.CopyList
local LogEvent             = SFR.LogEvent

----------------------------------------------------------------------
-- Archiving
----------------------------------------------------------------------

local function ArchiveAndReset(message)
    local when, lvl, zone = Stamp()
    local s = SFR_Data.started or {}
    -- The boundary IS a history event. History is append-only: a reset
    -- is a new chapter, not an erasure
    LogEvent("reset", lvl, { message = message, run = #SFR_Data.resets + 1 })
    RequestTimePlayed()

    local entry = {
        -- the "commit message"
        message      = message,
        -- when and where the reset happened
        resetTime    = when,
        resetLevel   = lvl,
        resetZone    = zone,
        -- snapshot of the run being archived
        startedLevel = s.level,
        startedTime  = s.time and date("%Y-%m-%d %H:%M", s.time) or "?",
        blocks       = SFR_Data.blocks or 0,
        violations   = CopyList(SFR_Data.violations),
        wasClean     = (#SFR_Data.violations == 0),
        historyAt    = #SFR_Data.history,
    }

    table.insert(SFR_Data.resets, entry)

    -- wipe the live run counters. history is NOT wiped:
    -- immutable history
    SFR_Data.violations = {}
    SFR_Data.blocks     = 0
    SFR_Data.started    = { level = lvl, time = time() }

    local n = #SFR_Data.resets
    Say(("Run archived as reset #%d."):format(n))
    print(("  \"%s\""):format(message))
    print(("  Previous run: level %s -> %d, %d violations, %d blocks, %s"):format(
        tostring(entry.startedLevel or "?"), lvl,
        #entry.violations, entry.blocks,
        entry.wasClean and "|cff81C784CLEAN|r" or "|cffFF5252BROKEN|r"))
    Say("New run started at level " .. lvl .. ".")
end

----------------------------------------------------------------------
-- Reading archives
----------------------------------------------------------------------

local function PrintResetHistory()
    local n = #SFR_Data.resets
    if n == 0 then
        Say("No resets on this character. This is the original run.")
        return
    end

    Say(("Reset history (%d):"):format(n))
    for i, r in ipairs(SFR_Data.resets) do
        print(("  |cffFFFFFF#%d|r  %s  lvl %s->%s  %s  \"%s\""):format(
            i,
            r.resetTime or "?",
            tostring(r.startedLevel or "?"),
            tostring(r.resetLevel or "?"),
            r.wasClean and "|cff81C784clean|r" or
                ("|cffFF5252%d viol|r"):format(#(r.violations or {})),
            r.message or ""))
    end
    print("  /sfr show <n> for full detail")
end

local function ShowReset(n)
    local r = SFR_Data.resets[n]
    if not r then
        Say("No reset #" .. tostring(n) .. ". Try /sfr resets")
        return
    end

    Say(("Reset #%d — \"%s\""):format(n, r.message or ""))
    print(("  Reset at:  %s, level %s, %s"):format(
        r.resetTime or "?", tostring(r.resetLevel or "?"), r.resetZone or "?"))
    print(("  Run began: %s, level %s"):format(
        r.startedTime or "?", tostring(r.startedLevel or "?")))
    print(("  Blocked:   %d times"):format(r.blocks or 0))

    local vs = r.violations or {}
    if #vs == 0 then
        print("  Record:    |cff81C784CLEAN|r")
    else
        print(("  Record:    |cffFF5252BROKEN|r (%d)"):format(#vs))
        for i, v in ipairs(vs) do
            print(("    %d. %s — %s (lvl %d, %s)"):format(
                i, v.time, v.what, v.level, v.zone))
        end
    end
end
----------------------------------------------------------------------
-- Exports
----------------------------------------------------------------------

SFR.ArchiveAndReset   = ArchiveAndReset
SFR.PrintResetHistory = PrintResetHistory
SFR.ShowReset         = ShowReset
