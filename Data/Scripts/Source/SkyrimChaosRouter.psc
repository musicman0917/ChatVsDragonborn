Scriptname SkyrimChaosRouter extends Quest
{
  Polls the SKSE plugin for queued chaos commands and dispatches each one to
  its effect handler. Attach this script to a persistent, always-running
  quest (start-game-enabled, no start-up stage). See docs/ARCHITECTURE.md
  step 5-6 for the full pipe -> native -> Papyrus -> engine call chain.
}

; --- Tunables -------------------------------------------------------------

float Property PollIntervalSeconds = 0.1 Auto
{ How often to ask the SKSE plugin for the next queued command. Kept short
  since chaos commands should feel near-instant to chat. }

Actor Property PlayerRef Auto
EncounterZone Property ChaosSpawnZone Auto
{ Optional: assign a dedicated encounter zone so spawned hostiles don't
  scale into an already-hard fight. }
MiscObject Property Gold001 Auto
{ Fill in with the vanilla Gold001 form in the Creation Kit. }

; --- Lifecycle --------------------------------------------------------------

Event OnInit()
    RegisterForSingleUpdate(PollIntervalSeconds)
EndEvent

Event OnUpdate()
    string[] command = STE_Native.PollNextCommand()
    if command.Length > 0
        RouteCommand(command)
    endif
    RegisterForSingleUpdate(PollIntervalSeconds)
EndEvent

; --- Routing ----------------------------------------------------------------

; command layout, per SKSEPlugin/src/Papyrus/ChaosNativeFunctions.cpp:
;   [0] id            (echoed back via STE_Native.ReportCommandResult)
;   [1] type          ("ragdoll" | "spawn_dragon" | "spawn_chickens" |
;                       "earthquake" | "invert_controls" | "add_gold" |
;                       "remove_gold" | "low_gravity")
;   [2] viewer        (Twitch display name, for logging/messages only)
;   [3] price         (points spent, as string; informational here)
;   [4] argsJson      (effect-specific payload, parsed via JsonUtil on demand)
Function RouteCommand(string[] command)
    string id = command[0]
    string cmdType = command[1]
    string viewer = command[2]
    string argsJson = command[4]

    bool success = false
    string message = ""

    if cmdType == "ragdoll"
        success = ExecuteRagdoll()
        message = viewer + " ragdolled the Dragonborn!"
    elseif cmdType == "earthquake"
        success = ExecuteEarthquake()
        message = viewer + " triggered an earthquake!"
    elseif cmdType == "spawn_dragon"
        success = ExecuteSpawnDragon()
        message = viewer + " summoned a dragon!"
    elseif cmdType == "spawn_chickens"
        success = ExecuteSpawnChickens(argsJson)
        message = viewer + " unleashed the chicken swarm!"
    elseif cmdType == "invert_controls"
        success = ExecuteInvertControls(argsJson)
        message = viewer + " inverted your controls!"
    elseif cmdType == "low_gravity"
        success = ExecuteLowGravity(argsJson)
        message = viewer + " turned on low gravity!"
    elseif cmdType == "add_gold"
        success = ExecuteGoldDelta(argsJson, true)
        message = viewer + " gave the Dragonborn gold!"
    elseif cmdType == "remove_gold"
        success = ExecuteGoldDelta(argsJson, false)
        message = viewer + " stole the Dragonborn's gold!"
    else
        message = "Unknown command type: " + cmdType
        Debug.Trace("SkyrimChaosRouter: unknown command type '" + cmdType + "' (id=" + id + ")")
    endif

    STE_Native.ReportCommandResult(id, success, message)
EndFunction

; --- Effect handlers ---------------------------------------------------------

bool Function ExecuteRagdoll()
    if !PlayerRef
        return false
    endif
    PlayerRef.PushActorAway(PlayerRef, 0.0)
    return true
EndFunction

bool Function ExecuteEarthquake()
    if !PlayerRef
        return false
    endif
    Game.ShakeCamera(PlayerRef, 1.0, 3.0)
    return true
EndFunction

bool Function ExecuteSpawnDragon()
    ; Actual leveled-actor selection + safe-spawn-point logic lives in a
    ; dedicated ChaosSpawnManager script (Phase 3 of docs/IMPLEMENTATION_PLAN.md);
    ; this stub shows the call shape the router expects handlers to expose.
    Actor spawned = ChaosSpawnManager.SpawnHostileDragon(PlayerRef, ChaosSpawnZone)
    return spawned != None
EndFunction

bool Function ExecuteSpawnChickens(string argsJson)
    int count = JsonUtil.JsonInt(argsJson, "count", 5)
    return ChaosSpawnManager.SpawnChickenSwarm(PlayerRef, count) > 0
EndFunction

bool Function ExecuteInvertControls(string argsJson)
    int durationSeconds = JsonUtil.JsonIntFromString(STE_Native.GetSetting("chaos.invert_controls.duration_seconds"), 20)
    ; Input remap itself is native (Papyrus can't hook input directly) — this
    ; just tells the plugin to flip the flag and auto-revert after duration.
    STE_Native.SetSetting("runtime.invert_controls.active_until", (Utility.GetCurrentRealTime() + durationSeconds) as String)
    return true
EndFunction

bool Function ExecuteLowGravity(string argsJson)
    int durationSeconds = JsonUtil.JsonIntFromString(STE_Native.GetSetting("chaos.low_gravity.duration_seconds"), 30)
    STE_Native.SetSetting("runtime.low_gravity.active_until", (Utility.GetCurrentRealTime() + durationSeconds) as String)
    return true
EndFunction

bool Function ExecuteGoldDelta(string argsJson, bool isAdd)
    if !PlayerRef
        return false
    endif
    int amount = JsonUtil.JsonInt(argsJson, "amount", 100)
    if !isAdd
        amount = -amount
    endif
    PlayerRef.AddItem(Gold001, amount, true)
    return true
EndFunction
