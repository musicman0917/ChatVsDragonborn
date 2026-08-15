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

```powershell
PapyrusCompiler.exe Scripts\Source\STE_Native.psc         -i="Scripts\Source;<SkyrimInstall>\Data\Source\Scripts" -o="Scripts" -flags="<SkyrimInstall>\Data\Source\Scripts\TESV_Papyrus_Flags.flg"
PapyrusCompiler.exe Scripts\Source\SkyrimChaosRouter.psc  -i="Scripts\Source;<SkyrimInstall>\Data\Source\Scripts" -o="Scripts" -flags="<SkyrimInstall>\Data\Source\Scripts\TESV_Papyrus_Flags.flg"
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
   and `ChaosChickenBase` (an `ActorBase` NPC_ record, e.g. the vanilla
   `EncChicken`). Both actor properties are deliberately concrete
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
