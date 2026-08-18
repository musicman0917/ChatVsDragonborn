# Data/ — mod payload

This tree mirrors what ships inside a Skyrim `Data\` folder. `installer/install.ps1`
copies it (plus the built plugin DLL) into your target install/MO2 profile.

## External mod dependencies

- **SKSE** (Skyrim Script Extender) — required; hosts `SkyrimTwitchExpansion.dll`.
- **Address Library for SKSE Plugins** — required; the plugin is built with
  `UsesAddressLibrary(true)` so it never hardcodes per-runtime-version offsets.
- **MCM Helper** (or SkyUI's MCM, if targeting pre-AE) — renders
  `MCM/Config/SkyrimTwitchExpansion/config.json` as the in-game settings menu.

No third-party Papyrus script library (e.g. PapyrusUtil) is required — any
value the SKSE plugin needs to hand Papyrus (a command's numeric args, a
setting) comes through a typed native function
(`STE_Native.GetCommandArgInt`, `STE_Native.GetSettingInt`) instead of a raw
JSON string Papyrus would otherwise need a JSON library to parse.

## Compiling the Papyrus scripts

Requires the (free) Skyrim Special Edition Creation Kit — install it via Steam
(Library → Tools → "Skyrim Special Edition: Creation Kit"). It installs
`PapyrusCompiler.exe` at `<SkyrimInstall>\Papyrus Compiler\PapyrusCompiler.exe`
and the vanilla base-game script sources at `<SkyrimInstall>\Data\Source\Scripts`
(note the order — `Source\Scripts`, not `Scripts\Source`; that's Bethesda's own
install layout and differs from the `Scripts/Source/` convention this repo uses
for its own scripts). The compiler needs both directories on its import path to
resolve base-game types like `Quest` and `Actor`.

The vanilla scripts ship inside `<SkyrimInstall>\Data\Scripts.zip` — extract it
directly into `<SkyrimInstall>\Data\` (not into `Data\Source\Scripts\`; the zip
already contains that path internally, so extracting it a second folder deeper
just nests it). You'll also need
`<SkyrimInstall>\Data\Source\Scripts\TESV_Papyrus_Flags.flg` on the compiler's
`-flags` argument explicitly — it isn't auto-discovered from the `-i` import
list, and omitting it produces a flood of spurious "Unknown user flag Hidden"
warnings that cascade into false "is not a function" errors on real functions.

Compiled `.pex` files are intentionally not committed (see `.gitignore`) —
build them locally or as part of a release pipeline.

`STE_MCMConfig.psc` extends MCM Helper's own `MCM_ConfigBase`, so its script
source (wherever MCM Helper's own mod files are installed — typically
alongside its own `Scripts\Source\` under your Skyrim `Data\`) needs to be on
the `-i` import list too, alongside the two paths below.

```powershell
PapyrusCompiler.exe Scripts\Source\STE_Native.psc         -i="Scripts\Source;<SkyrimInstall>\Data\Source\Scripts;<MCM Helper's Scripts\Source>" -o="Scripts" -flags="<SkyrimInstall>\Data\Source\Scripts\TESV_Papyrus_Flags.flg"
PapyrusCompiler.exe Scripts\Source\SkyrimChaosRouter.psc  -i="Scripts\Source;<SkyrimInstall>\Data\Source\Scripts;<MCM Helper's Scripts\Source>" -o="Scripts" -flags="<SkyrimInstall>\Data\Source\Scripts\TESV_Papyrus_Flags.flg"
PapyrusCompiler.exe Scripts\Source\STE_MCMConfig.psc      -i="Scripts\Source;<SkyrimInstall>\Data\Source\Scripts;<MCM Helper's Scripts\Source>" -o="Scripts" -flags="<SkyrimInstall>\Data\Source\Scripts\TESV_Papyrus_Flags.flg"
```

The compiled `.pex` files also need to be copied into
`<SkyrimInstall>\Data\Scripts\` (not just this repo's own `Data\Scripts\`) —
that's the folder the Creation Kit and the game itself actually read from.
Recopy after every recompile:

```powershell
Copy-Item "Scripts\*.pex" "<SkyrimInstall>\Data\Scripts\" -Force
```

## Wiring up in the Creation Kit

1. Create a new Quest (e.g. `STE_ChaosRouterQuest`), start-game-enabled, no
   quest stages needed. **Save the plugin (File → Save As) right after
   creating it, before attaching scripts or setting properties** — the CK is
   prone to crashing, and nothing you do is persisted until you explicitly
   save.
2. Attach `SkyrimChaosRouter.psc` to it. Save again.
3. Reopen the quest, fill in its properties: `ChaosSpawnZone` (optional —
   safe to leave unset), `Gold001`, `ChaosDragonActorBase` (an `ActorBase`
   NPC_ record for a hostile dragon, e.g. the vanilla `EncDragon01Fire`),
   `ChaosChickenBase` (an `ActorBase` NPC_ record, e.g. the vanilla
   `EncChicken`), and `ChaosCheeseItem1`-`ChaosCheeseItem4` (four separate
   `Potion` properties — e.g. the vanilla `FoodCheeseWheel01A`,
   `FoodCheeseWheel01B`, `FoodCheeseWheel02A`, `FoodCheeseWheel02B`;
   `ExecuteSpawnCheese()` picks one at random per `!buy cheese`). These are
   typed `Potion`, not the generic `Form` — `Potion` is the real Papyrus
   script type for ALCH records (Skyrim shares one script type across
   potions, poisons, and food), and the CK's "Pick Object" picker cannot
   build a working search/browse list for the fully generic `Form` type
   (confirmed live: it showed only two unrelated system forms regardless
   of Object Window selection, for both a scalar `Form` property and an
   earlier `Form[]` array attempt). `Potion` is specific enough for the
   picker — and drag-and-drop/Auto-Fill from the Object Window — to work
   normally, and still passes into `PlaceAtMe()` fine since `Potion` is
   itself a `Form`. The same reasoning applies to the item/scroll grant
   properties below — each is typed to the specific Papyrus type matching
   its record so the picker actually works: `Ammo` for ammunition records,
   `MiscObject` for MISC records, `SoulGem` for SLGM records, `Scroll` for
   SCRL records, and `Potion` again for ALCH-backed food items. Fill in:
   `ChaosGiveApples` (a food `Potion`, e.g. `Apple`), `ChaosGiveArrows` (an
   `Ammo`, e.g. `IronArrow` — 20 are granted per `!buy givearrows`),
   `ChaosGiveBakedPotatoes` (a food `Potion`, e.g. `FoodBakedPotato`),
   `ChaosGiveDiamond`/`ChaosGiveGoldIngot`/`ChaosGiveIronIngot`/
   `ChaosGiveSilverIngot`/`ChaosGiveDragonBone`/`ChaosGiveDragonScales` (all
   `MiscObject`, e.g. the vanilla `Diamond001`, `GoldIngot01`, `IronIngot01`,
   `SilverIngot01`, `DragonBone`, `DragonScales`), `ChaosGivePotatoes` (a
   food `Potion`, e.g. `FoodRawPotato` — 5 are granted per
   `!buy givepotatoes`), `ChaosGiveSoulGemCommon` (a `SoulGem`, e.g. the
   vanilla `SoulGemCommon`), and the 12 `ChaosScroll*` properties (all
   `Scroll`, one per scroll command — e.g. `ChaosScrollBlizzard` →
   `ScrollBlizzard`, `ChaosScrollConjureFlameAtronach` →
   `ScrollConjureFlameAtronach`, `ChaosScrollConjureFrostAtronach` →
   `ScrollConjureFrostAtronach`, `ChaosScrollConjureStormAtronach` →
   `ScrollConjureStormAtronach`, `ChaosScrollFlameThrall` →
   `ScrollFlameThrall`, `ChaosScrollFrostThrall` → `ScrollFrostThrall`,
   `ChaosScrollHarmony` → `ScrollHarmony`, `ChaosScrollHysteria` →
   `ScrollHysteria`, `ChaosScrollInvisibility` → `ScrollInvisibility`,
   `ChaosScrollMayhem` → `ScrollMayhem`, `ChaosScrollStormThrall` →
   `ScrollStormThrall`, `ChaosScrollWaterBreathing` →
   `ScrollWaterBreathing`, all vanilla `SCRL` editor IDs). `!buy
   cheesemageddon` reuses `ChaosCheeseItem1`-`4` (already set above) and
   needs no separate property. `!buy yeet` also needs no property — it
   picks its target live via `Game.FindRandomActor()` within 1500 units of
   the player (retrying up to 10 times against ones that are dead, the
   player themself, or lack line of sight), then `PushActorAway()`s them
   with a mild 8-12 force and clears their combat/alarm state so the shove
   doesn't turn into a fight or a bounty. `!buy ragdollblast` is the same
   idea applied to up to 5 nearby NPCs at once and also needs no property.
   `!buy superjump`, `!buy tinydovahkiin`, and `!buy giantdovahkiin` need no
   properties either — they read/restore the real `fJumpHeightMin` game
   setting or the actor's own scale directly, with no Form involved.

   Three more properties round out the "Physics & Magic" batch: `ChaosDrunkSpell`
   (a `Spell` — any spell that applies a drunk-style visual distort/wobble to
   the player for `!buy drunkvision`, e.g. the vanilla Skooma "high" effect
   or a custom spell built around an ImageSpace Modifier; its own magic
   effect duration governs how long the effect lasts, so there's no separate
   duration setting for this one), `ChaosWildSpell1`-`3` (three `Spell`
   properties for `!buy wildmagic` — high-cost offensive spells, e.g. the
   vanilla Fireball, Chain Lightning, and Ice Storm; one is picked at random
   and cast at a random nearby actor), and `ChaosMidasOre` (a `MiscObject`
   for `!buy midasweight` — e.g. the vanilla Iron Ore, swapped in 1-for-1 for
   the Dragonborn's gold count). `!buy pocketchangeblast` reuses `Gold001`
   (already set above) and needs no separate property.

   Both actor properties are deliberately concrete
   `ActorBase` templates rather than `LeveledActor` lists — `LeveledActor`
   forms are both harder to place via `PlaceActorAtMe` (which needs a
   concrete `ActorBase`, not a leveled list — `PlaceAtMe` handles leveled
   lists but doesn't accept an `EncounterZone`) and, in practice, much
   harder to locate and assign through the CK's object pickers. The player
   reference itself comes from `Game.GetPlayer()` in-script, no property
   needed. Save again.

   All the spawn logic lives directly on `SkyrimChaosRouter.psc` rather than
   a separate script — the CK's property picker has no way to point a
   script-type Property at a bare Quest form (even the same quest doing the
   pointing), so a second script needing a live reference back to this one
   had no way to be wired up through the GUI.
4. Build a plugin (`.esp`/`.esl`) containing the quest and save it alongside
   this `Data/` tree.
5. On that same quest's Scripts tab, attach `STE_MCMConfig.psc` as a second
   script (a Quest form can carry more than one). It has no properties to
   fill in — it only implements `OnSettingChange` to mirror MCM Helper's own
   slider values into this mod's settings store (see the script's own header
   comment and `Data/MCM/Config/SkyrimTwitchExpansion/config.json` for the
   menu itself). Save. The "ChatVsDragonborn" menu should now appear under
   Mod Configuration in-game, with live-editable chaos-command prices, the
   gold amounts granted/stolen by `!buy addgold`/`!buy removegold`, and
   effect durations.
