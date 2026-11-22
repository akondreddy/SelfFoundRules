--[[-------------------------------------------------------------------
    Rules.lua

    Enforcement: the windows that get closed, the violations that get
    logged, and the hooks that act as a backstop.

    Must load before Mail.lua, because the mail hooks call Violation.
-------------------------------------------------------------------]]--

local TIMEOUT = 2
local pending = nil -- Intercept awaiting an outcome
local ADDON, SFR = ...

local Say, Warn, Stamp, After = SFR.Say, SFR.Warn, SFR.Stamp, SFR.After

----------------------------------------------------------------------
-- Enforcement
----------------------------------------------------------------------

-- If window is closed by hand within 2 seconds, CLOSED fires and gets counted as a successful block.
-- Addon won't know who closed it, not worth fixing
local function Intercept(what, closeFunc, eventName)
    if SFR_Data.paused then return end
    SFR_Data.blocks = (SFR_Data.blocks or 0) + 1
    
    if SFR_Data.strict and type(closeFunc) == "function" then
        local p = { what = what, eventName = eventName }
        pending = p
        closeFunc()
        Warn("Closing " .. what)

        After(TIMEOUT, function()
            if pending == p then
                SFR_Data.blocksFailed = (SFR_Data.blocksFailed or 0) + 1
                Warn(what .. " is still open")
                pending = nil
            end
        end) 
    else 
        SFR_Data.blocksWarned = (SFR_Data.blocksWarned or 0) + 1
        Warn("Reminder: " .. what .. " breaks your self-found rules.")
    end
end

local function Resolve(eventName)
    if pending == nil then return end
    if pending.eventName ~= eventName then return end
    SFR_Data.blocksClosed = (SFR_Data.blocksClosed or 0) + 1
    pending = nil
end

local function Violation(what, evidence)
    if SFR_Data.paused then what = what .. " (while paused)" end

    local when, lvl, zone = Stamp()
    table.insert(SFR_Data.violations, {
        time = when, level = lvl, zone = zone, what = what, evidence = evidence,
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
rules:RegisterEvent("AUCTION_HOUSE_CLOSED")
rules:RegisterEvent("TRADE_CLOSED")
rules:RegisterEvent("GUILDBANKFRAME_CLOSED")
rules:RegisterEvent("MAIL_SEND_SUCCESS")

-- MAIL_SEND_SUCCESS lives here rather than in Mail.lua on purpose.
-- Mail.lua is about reading the inbox; sending is a flat violation and
-- needs none of that state. If you disagree, moving it is harmless --
-- but notice that it would be the only thing in Mail.lua that does not
-- touch the snapshot.

rules:SetScript("OnEvent", function(self, event)
    if event == "AUCTION_HOUSE_SHOW" then
        Intercept("The Auction House", CloseAuctionHouse, "AUCTION_HOUSE_CLOSED")
    elseif event == "TRADE_SHOW" then
        Intercept("Trading", CancelTrade, "TRADE_CLOSED")
    elseif event == "GUILDBANKFRAME_OPENED" then
        Intercept("The guild bank", CloseGuildBankFrame, "GUILDBANKFRAME_CLOSED")
    elseif event == "MAIL_SEND_SUCCESS" then
        Violation("Sent mail", "observed")
    elseif event == "AUCTION_HOUSE_CLOSED" then
        Resolve("AUCTION_HOUSE_CLOSED")
    elseif event == "TRADE_CLOSED" then
        Resolve("TRADE_CLOSED")
    elseif event == "GUILDBANKFRAME_CLOSED" then
        Resolve("GUILDBANKFRAME_CLOSED")
    end
end)

----------------------------------------------------------------------
-- Action hooks (backstop)
----------------------------------------------------------------------
--
-- The two TakeInbox* hooks stay behind for Mail.lua: they read the
-- snapshot, so they belong with it.
SafeHook("AcceptTrade",     function() Violation("Accepted a trade", "attempted")       end)
SafeHook("PlaceAuctionBid", function() Violation("Bid/bought on the AH", "attempted")   end)
SafeHook("StartAuction",    function() Violation("Posted an auction", "attempted")      end)
SafeHook("WithdrawGuildBankMoney", function() Violation("Withdrew guild bank gold", "attempted") end)

----------------------------------------------------------------------
-- Exports
----------------------------------------------------------------------

SFR.Violation = Violation
SFR.Intercept = Intercept
SFR.SafeHook  = SafeHook
