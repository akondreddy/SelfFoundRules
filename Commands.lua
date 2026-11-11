--[[-------------------------------------------------------------------
    Commands.lua

    The slash command handler and everything the player reads.

    Loads last: this file calls into every other one, and nothing calls
    into it. It exports nothing, for the same reason -- it is the top of
    the dependency graph.

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

local ADDON, SFR = ...

local Say, InitDB         = SFR.Say, SFR.InitDB
local PrintHistory        = SFR.PrintHistory
local ArchiveAndReset     = SFR.ArchiveAndReset
local PrintResetHistory   = SFR.PrintResetHistory
local ShowReset           = SFR.ShowReset

----------------------------------------------------------------------
-- Login greeting
----------------------------------------------------------------------

local greet = CreateFrame("Frame", ADDON .. "GreetFrame")
greet:RegisterEvent("PLAYER_LOGIN")
greet:SetScript("OnEvent", function(self, event)
    local v, r = #SFR_Data.violations, #SFR_Data.resets
        Say(("Active. Strict: %s. Violations: %d. Resets: %d."):format(
            SFR_Data.strict and "|cff81C784on|r" or "|cffFFB74Doff|r", v, r))
        if v > 0 then
            Say("|cffFF5252This run has a broken record.|r  /sfr log")
        end
        if SFR_Data.paused then
            Say("|cffFFB74DEnforcement is PAUSED.|r  /sfr pause to resume.")
        end
end)

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

----------------------------------------------------------------------
-- Exports
----------------------------------------------------------------------

-- None. Nothing in the addon should be calling into the command layer.
