# Changelog

All notable changes to ChatVsDragonborn, grouped by feature area rather than
by date/version — this project doesn't yet tag releases. See commit history
for the exact sequence.

## Core chaos command system

- SKSE64 plugin + Papyrus router (`SkyrimChaosRouter.psc`) + TwitchBridge C#
  app scaffolded, connected over a named-pipe JSON protocol.
- `!buy ragdoll`, `!buy earthquake`, `!buy dragon` (spawns a hostile dragon a
  safe distance ahead of the player, not point-blank), `!buy chickens`.
- `!buy cheese` — originally a single hardcoded item, now picks randomly
  from 4 configurable cheese wheels per cast.
- `!buy addgold` / `!buy removegold` — amounts now configurable in-game via
  the MCM menu instead of hardcoded.
- Command results (success/failure) are reported back to chat instead of
  only ever confirming "queued".

## Points economy

Ported from the WaterparkSimTwitchExpansion design:

- Role-based starting balances — 250 for everyone, +500 one-time bonus for
  confirmed followers, 1000 for VIPs/mods/broadcaster.
- Passive income: 10 points/min for viewers active in chat (pauses if they
  go quiet).
- New sub/resub (500–1500 by tier), gifted subs (paid to the gifter, once
  per recipient even in a mass gift), and bits (1 point/bit, straight
  conversion).
- Mod/broadcaster-only `!give @username <amount>` command.

## Moderator auth

- Twitch moderator OAuth token now auto-refreshes instead of needing manual
  regeneration every ~60 days — implemented directly against Twitch's OAuth
  endpoint rather than through TwitchLib.Api's own refresh helper, which has
  a known bug (`ExpiresIn` always reports 0).

## In-game MCM menu

- Full Mod Configuration Menu (via MCM Helper) for live-editable chaos
  command prices, gold amounts, and effect durations — no restart needed,
  changes sync to the SKSE plugin and TwitchBridge immediately.
- Required a SkyUI 6.x → 5.2 SE downgrade for genuine MCM Helper
  compatibility, plus fixes for a duplicated quest form, missing/mismatched
  MCM Helper dependency files, and a missing `settings.ini` (MCM Helper
  reads control defaults from there, not from `config.json`'s
  `defaultValue`, which only sizes the slider widget).

## GitHub Pages commands site

- Skyrim word-wall themed page at musicman0917.github.io/ChatVsDragonborn
  listing every chaos command, its price, and how the points economy works.
- Manually kept in sync with the mod's command list — nothing generates it
  automatically.

## Item, gold, and scroll grants (27 commands)

- 3 fixed gold-amount grants: `!buy give10gold` / `give100gold` /
  `give1000gold`.
- 11 misc item grants: apples, arrows, baked potatoes, diamond, dragon
  bone/scales, gold/iron/silver ingot, potatoes, a common soul gem.
- 12 scroll grants, one per vanilla scroll (Blizzard, the three Conjure
  Atronach scrolls, the three Thrall scrolls, Harmony, Hysteria,
  Invisibility, Mayhem, Water Breathing).
- `!buy cheesemageddon` — a bigger, pricier `!buy cheese` (60–100 wheels
  instead of 15–40). Originally named "cheese-splosion"; renamed to avoid
  colliding with an existing trademarked "-splosion" name.

## `!buy yeet`

- Comedically launches a random nearby NPC into a brief, non-lethal
  ragdoll stumble. Picks a live, visible, non-player target via the
  engine's own actor search (retrying on misses), then clears the
  target's combat/alarm state so the shove never turns into a fight or a
  bounty.

## Physics & Magic (8 commands)

- `!buy superjump` — temporarily boosts `fJumpHeightMin`, then restores
  whatever value it actually found.
- `!buy ragdollblast` — the `!buy yeet` idea applied to up to 5 nearby
  NPCs at once, with a gentler push.
- `!buy tinydovahkiin` / `!buy giantdovahkiin` — timed player scale change
  (0.25x / 3.0x), auto-reverts.
- `!buy drunkvision` — casts a configurable drunk-style visual effect on
  the player.
- `!buy wildmagic` — casts a random one of three configurable high-cost
  spells at a random nearby NPC.
- `!buy midasweight` — swaps the player's entire gold count 1-for-1 into a
  configurable heavy MiscObject (e.g. Iron Ore).
- `!buy pocketchangeblast` — drops the player's entire gold count on the
  ground as a physics object.

## Known limitations

- `!buy invert` and `!buy lowgravity` are tagged Beta on the commands page:
  Papyrus writes a marker setting when they fire, but nothing on the native
  side currently consumes it to actually apply the effect.
- `!buy drunkvision`, `!buy wildmagic`, and `!buy midasweight` need CK
  properties (`ChaosDrunkSpell`, `ChaosWildSpell1`-`3`, `ChaosMidasOre`)
  manually assigned before they'll work — everything else in this file
  works out of the box once compiled and deployed.
