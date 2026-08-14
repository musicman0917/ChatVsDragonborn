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

`Scripts/Source/*.psc` need to be compiled to `.pex` with the Creation Kit's
Papyrus Compiler (or Champollion/PapyrusCompiler.exe directly), with
`Scripts/Source` plus your Skyrim install's own `Data/Scripts/Source` (for the
base-game scripts referenced, e.g. `Quest`, `Actor`) on the import path.
Compiled `.pex` files are intentionally not committed (see `.gitignore`) —
build them locally or as part of a release pipeline.

```powershell
PapyrusCompiler.exe Scripts\Source\SkyrimChaosRouter.psc -i="Scripts\Source;<SkyrimInstall>\Data\Scripts\Source" -o="Scripts"
PapyrusCompiler.exe Scripts\Source\ChaosSpawnManager.psc  -i="Scripts\Source;<SkyrimInstall>\Data\Scripts\Source" -o="Scripts"
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
