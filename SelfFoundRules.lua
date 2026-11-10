--[[-------------------------------------------------------------------
    Self-Found Rules
    A personal self-found ruleset for Wow Classic / TBC Anniversary, with the intent to build WoW characters without outside help,
    but without the fatality of hardcore mode, similar to OSRS Ironman.

    Rules enforced:
      - No Auction House
      - No sending mail, and nothing taken from player-sent mail.
        NPC and system mail is allowed: Classic and TBC deliver quest
        rewards, profession items and reputation rewards that way.
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
      /sfr history          the level-by-level chronicle
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
    history     = {},     -- append-only: { kind, level, time, build, expansion, zone, played, rules, detail }
    schema      = 1,     -- data shape, separate from the addon's release version
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
    -- Written once. The honest statement of where the record beings:
    -- level before this were played but not observed
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
-- Mail
----------------------------------------------------------------------

-- The TakeInboxItem hook runs AFTER the take. Taking the last item
-- deletes the letter and renumbers everything below it, so asking the
-- API at hook time can describe a different letter. Snapshot while the
-- inbox is stable instead.
local mailSnapshot = {}

-- MAIL_INBOX_UPDATE fires on every take, delete and return, so warning
-- from there directly would spam chat. One warning per visit to the
-- mailbox reads better than a timed cooldown: the visit is the unit the
-- player actually experiences.
local mailWarned = false

-- canReply is a proxy, not a direct test: it means the client thinks
-- there is someone to reply to, which player mail has and quest mail
-- does not. Preferred over matching the sender's name because a name
-- shape only correlates with being a player, whereas this asks a
-- question close to the one we mean.
-- NOT VERIFIED IN-GAME YET -- all four mail paths below depend on it.
local function MailIsFromPlayer(index)
    local _, _, sender, _, _, _, _, _, _, _, _, canReply = GetInboxHeaderInfo(index)
    -- Using not not for simplifying to true and false, no nil
    return not not canReply, sender
end

local function SnapshotInbox()
    mailSnapshot = {}
    for i = 1, GetInboxNumItems() do
        local isPlayer, sender = MailIsFromPlayer(i)
        mailSnapshot[i] = { isPlayer = isPlayer, sender = sender }
    end
end

-- pairs rather than ipairs: SnapshotInbox fills 1..n with no gaps today,
-- but ipairs would silently stop at the first hole if that ever changes.
local function PlayerMailCount()
    local n = 0
    for i, m in pairs(mailSnapshot) do
        if m.isPlayer then n = n + 1 end
    end
    return n
end

-- Naming the senders makes the warning actionable: you can tell at a
-- glance whether it's an alt you forgot about or something unexpected.
local function PlayerMailSenders()
    local names = {}
    for _, m in pairs(mailSnapshot) do
        if m.isPlayer then table.insert(names, m.sender or "?") end
    end
    return table.concat(names, ", ")
end

----------------------------------------------------------------------
-- Enforcement
----------------------------------------------------------------------
local EXPANSION_BY_MAJOR = {
    ["1"] = "Classic", ["2"] = "TBC", ["3"] = "WotLK",
    ["4"] = "Cataclysm", ["5"] = "MoP",
}

-- Never asks the player what expansion it's on: the client knows.
-- Falls through to the raw version string rather than guessing, so a 
-- future flavor records something true instead of something wrong.
local function CurrentExpansion()
    local version = GetBuildInfo()
    local major = version:match("^(%d+)")
    return EXPANSION_BY_MAJOR[major] or ("Unknown " .. version), version
end

-- States the current rules that will be recorded in the log
local function CurrentRules()
    if SFR_Data.paused then return "paused" end
    return SFR_Data.strict and "strict" or "warn"
end

local function LogEvent(kind, level, detail)
    local expansion, build = CurrentExpansion()
    table.insert(SFR_Data.history, {
        kind        = kind,
        level       = level,
        time        = time(),   -- In Unix, not formatted
        build       = build,
        expansion   = expansion,
        zone        = GetRealZoneText() or "?",
        rules       = CurrentRules(),
        played      = nil,      -- filled in by TIME_PLAYED_MSG if it arrives
        detail      = detail,
    })
end

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
f:RegisterEvent("MAIL_INBOX_UPDATE")
f:RegisterEvent("MAIL_CLOSED")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("TIME_PLAYED_MSG")

f:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "PLAYER_LOGIN" then
        InitDB()
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
        -- The mailbox is allowed to open now: NPC mail carries quest rewards,
        -- profession deliveries and reputation items. Only player mail is a break.
        mailSnapshot, mailWarned = {}, false
    elseif event == "MAIL_INBOX_UPDATE" then
        SnapshotInbox()
        if not SFR_Data.paused and PlayerMailCount() > 0 and not mailWarned then
            mailWarned = true
            SFR_Data.blocks = (SFR_Data.blocks or 0) + 1
            Warn("Warning: Mailbox has player-sent mail from " .. PlayerMailSenders() .. ". Avoid opening.")
        end
    
    elseif event == "TRADE_SHOW" then
        Intercept("Trading", CancelTrade)
    elseif event == "GUILDBANKFRAME_OPENED" then
        Intercept("The guild bank", CloseGuildBankFrame)
    elseif event == "MAIL_SEND_SUCCESS" then
        Violation("Sent mail")
    elseif event == "MAIL_CLOSED" then
        mailSnapshot, mailWarned = {}, false
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
-- Action hooks (backstop)
----------------------------------------------------------------------

local function SafeHook(name, fn)
    if type(_G[name]) == "function" then hooksecurefunc(name, fn) end
end

-- These consult the snapshot rather than calling GetInboxHeaderInfo:
-- hooksecurefunc runs us after the take, by which point the letter may
-- be gone and the indices shifted.
--
-- Fails open. No snapshot entry means no violation, so a take after a
-- /reload at an open mailbox goes unlogged. Logging it as unknown
-- provenance would be more honest, but that needs Violation to record
-- an evidence class first.
SafeHook("TakeInboxItem",   function(index)
    local m = mailSnapshot[index]
    if m and m.isPlayer then
        Violation("Took an item from player-sent mail (" .. (m.sender or "?") .. ")")
    end
end)
SafeHook("TakeInboxMoney",  function(index) 
    local m = mailSnapshot[index]
    if m and m.isPlayer then
        Violation("Took gold from player-sent mail (" .. (m.sender or "?") .. ")")
    end
end)
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
            -- Mail is deliberately outside this toggle: the mailbox always
            -- opens, because closing it would lock out NPC mail too.
            and "|cff81C784ON|r — the AH, trade and guild bank windows close automatically."
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

    elseif cmd == "resets" then
        PrintResetHistory()
    elseif cmd == "history" then
        PrintHistory()

    elseif cmd == "show" then
        ShowReset(tonumber(rest))

    else
        local s = SFR_Data.started or {}
        Say("|cffFFFFFF" .. (UnitName("player") or "?") .. "|r — self-found")
        print("  Rules: no AH, no player-sent mail, no trading, no guild bank")
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
        print("  Commands: log | history | strict | pause | reset <msg> | resets | show <n>")
    end
end