# Data/ — mod payload

This tree mirrors what ships inside a Skyrim `Data\` folder. `installer/install.ps1`
copies it (plus the built plugin DLL) into your target install/MO2 profile.

## External mod dependencies

- **SKSE** (Skyrim Script Extender) — required; hosts `SkyrimTwitchExpansion.dll`.
- **Address Library for SKSE Plugins** — required; the plugin is built with
  `UsesAddressLibrary(true)` so it never hardcodes per-runtime-version offsets.
- **PapyrusUtil** — provides `JsonUtil`, used by `SkyrimChaosRouter.psc` to read
  effect-specific args out of the JSON payload the SKSE plugin hands it.
- **MCM Helper** (or SkyUI's MCM, if targeting pre-AE) — renders
  `MCM/Config/SkyrimTwitchExpansion/config.json` as the in-game settings menu.

## Compiling the Papyrus scripts

Requires the (free) Skyrim Special Edition Creation Kit — install it via Steam
(Library → Tools → "Skyrim Special Edition: Creation Kit"). It installs
`PapyrusCompiler.exe` at `<SkyrimInstall>\Papyrus Compiler\PapyrusCompiler.exe`
and the vanilla base-game script sources at `<SkyrimInstall>\Data\Source\Scripts`
(note the order — `Source\Scripts`, not `Scripts\Source`; that's Bethesda's own
install layout and differs from the `Scripts/Source/` convention this repo uses
for its own scripts). The compiler needs both directories on its import path to
resolve base-game types like `Quest` and `Actor`.

Compiled `.pex` files are intentionally not committed (see `.gitignore`) —
build them locally or as part of a release pipeline.

`SkyrimChaosRouter.psc` also calls `JsonUtil` (from the PapyrusUtil dependency
listed above). The compiler resolves that from PapyrusUtil's compiled
`JsonUtil.pex` — no source needed — as long as PapyrusUtil is installed into
this same `Data\` tree first, so `Data\Scripts` (containing its `.pex`) is on
the import path too:

```powershell
PapyrusCompiler.exe Scripts\Source\SkyrimChaosRouter.psc -i="Scripts\Source;<SkyrimInstall>\Data\Source\Scripts;<SkyrimDataFolder>\Scripts" -o="Scripts"
PapyrusCompiler.exe Scripts\Source\ChaosSpawnManager.psc  -i="Scripts\Source;<SkyrimInstall>\Data\Source\Scripts;<SkyrimDataFolder>\Scripts" -o="Scripts"
```

## Wiring up in the Creation Kit

1. Create a new Quest (e.g. `STE_ChaosRouterQuest`), start-game-enabled, no
   quest stages needed.
2. Attach `SkyrimChaosRouter.psc` to it; fill in the `PlayerRef`,
   `ChaosSpawnZone`, and `Gold001` properties.
3. Create a second Quest (or reuse the same one) for `ChaosSpawnManager.psc`;
   fill in `ChaosDragonLeveledActor` and `ChaosChickenBase`.
4. Build a plugin (`.esp`/`.esl`) containing both quests and save it alongside
   this `Data/` tree.
