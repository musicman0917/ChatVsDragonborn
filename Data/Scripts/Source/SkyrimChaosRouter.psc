Scriptname SkyrimChaosRouter extends Quest
{
  Polls the SKSE plugin for queued chaos commands and dispatches each one to
  its effect handler. Attach this script to a persistent, always-running
  quest (start-game-enabled, no start-up stage). See docs/ARCHITECTURE.md
  step 5-6 for the full pipe -> native -> Papyrus -> engine call chain.

  Spawn logic (ExecuteSpawnDragon/ExecuteSpawnChickens) lives directly on
  this script rather than a separate ChaosSpawnManager script: the Creation
  Kit has no GUI way to point a script-type Property at a bare Quest form
  (the "Pick Object" picker only lists placed object references, not Quest
  forms — even the quest carrying the target script itself), so a second
  script needing a live reference back to this one had no way to be wired
  up. Since nothing else needs these functions independently, keeping them
  here avoids the problem entirely.
}

; --- Tunables -------------------------------------------------------------

float Property PollIntervalSeconds = 0.1 Auto
{ How often to ask the SKSE plugin for the next queued command. Kept short
  since chaos commands should feel near-instant to chat. }

EncounterZone Property ChaosSpawnZone Auto
{ Optional: assign a dedicated encounter zone so spawned hostiles don't
  scale into an already-hard fight. }
MiscObject Property Gold001 Auto
{ Fill in with the vanilla Gold001 form in the Creation Kit. }
ActorBase Property ChaosDragonActorBase Auto
{ An NPC_ record for a hostile dragon (e.g. the vanilla EncDragon01Fire).
  Not a LeveledActor — those need a different placement function
  (PlaceAtMe) that doesn't accept an EncounterZone, and are also much
  harder to locate/assign in the Creation Kit's object pickers than a
  plain ActorBase, so a concrete dragon template is used directly instead. }
ActorBase Property ChaosChickenBase Auto
{ An NPC_ record (e.g. the vanilla "Chicken" ActorBase) — PlaceActorAtMe
  needs an ActorBase template, not a placed Actor reference. }

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
; Any numeric arg a handler needs (chicken count, gold amount) comes from
; STE_Native.GetCommandArgInt(key, default) instead of a JSON blob here —
; the plugin already parsed it, so Papyrus never touches raw JSON.
Function RouteCommand(string[] command)
    string id = command[0]
    string cmdType = command[1]
    string viewer = command[2]

    bool success = false
    ; Named resultMessage, not "message" — that collides with Skyrim's own
    ; Message script/type (Papyrus identifiers are case-insensitive) and the
    ; compiler rejects it as "cannot name a variable... the same as a known
    ; type or script".
    string resultMessage = ""

    if cmdType == "ragdoll"
        success = ExecuteRagdoll()
        resultMessage = viewer + " ragdolled the Dragonborn!"
    elseif cmdType == "earthquake"
        success = ExecuteEarthquake()
        resultMessage = viewer + " triggered an earthquake!"
    elseif cmdType == "spawn_dragon"
        success = ExecuteSpawnDragon()
        resultMessage = viewer + " summoned a dragon!"
    elseif cmdType == "spawn_chickens"
        success = ExecuteSpawnChickens()
        resultMessage = viewer + " unleashed the chicken swarm!"
    elseif cmdType == "invert_controls"
        success = ExecuteInvertControls()
        resultMessage = viewer + " inverted your controls!"
    elseif cmdType == "low_gravity"
        success = ExecuteLowGravity()
        resultMessage = viewer + " turned on low gravity!"
    elseif cmdType == "add_gold"
        success = ExecuteGoldDelta(true)
        resultMessage = viewer + " gave the Dragonborn gold!"
    elseif cmdType == "remove_gold"
        success = ExecuteGoldDelta(false)
        resultMessage = viewer + " stole the Dragonborn's gold!"
    else
        resultMessage = "Unknown command type: " + cmdType
        Debug.Trace("SkyrimChaosRouter: unknown command type '" + cmdType + "' (id=" + id + ")")
    endif

    STE_Native.ReportCommandResult(id, success, resultMessage)
EndFunction

; --- Effect handlers ---------------------------------------------------------

bool Function ExecuteRagdoll()
    Actor player = Game.GetPlayer()
    if !player
        return false
    endif
    player.PushActorAway(player, 0.0)
    return true
EndFunction

bool Function ExecuteEarthquake()
    Actor player = Game.GetPlayer()
    if !player
        return false
    endif
    Game.ShakeCamera(player, 1.0, 3.0)
    return true
EndFunction

bool Function ExecuteSpawnDragon()
    Actor player = Game.GetPlayer()
    if !player || !ChaosDragonActorBase
        return false
    endif

    Actor dragon = player.PlaceActorAtMe(ChaosDragonActorBase, 4, ChaosSpawnZone)
    return dragon != None
EndFunction

bool Function ExecuteSpawnChickens()
    Actor player = Game.GetPlayer()
    if !player || !ChaosChickenBase
        return false
    endif

    int count = STE_Native.GetCommandArgInt("count", 5)
    int spawned = 0
    int i = 0
    while i < count
        if player.PlaceActorAtMe(ChaosChickenBase)
            spawned += 1
        endif
        i += 1
    endwhile
    return spawned > 0
EndFunction

bool Function ExecuteInvertControls()
    int durationSeconds = STE_Native.GetSettingInt("chaos.invert_controls.duration_seconds", 20)
    ; Input remap itself is native (Papyrus can't hook input directly) — this
    ; just tells the plugin to flip the flag and auto-revert after duration.
    STE_Native.SetSetting("runtime.invert_controls.active_until", (Utility.GetCurrentRealTime() + durationSeconds) as String)
    return true
EndFunction

bool Function ExecuteLowGravity()
    int durationSeconds = STE_Native.GetSettingInt("chaos.low_gravity.duration_seconds", 30)
    STE_Native.SetSetting("runtime.low_gravity.active_until", (Utility.GetCurrentRealTime() + durationSeconds) as String)
    return true
EndFunction

bool Function ExecuteGoldDelta(bool isAdd)
    Actor player = Game.GetPlayer()
    if !player
        return false
    endif
    int amount = STE_Native.GetCommandArgInt("amount", 100)
    if !isAdd
        amount = -amount
    endif
    player.AddItem(Gold001, amount, true)
    return true
EndFunction
