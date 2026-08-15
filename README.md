# ChatVsDragonborn — SkyrimTwitchExpansion

A Twitch-chat-driven chaos mod for Skyrim: viewers earn points and spend them
on `!buy <action>` commands (ragdoll the player, spawn a dragon, trigger an
earthquake, invert controls, and more), vote in periodic chat polls, and see
live toasts through an OBS overlay — all configurable in-game via MCM without
restarting Skyrim.

It's built as three cooperating pieces:

- **`SKSEPlugin/`** — the C++ SKSE plugin (CommonLibSSE NG) that runs inside
  Skyrim: engine hooks, the main-thread task queue, and the native functions
  Papyrus calls to execute chaos effects.
- **`Data/`** — the mod's payload as it ships into a Skyrim `Data\` folder:
  Papyrus scripts (`Scripts/Source/SkyrimChaosRouter.psc`), the MCM menu
  config, and the plugin's boot-time `.ini`.
- **`TwitchBridge/`** — a standalone C# .NET companion app that owns all the
  networking: the Twitch IRC client, Helix API calls, the points economy
  ledger, and the local HTTP/WebSocket server for the OBS browser-source
  overlay. It talks to the SKSE plugin over a local named pipe.

See **`docs/ARCHITECTURE.md`** for the full data-flow diagram (Twitch → bridge
→ plugin → Papyrus → game engine) and the threading rules that keep network
I/O off the game's main thread. See **`docs/IMPLEMENTATION_PLAN.md`** for the
phased build-out plan from this scaffold to a shippable mod.

## Repository layout

```
SKSEPlugin/            C++ SKSE plugin (CommonLibSSE NG)
  src/Bridge/           Named-pipe IPC server + thread-safe message queue
  src/Hooks/             Native engine event sinks (OnPlayerHit, spell casts, GameHour)
  src/Papyrus/           Native functions exposed to Papyrus (STE_Native.*)
  src/Settings/          Live-editable settings store backing the MCM menu
  src/Update/            GitHub Releases update checker
Data/                   Mod payload — copy this into a Skyrim Data\ folder
  SKSE/Plugins/          Compiled plugin + boot-time .ini land here
  Scripts/Source/        Papyrus sources (SkyrimChaosRouter.psc, STE_Native.psc)
  MCM/Config/            MCM Helper menu definition
TwitchBridge/            C# .NET companion app (Twitch IRC/Helix + overlay server)
  TwitchBridge.App/Services/   IRC, Helix, points economy, overlay HTTP, Skyrim IPC client
  TwitchBridge.App/wwwroot/    OBS browser-source overlay (HTML/CSS/JS)
installer/               install.ps1 — copies build output into a Data\ folder + bridge install
docs/                    Architecture + implementation plan
```

## Building

**SKSE plugin** (Windows, MSVC + vcpkg + CommonLibSSE-NG):

```powershell
git submodule add https://github.com/CharmedBaryon/CommonLibSSE-NG SKSEPlugin/extern/CommonLibSSE-NG
cd SKSEPlugin
cmake --preset windows-msvc
cmake --build --preset windows-msvc
```

**TwitchBridge** (.NET 8):

```powershell
cd TwitchBridge
dotnet publish TwitchBridge.App -c Release -r win-x64 --self-contained false
```

**Install into a Data\ folder / MO2 profile:**

```powershell
installer/install.ps1 -SkyrimDataPath "D:\Games\MO2\mods\SkyrimTwitchExpansion"
```
