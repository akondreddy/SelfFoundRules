--[[-------------------------------------------------------------------
    Self-Found Rules
    A personal self-found ruleset for Wow Classic / TBC Anniversary, with the intent to build WoW characters without outside help,
    but without the fatality of hardcore mode, similar to OSRS Ironman.

    Rules enforced:
      - No Auction House
      - No mail (sending or receiving)
      - No trading with players
      - No guild bank

    Everything else is allowed: grouping, dungeons, professions,
    talents, any gear quality, and death is not a failure.

    Commands:
      /sfr                  status
      /sfr log              violation log
      /sfr strict           toggle strict mode (auto-close vs warn only)
      /sfr pause            toggle enforcement (breaks are still logged)
      /sfr reset <message>  archive the current run and start over
      /sfr resets           history of previous runs
      /sfr show <n>         full detail of archived run #n
-------------------------------------------------------------------]]--

local ADDON = "SelfFoundRules"
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
}

local function InitDB()
    if type(SFR_Data) ~= "table" then SFR_Data = {} end
    for k, v in pairs(DEFAULTS) do
        if SFR_Data[k] == nil then
            SFR_Data[k] = (type(v) == "table") and {} or v
        end
    end
    if not SFR_Data.started then
        SFR_Data.started = { level = UnitLevel("player"), time = time() }
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
-- Enforcement
----------------------------------------------------------------------

local function Intercept(what, closeFunc)
    if SFR_Data.paused then return end
    SFR_Data.blocks = (SFR_Data.blocks or 0) + 1

    if SFR_Data.strict and type(closeFunc) == "function" then
        closeFunc()
        Warn(what .. " is closed. Self-found.")
    else
        Warn("Reminder: " .. what .. " breaks your self-found rules.")
    end
end

local function Violation(what)
    if SFR_Data.paused then what = what .. " (while paused)" end

    local when, lvl, zone = Stamp()
    table.insert(SFR_Data.violations, {
        time = when, level = lvl, zone = zone, what = what,
    })

    Warn("VIOLATION: " .. what .. "  —  logged at level " .. lvl .. ", " .. zone)
    Say("Total violations: " .. #SFR_Data.violations)
end

----------------------------------------------------------------------
-- Reset / archive
----------------------------------------------------------------------

local function ArchiveAndReset(message)
    local when, lvl, zone = Stamp()
    local s = SFR_Data.started or {}

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
    }

    table.insert(SFR_Data.resets, entry)

    -- wipe the live run
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
-- Event frame
----------------------------------------------------------------------

local f = CreateFrame("Frame", ADDON .. "Frame")

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:RegisterEvent("MAIL_SHOW")
f:RegisterEvent("TRADE_SHOW")
f:RegisterEvent("GUILDBANKFRAME_OPENED")
f:RegisterEvent("MAIL_SEND_SUCCESS")

f:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        InitDB()
        local v, r = #SFR_Data.violations, #SFR_Data.resets
        Say(("Active. Strict: %s. Violations: %d. Resets: %d."):format(
            SFR_Data.strict and "|cff81C784on|r" or "|cffFFB74Doff|r", v, r))
        if v > 0 then
            Say("|cffFF5252This run has a broken record.|r  /sfr log")
        end
        if SFR_Data.paused then
            Say("|cffFFB74DEnforcement is PAUSED.|r  /sfr pause to resume.")
        end

    elseif event == "AUCTION_HOUSE_SHOW" then
        Intercept("The Auction House", CloseAuctionHouse)
    elseif event == "MAIL_SHOW" then
        Intercept("Mail", CloseMail)
    elseif event == "TRADE_SHOW" then
        Intercept("Trading", CancelTrade)
    elseif event == "GUILDBANKFRAME_OPENED" then
        Intercept("The guild bank", CloseGuildBankFrame)
    elseif event == "MAIL_SEND_SUCCESS" then
        Violation("Sent mail")
    end
end)

----------------------------------------------------------------------
-- Action hooks (backstop)
----------------------------------------------------------------------

local function SafeHook(name, fn)
    if type(_G[name]) == "function" then hooksecurefunc(name, fn) end
end

SafeHook("TakeInboxItem",   function() Violation("Took an item from mail") end)
SafeHook("TakeInboxMoney",  function() Violation("Took gold from mail")    end)
SafeHook("AcceptTrade",     function() Violation("Accepted a trade")       end)
SafeHook("PlaceAuctionBid", function() Violation("Bid/bought on the AH")   end)
SafeHook("StartAuction",    function() Violation("Posted an auction")      end)
SafeHook("WithdrawGuildBankMoney", function() Violation("Withdrew guild bank gold") end)

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------

SLASH_SELFFOUNDRULES1 = "/sfr"
SLASH_SELFFOUNDRULES2 = "/selffound"

SlashCmdList["SELFFOUNDRULES"] = function(msg)
    InitDB()

    msg = strtrim(msg or "")
    -- split into first word + the rest, so "reset fresh start" works
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = strlower(cmd or "")

    if cmd == "log" then
        local n = #SFR_Data.violations
        if n == 0 then
            Say("|cff81C784Clean record.|r No violations this run.")
        else
            Say("Violation log (" .. n .. "):")
            for i, v in ipairs(SFR_Data.violations) do
                print(("  %d. %s — %s (lvl %d, %s)"):format(
                    i, v.time, v.what, v.level, v.zone))
            end
        end

    elseif cmd == "strict" then
        SFR_Data.strict = not SFR_Data.strict
        Say("Strict mode " .. (SFR_Data.strict
            and "|cff81C784ON|r — restricted windows close automatically."
            or  "|cffFFB74DOFF|r — you will only be warned."))

    elseif cmd == "pause" then
        SFR_Data.paused = not SFR_Data.paused
        Say(SFR_Data.paused
            and "|cffFFB74DEnforcement PAUSED.|r Anything you do now is still logged."
            or  "|cff81C784Enforcement resumed.|r")

    elseif cmd == "reset" then
        -- like `git commit`, refuse without a message
        if rest == "" then
            Say("|cffFF5252Reset needs a message.|r")
            print("  Usage:  /sfr reset <why you are resetting>")
            print("  Example: /sfr reset starting clean after the AH slip")
            return
        end
        ArchiveAndReset(rest)

    elseif cmd == "resets" or cmd == "history" then
        PrintResetHistory()

    elseif cmd == "show" then
        ShowReset(tonumber(rest))

    else
        local s = SFR_Data.started or {}
        Say("|cffFFFFFF" .. (UnitName("player") or "?") .. "|r — self-found")
        print("  Rules: no AH, no mail, no trading, no guild bank")
        print("  Allowed: grouping, dungeons, professions, talents, any gear")
        print(("  Run started: level %s"):format(tostring(s.level or "?")))
        print(("  Current:     level %d"):format(UnitLevel("player")))
        print(("  Strict mode: %s"):format(SFR_Data.strict and "on" or "off"))
        print(("  Times blocked: %d"):format(SFR_Data.blocks or 0))
        print(("  Resets: %d"):format(#SFR_Data.resets))
        if #SFR_Data.violations == 0 then
            print("  Status: |cff81C784CLEAN|r")
        else
            print(("  Status: |cffFF5252BROKEN|r (%d violations) — /sfr log"):format(
                #SFR_Data.violations))
        end
        print("  Commands: log | strict | pause | reset <msg> | resets | show <n>")
    end
end