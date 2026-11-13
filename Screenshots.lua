local SHOT_DELAY = 2 -- 2 seconds delay
-- Import
local ADDON, SFR = ...
-- We want the level-up banner on screen so fire two seconds after the event.
local function After(secs, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(secs, fn)
    else
        fn()    -- no timer; take it immediately rather than not at all
    end
end

local pending = nil -- entry awaiting an outcome

local shots = CreateFrame("Frame", ADDON .. "ShotFrame")
shots:RegisterEvent("SCREENSHOT_SUCCEEDED")
shots:RegisterEvent("SCREENSHOT_FAILED")
shots:SetScript("OnEvent", function(self, event)
    if not pending then return end   -- a manual PrintScreen; not ours to claim
    pending.screenshot.status = (event == "SCREENSHOT_SUCCEEDED") and "succeeded" or "failed"
    pending = nil
end)

local function RequestScreenshot(entry, trigger)
    if not SFR_Data.screenshots then return end
    if pending then return end
    entry.screenshot = { trigger = trigger, status = "pending", time = time(), }
    After(SHOT_DELAY, function()
        pending = entry
        Screenshot()
    end)
    After(SHOT_DELAY + 5, function()
        if pending == entry then
            entry.screenshot.status = "unknown"
            pending = nil
        end
    end)
end

----------------------------------------------------------------------
-- Exports
----------------------------------------------------------------------
SFR.RequestScreenshot = RequestScreenshot

