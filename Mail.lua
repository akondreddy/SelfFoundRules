--[[-------------------------------------------------------------------
    Mail.lua

    The mailbox is the one restricted window that is allowed to open:
    Classic and TBC deliver quest rewards, profession items and
    reputation rewards as NPC mail, so closing it outright would lock
    those out. Only player-sent mail is a break.

    This file exports NOTHING. Every piece of mail state and every
    piece of mail logic is unreachable from the rest of the addon,
    which means mail can only ever be broken by mail code. That is the
    main reason the split was worth doing -- do not add an export here
    without a concrete reason.

    Loads after Rules.lua, because the hooks below call Violation.
-------------------------------------------------------------------]]--

local ADDON, SFR = ...

local Warn          = SFR.Warn
local Violation     = SFR.Violation
local SafeHook      = SFR.SafeHook

----------------------------------------------------------------------
-- State
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

----------------------------------------------------------------------
-- Reading the inbox
----------------------------------------------------------------------

-- canReply is a proxy, not a direct test: it means the client thinks
-- there is someone to reply to, which player mail has and quest mail
-- does not. Preferred over matching the sender's name because a name
-- shape only correlates with being a player, whereas this asks a
-- question close to the one we mean.
-- VERIFIED IN-GAME -- all four mail paths below depend on it.
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
-- Events
----------------------------------------------------------------------

local mail = CreateFrame("Frame", ADDON .. "MailFrame")

mail:RegisterEvent("MAIL_SHOW")
mail:RegisterEvent("MAIL_INBOX_UPDATE")
mail:RegisterEvent("MAIL_CLOSED")

mail:SetScript("OnEvent", function(self, event)
    if event == "MAIL_SHOW" then
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
    elseif event == "MAIL_CLOSED" then
        mailSnapshot, mailWarned = {}, false
    end
end)

----------------------------------------------------------------------
-- Inbox hooks (backstop)
----------------------------------------------------------------------

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

----------------------------------------------------------------------
-- Exports
----------------------------------------------------------------------

-- Deliberately none.
