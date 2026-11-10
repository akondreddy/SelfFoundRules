# Self-Found Rules

A personal self-found ruleset for World of Warcraft Classic and TBC.

No permadeath. No gear restrictions. No talent restrictions.
Just the one thing: everything you have, you found yourself.

## Rules

**Blocked:**
- Auction House
- Sending mail, and taking anything out of player-sent mail
- Trading with other players
- Guild bank

**Allowed:**
- NPC and system mail — quest rewards, profession deliveries,
  reputation rewards and Blizzard restorations all arrive this way
- Grouping and dungeons
- Professions
- Talents
- Any gear quality
- Dying

This mirrors the Old School RuneScape Ironman model: you can
play *with* people, you just can't take anything from them.

## Why

WoW has no self-found mode outside Hardcore realms, where it comes
bundled with permadeath. This separates the two.

## Installation

1. Download the latest release
2. Extract into the AddOns folder of whichever client you play. Each
   one has its own, and the addon has to be installed in each
   separately:
   ```
   World of Warcraft/_classic_era_/Interface/AddOns/    # Classic Era
   World of Warcraft/_anniversary_/Interface/AddOns/    # TBC Anniversary
   World of Warcraft/_forever_/Interface/AddOns/        # Warcraft Forever
   ```
3. The folder structure should look like:
   ```
   AddOns/SelfFoundRules/SelfFoundRules.toc
   AddOns/SelfFoundRules/SelfFoundRules.lua
   ```
4. Restart WoW or `/reload`

## Commands

| Command | Does |
|---|---|
| `/sfr` | Status — level started, blocks, violations, resets |
| `/sfr log` | Violation log for the current run |
| `/sfr strict` | Toggle auto-close vs warn-only |
| `/sfr pause` | Suspend enforcement (actions still logged) |
| `/sfr reset <message>` | Archive the run and start over. Message required |
| `/sfr resets` | History of archived runs |
| `/sfr history` | The chronicle - every level, with rules in force at the time | 
| `/sfr show <n>` | Full detail of archived run #n |

## How enforcement works

**Strict mode (default):** the Auction House, trade and guild bank
windows close the instant they open, with a warning and a sound.

**Mail is handled differently.** The mailbox always opens, whatever the
mode, because Classic and TBC use NPC mail for quest rewards,
profession deliveries and reputation rewards — closing it outright
would lock those out. Instead, the addon warns when player-sent mail is
sitting in the inbox, and logs a violation only if you take an item or
gold out of it. NPC mail is untouched.

**Backstop:** hooks on `TakeInboxItem`, `TakeInboxMoney`, `AcceptTrade`,
`PlaceAuctionBid`, `StartAuction`, and guild bank withdrawals log an
actual violation if something slips through.

**Limitation:** this is a client-side addon. It cannot stop the server
from processing an action, and disabling the addon removes all of it.
It is designed to prevent accidents and make deliberate breaks visible
and permanent — not to be unbreakable.

## Resets

Resets work like git commits. Each one requires a message and archives
a full snapshot of the run being ended: start level, end level, block
count, and the complete violation log.

```
/sfr reset fresh start after the Deadmines group handed me a drop
```

## Data

Stored per character in `SFR_Data` via `SavedVariablesPerCharacter`.
Your other characters are unaffected.

## License

MIT