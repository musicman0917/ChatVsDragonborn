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
PapyrusCompiler.exe Scripts\Source\ChaosSpawnManager.psc  -i="Scripts\Source;<SkyrimInstall>\Data\Source\Scripts" -o="Scripts" -flags="<SkyrimInstall>\Data\Source\Scripts\TESV_Papyrus_Flags.flg"
PapyrusCompiler.exe Scripts\Source\SkyrimChaosRouter.psc  -i="Scripts\Source;<SkyrimInstall>\Data\Source\Scripts" -o="Scripts" -flags="<SkyrimInstall>\Data\Source\Scripts\TESV_Papyrus_Flags.flg"
```

## Wiring up in the Creation Kit

1. Create a new Quest (e.g. `STE_ChaosRouterQuest`), start-game-enabled, no
   quest stages needed.
2. Attach `SkyrimChaosRouter.psc` to it; fill in the `ChaosSpawnZone`
   (optional — safe to leave unset), `Gold001`, and `SpawnManager`
   properties (the last one points at the `ChaosSpawnManager` instance from
   step 3 — its spawn functions are instance methods, so the router needs a
   live reference to call them through; the player reference itself comes
   from `Game.GetPlayer()` in-script, no property needed).
3. Attach `ChaosSpawnManager.psc` to the same quest (a Form can have more
   than one script attached — this lets `SpawnManager` above just point at
   "this quest"); fill in `ChaosDragonLeveledActor` (a `LeveledActor`, e.g. a
   dragon leveled list) and `ChaosChickenBase` (an `ActorBase` NPC_ record,
   e.g. the vanilla "Chicken" template).
4. Build a plugin (`.esp`/`.esl`) containing the quest and save it alongside
   this `Data/` tree.
