--[[-------------------------------------------------------------------
    Rules.lua

    Enforcement: the windows that get closed, the violations that get
    logged, and the hooks that act as a backstop.

    Must load before Mail.lua, because the mail hooks call Violation.
-------------------------------------------------------------------]]--

local ADDON, SFR = ...

local Say, Warn, Stamp = SFR.Say, SFR.Warn, SFR.Stamp

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
-- Hook helper
----------------------------------------------------------------------

local function SafeHook(name, fn)
    if type(_G[name]) == "function" then hooksecurefunc(name, fn) end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

local rules = CreateFrame("Frame", ADDON .. "RulesFrame")

rules:RegisterEvent("AUCTION_HOUSE_SHOW")
rules:RegisterEvent("TRADE_SHOW")
rules:RegisterEvent("GUILDBANKFRAME_OPENED")
rules:RegisterEvent("MAIL_SEND_SUCCESS")

-- MAIL_SEND_SUCCESS lives here rather than in Mail.lua on purpose.
-- Mail.lua is about reading the inbox; sending is a flat violation and
-- needs none of that state. If you disagree, moving it is harmless --
-- but notice that it would be the only thing in Mail.lua that does not
-- touch the snapshot.

rules:SetScript("OnEvent", function(self, event)
    -- MOVE: the AUCTION_HOUSE_SHOW, TRADE_SHOW, GUILDBANKFRAME_OPENED
    --       and MAIL_SEND_SUCCESS branches,
    --       from SelfFoundRules.lua:392-393, 406-411
    --
    -- Leave the MAIL_SHOW / MAIL_INBOX_UPDATE / MAIL_CLOSED branches
    -- behind: those go to Mail.lua.

    if event == "AUCTION_HOUSE_SHOW" then
        Intercept("The Auction House", CloseAuctionHouse)
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

-- MOVE: the four non-mail hooks,
--       from SelfFoundRules.lua:455-458
--       (AcceptTrade, PlaceAuctionBid, StartAuction,
--        WithdrawGuildBankMoney)
--
-- The two TakeInbox* hooks stay behind for Mail.lua: they read the
-- snapshot, so they belong with it.
SafeHook("AcceptTrade",     function() Violation("Accepted a trade")       end)
SafeHook("PlaceAuctionBid", function() Violation("Bid/bought on the AH")   end)
SafeHook("StartAuction",    function() Violation("Posted an auction")      end)
SafeHook("WithdrawGuildBankMoney", function() Violation("Withdrew guild bank gold") end)

----------------------------------------------------------------------
-- Exports
----------------------------------------------------------------------

SFR.Violation = Violation
SFR.Intercept = Intercept
SFR.SafeHook  = SafeHook
