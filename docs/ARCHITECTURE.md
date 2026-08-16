# SkyrimTwitchExpansion — Architecture

## 1. Overview

SkyrimTwitchExpansion ports the points-economy / chaos-command architecture of our Unity
Twitch-integration mod onto Skyrim. Skyrim has no managed scripting runtime capable of
running a Twitch IRC client or an HTTP server reliably inside the game process, so the
system is split into two processes that talk over a local IPC channel:

- **TwitchBridge** — an out-of-process C# .NET background worker. Owns all networking:
  Twitch IRC (chat), Twitch Helix (follows/subs/points), and a local HTTP server for the
  OBS browser-source overlay. Never touches Skyrim memory directly.
- **SkyrimTwitchExpansion.dll** — an SKSE plugin (C++ / CommonLibSSE NG). Owns everything
  that has to run inside the Skyrim process: engine hooks, the main-thread task queue,
  and the native functions Papyrus calls to execute chaos effects.
- **Papyrus (`SkyrimChaosRouter.psc` + friends)** — the last hop. Polls the SKSE plugin
  for queued commands and calls native Skyrim game functions (`Game.ShakeCamera`,
  `Actor.PushActorAway`, `PlaceAtMe`, spell casts, etc.) that C++ alone can't safely
  reach without deep engine knowledge.

This mirrors the Unity mod's shape: a background service owns Twitch, a thread-safe
queue crosses the thread boundary, and the "engine" (Unity MonoBehaviour update loop /
Skyrim Papyrus VM tick) drains the queue on its own cadence.

## 2. Data Flow

```
 Twitch Chat/Helix                         Windows named pipe                 Papyrus VM tick
┌──────────────────┐   IRC / EventSub    ┌───────────────────┐   JSON line    ┌──────────────────┐
│  Twitch servers   │ ───────────────────▶│   TwitchBridge     │ ─────────────▶│  SKSE Plugin      │
│  (chat, subs,     │                     │   (C# .NET worker) │  \\.\pipe\STE │  (C++ / CommonLib)│
│   bits, channel   │◀─────────────────── │                     │◀──────────────│                   │
│   points)         │   Helix REST calls  │  - IRC client       │  ack / state   │  - IPCServer      │
└──────────────────┘                     │  - Points economy    │               │  - MessageQueue   │
        ▲                                 │  - Poll engine       │               │  - EventSink      │
        │  OBS Browser Source (WS/SSE)    │  - HTTP overlay      │               │  - Papyrus natives│
        │◀────────────────────────────────│    server            │               └─────────┬─────────┘
        │        toasts + poll widget      └───────────────────┘                             │
        │                                                                          native call boundary
   Streamer's OBS                                                                             ▼
                                                                                    ┌──────────────────┐
                                                                                    │ SkyrimChaosRouter │
                                                                                    │      .psc         │
                                                                                    │  polls queue on   │
                                                                                    │  quest Update(),   │
                                                                                    │  dispatches to     │
                                                                                    │  Ragdoll/Spawn/    │
                                                                                    │  Earthquake/etc.   │
                                                                                    └──────────────────┘
```

Step by step, for a viewer typing `!buy earthquake` in chat:

1. **Twitch → TwitchBridge**: `TwitchIrcService` receives the PRIVMSG, `HelixApiService`
   has already cached the viewer's sub tier / follow age for point-earn-rate purposes.
   `PointsEconomyService` checks the viewer's balance in the local JSON ledger, debits
   the price, and persists the ledger.
2. **TwitchBridge → SKSE Plugin**: `SkyrimIpcClient` serializes a `ChaosCommand`
   (`{ id, type: "earthquake", viewer, args, ts }`) as one JSON line and writes it to the
   `\\.\pipe\SkyrimTwitchExpansion` named pipe. This never blocks on game state — the
   pipe write happens on the bridge's own thread.
3. **SKSE Plugin ingest**: `IPCServer` runs a dedicated OS thread reading pipe lines. Each
   parsed command is pushed onto a lock-protected `MessageQueue<ChaosCommand>`. This is
   the *only* thread-safe handoff point — nothing on this thread touches Skyrim's engine
   state, satisfying SKSE's "game thread only" rule.
4. **Main-thread hop**: On `SKSE::MessagingInterface::kPostLoadGame` / every
   `kInputLoaded`-gated frame, a task queued via `SKSE::GetTaskInterface()->AddTask(...)`
   (or an `EventSink` on the input/update event) drains ready commands and stages them
   for Papyrus to collect — no Papyrus call happens on the pipe thread.
5. **C++ → Papyrus**: Papyrus doesn't get pushed to directly (Skyrim has no reliable
   native→arbitrary-script call without a live object reference). Instead
   `SkyrimChaosRouter.psc`, running on a persistent quest alias, polls the exposed native
   function `STE_Native.PollNextCommand()` on a short `RegisterForSingleUpdate(0.1)` loop.
6. **Papyrus → Skyrim engine**: The router parses the command tag and routes to a handler
   function (`ExecuteRagdoll`, `ExecuteSpawnDragon`, `ExecuteEarthquake`,
   `ExecuteInvertControls`, `ExecuteGoldDelta`, `ExecuteLowGravity`) which calls native
   Skyrim functions (`PushActorAway`, `PlaceAtMe`, `Game.ShakeCamera`, `Actor.SetActorValue`,
   `SetPlayerControls`, etc.) and then calls `STE_Native.ReportCommandResult(id, success)`
   so the bridge (and eventually the overlay) can show a success/failure toast.
7. **Overlay feedback**: `PointsEconomyService`/`PollEngine` in TwitchBridge push state
   changes (points spent, active poll tallies, command results relayed back over the
   pipe) to connected OBS browser sources via the local overlay server's WebSocket/SSE
   channel, so the toast and poll widget update in near real time.

`EventSink` (native SKSE/CommonLibSSE hooks — `OnPlayerHit`, `OnSpellCast`, `GameHour`)
runs the reverse direction: engine events are captured natively, pushed onto an outbound
queue, and forwarded through the same pipe to TwitchBridge so chat can react to in-game
events (e.g. "the Dragonborn just leveled up!" announcements), without needing Papyrus
polling for things C++ can already observe directly.

## 3. Threading Discipline

| Thread | Owns | Never does |
|---|---|---|
| TwitchBridge IRC thread | Reading/parsing chat | Touch Skyrim memory (impossible anyway — different process) |
| TwitchBridge HTTP/WS thread | Overlay serving | Block on game state |
| SKSE pipe-reader thread | Parsing inbound JSON, `MessageQueue::Push` | Call Papyrus, touch `TESForm`/`Actor` pointers, call any CommonLib engine API |
| Skyrim main/game thread | `MessageQueue::PopAll`, `EventSink` callbacks, staging data for Papyrus, all `PlaceAtMe`/hook work | Block on I/O (pipe reads, HTTP, disk beyond quick INI/JSON saves) |
| Papyrus VM tick | Draining native queue, calling engine functions via script API | Any P/Invoke or file I/O beyond the JSON ledger helpers already provided by the VM |

The single rule enforced throughout: **anything that can block (network, pipe I/O) lives
off the main thread; anything that touches game state lives only on the main thread**,
and the only thing that crosses between them is data (a `ChaosCommand` struct / JSON
line), never a pointer or callback.

## 4. In-Game Settings (MCM)

The C++ plugin owns the canonical settings (`Data/SKSE/Plugins/SkyrimTwitchExpansion.ini`
+ a live JSON overlay for prices/timers so the streamer can hot-edit without restarting).
An MCM Helper-based menu (`Data/MCM/Config/SkyrimTwitchExpansion/config.json`) persists
its own slider values to its own file under `Data/MCM/Settings/`, separate from ours;
`Data/Scripts/Source/STE_MCMConfig.psc` bridges each change into the plugin's settings
store through the same native function surface Papyrus already uses
(`ChaosNativeFunctions::GetSetting/SetSetting`), so "no restart required" falls out of the
existing polling design rather than needing a second code path. TwitchBridge has no fixed
relationship to the game's install directory, so instead of also reading that settings
JSON file directly, the plugin pushes a `settings_sync` OutboundEvent over the existing
pipe (on connect, and again whenever a `chaos.*` key changes) — see
`SKSEPlugin/src/Settings/Settings.h`.

## 5. Update Checker

On `SKSE::MessagingInterface::kPostLoadGame`, the plugin spawns a short-lived background
thread that performs a single HTTPS GET to the GitHub Releases API
(`/repos/<org>/SkyrimTwitchExpansion/releases/latest`), compares the tag against the
compiled-in version, and — if newer — stages a one-shot notification that the main thread
surfaces via `DebugNotification`/`RegisterForSingleUpdate` next tick. This thread is
fire-and-forget and never touches game state itself, keeping it consistent with the
threading rule above.
