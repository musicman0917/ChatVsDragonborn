# SkyrimTwitchExpansion — Implementation Plan

See `ARCHITECTURE.md` for the data-flow diagram and threading rules referenced below.

## Phase 0 — Toolchain & Scaffolding (this commit)

- [x] Repo layout: `SKSEPlugin/` (C++), `Data/` (mod payload), `TwitchBridge/` (C#),
      `installer/`, `docs/`.
- [x] CMake + vcpkg skeleton for CommonLibSSE NG, targeting SE/AE/VR via
      `CommonLibSSE-NG`'s multi-runtime build.
- [x] `.NET 8` worker-service skeleton for TwitchBridge with DI-wired stub services.
- [x] Pipe protocol draft (`Bridge/Protocol.h` ↔ `Models/ChaosCommand.cs`) — JSON-line
      framing over `\\.\pipe\SkyrimTwitchExpansion`.
- [ ] CI: GitHub Actions matrix building the plugin (Windows, MSVC, CMake+vcpkg) and the
      bridge (`dotnet build`/`dotnet publish -r win-x64`).

## Phase 1 — Points Economy (local JSON ledger)

- [ ] `TwitchBridge`: `PointsEconomyService` — per-viewer balance, earn-rate ticks
      (points/min while live), event-based grants (sub, resub, bits, channel-point
      redemption via EventSub), atomic JSON persistence (write-to-temp + rename).
- [ ] Admin/mod commands (`!points add <user> <n>`, `!points set`) gated by Twitch
      badge checks.
- [ ] Unit tests around the ledger (concurrent grant + spend, corrupt-file recovery).

## Phase 2 — Chaos Command Pipe & Native Bridge

- [ ] Finalize `ChaosCommand` schema (id, type, viewer, args, price, ts).
- [ ] `SKSEPlugin`: `IPCServer` (named pipe, one reader thread, JSON-line framing,
      reconnect loop if the bridge restarts).
- [ ] `SKSEPlugin`: `MessageQueue<ChaosCommand>` — mutex + deque, `Push`/`PopAll`, plus an
      outbound queue for command-result acks and native engine events.
- [ ] `SKSEPlugin`: Papyrus native function surface (`Papyrus/ChaosNativeFunctions`) —
      `PollNextCommand`, `ReportCommandResult`, `GetSetting`/`SetSetting` for MCM.
- [ ] `Data/Scripts/Source/SkyrimChaosRouter.psc` — polling quest script dispatching to
      per-effect handler scripts.
- [ ] First 3 vertical-slice effects end-to-end: ragdoll player, add/remove gold,
      earthquake/camera-shake. These exercise pipe → queue → Papyrus → engine without
      needing spawn logic yet.

## Phase 3 — Remaining Chaos Effects

- [ ] Spawn effects (hostile dragon, chicken swarm) — leveled-list-safe `PlaceAtMe` with
      cell-safety checks (don't spawn on top of the player, respect interior/exterior).
- [ ] Invert controls — via `SKSE::GetInputMap` remap or a hooked
      `MovementHandler`/`ButtonEvent` sink (native, since Papyrus can't remap input).
- [ ] Toggle low gravity — native `Setting`/havok scale hook (`fMaxTeleportDistanceIWD`-
      style physics setting via `TESObjectREFR` / global game settings, guarded by a
      revert-on-crash-or-unload safety timer so a dropped connection can't strand the
      player in a broken state).
- [ ] Effect registry pattern so new `!buy` actions are a config entry + one handler
      function, not a new pipe message type.

## Phase 4 — Chat-Vote Polls

- [ ] `TwitchBridge`: `PollEngine` — picks a randomized subset of enabled chaos actions,
      opens a timed chat vote (`!vote 1/2/3`), tallies, announces winner, enqueues the
      winning `ChaosCommand` (price = 0, funded by the "free" pool) through the same pipe
      path as purchased commands.
- [ ] Periodic auto-poll timer + streamer-triggered `!chaosvote` on-demand trigger.
- [ ] Overlay poll widget consumes the same tally stream (see Phase 5).

## Phase 5 — OBS Overlay Server

- [ ] `TwitchBridge`: `OverlayHttpServer` — Kestrel minimal-API host serving
      `wwwroot/overlay.html` (transparent background, toast queue + live poll bars) and a
      WebSocket endpoint pushing `{type: "toast"|"poll_update"|"command_result", ...}`
      events.
- [ ] Toasts triggered by: points spent, chaos command fired/succeeded/failed, poll
      opened/closed.
- [ ] Configurable port + local-only binding (127.0.0.1) for OBS Browser Source safety.

## Phase 6 — In-Game Settings Menu (MCM)

- [ ] `Data/MCM/Config/SkyrimTwitchExpansion/config.json` (MCM Helper schema) — sliders/
      toggles for prices, cooldowns, poll interval, effect enable flags.
- [ ] Wire MCM reads/writes through `ChaosNativeFunctions::GetSetting/SetSetting`, which
      persist to the same live-editable JSON the bridge and plugin both read, so changes
      apply without a restart (per `ARCHITECTURE.md` §4).

## Phase 7 — Native Engine Hooks (CommonLibSSE)

- [x] `Hooks/EventSink` — subscribe to `TESHitEvent` (OnPlayerHit) and the spell-cast
      event source. Confirmed live: engine event sinks register successfully on a real
      game launch.
- [ ] A genuine per-frame hook is still needed to drive `Hooks::PollGameHour()` and
      `Update::TakePendingNotification()` — both were originally wired through a
      self-rearming `SKSE::GetTaskInterface()->AddTask()` task (re-adding itself each run
      to fake a recurring tick), which **hung the game at the main menu** the one time it
      was tested live. `AddTask`'s actual queue-draining behavior when a task re-adds
      itself was never verified against SKSE's source before shipping it, and it's
      plausible newly-added tasks get processed within the same drain pass rather than
      deferred to the next frame — a tight synchronous loop with no chance to render.
      Removed for now (see `main.cpp`); replace with a real per-frame hook (e.g. an
      Xbyak/trampoline hook on the main update loop — `SKSE_SUPPORT_XBYAK` in
      `CMakePresets.json` is currently `OFF`) before restoring either feature.
- [x] Address-library-only (`v.UsesAddressLibrary(true)`) — no hardcoded SE/AE offsets,
      so the plugin stays compatible across Skyrim runtime patches without recompiling
      per-version. Confirmed live: loads correctly against game version 1.6.1170.0 with
      only Address Library's `versionlib-*.bin` on disk, no hardcoded offsets.

## Phase 8 — Update Checker

- [ ] `Update/UpdateChecker` — background HTTPS GET to GitHub Releases `/latest`, semver
      compare, one-shot in-game notification. No auto-download (manual update only, to
      avoid touching the user's mod manager state).

## Phase 9 — Packaging & Install

- [ ] `installer/install.ps1` — copies built `SkyrimTwitchExpansion.dll` +
      `Scripts/*.pex` + `MCM/Config/*` into a target `Data/` (Skyrim install or MO2
      profile), and drops the built TwitchBridge `win-x64` publish output alongside a
      `SkyrimTwitchExpansion.dll`-adjacent `TwitchBridge/` folder with a shortcut/`.bat`
      launcher.
- [ ] Release archive layout mirrors `Data/` 1:1 so it can be dropped straight into a mod
      manager as a normal FOMOD-less mod, with `TwitchBridge/` shipped as a sibling
      standalone folder (not part of the Skyrim `Data/` tree).

## Open Questions / Risks

- **Named pipe vs. loopback WebSocket**: named pipes need no firewall exception and are
  simpler on Windows; a loopback WebSocket is easier to debug and reuse for the overlay.
  Scaffolding ships named-pipe first since it has zero extra runtime dependency for the
  SKSE side; revisit if TwitchBridge ends up wanting a single transport for both the
  plugin and the overlay.
- **Low-gravity / invert-controls safety**: both effects must have a hard server-side
  and client-side timeout so a crashed TwitchBridge process (or a lost pipe connection)
  can never leave the player permanently affected — the plugin should self-revert any
  "state" effect after its configured duration regardless of pipe state.
- **Spawn safety**: hostile spawns need cell/interior checks to avoid softlocks (e.g.
  spawning a dragon inside a house cell). Phase 3 should land a shared "is this a safe
  spawn context" helper before adding more spawn-type effects.
