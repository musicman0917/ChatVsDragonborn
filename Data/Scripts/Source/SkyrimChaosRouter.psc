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
Potion Property ChaosCheeseItem1 Auto
{ Fill in with a vanilla cheese item in the Creation Kit, e.g. FoodCheeseWheel01A. }
Potion Property ChaosCheeseItem2 Auto
{ e.g. FoodCheeseWheel01B. }
Potion Property ChaosCheeseItem3 Auto
{ e.g. FoodCheeseWheel02A. }
Potion Property ChaosCheeseItem4 Auto
{ e.g. FoodCheeseWheel02B.
  Typed as Potion, not the generic Form — Potion is the actual Papyrus
  script type for ALCH records (Skyrim shares one script type across
  potions, poisons, and food; that's why the cheese wheels show as ALCH
  in the Object Window). The CK's "Pick Object" picker can't build a
  search/browse list for the fully generic Form type (it showed only two
  unrelated system forms no matter what was selected in the Object
  Window, for both this and an earlier Form[] array attempt) — Potion is
  specific enough for the picker to actually work, and still passes into
  PlaceAtMe() fine since Potion is itself a Form. ExecuteSpawnCheese()
  picks one of the four at random per call. }

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
;                       "remove_gold" | "low_gravity" | "spawn_cheese")
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
        resultMessage = FormatResult(success, viewer, "ragdolled the Dragonborn!", "ragdoll failed (no player reference).")
    elseif cmdType == "earthquake"
        success = ExecuteEarthquake()
        resultMessage = FormatResult(success, viewer, "triggered an earthquake!", "earthquake failed (no player reference).")
    elseif cmdType == "spawn_dragon"
        success = ExecuteSpawnDragon()
        resultMessage = FormatResult(success, viewer, "summoned a dragon!", "dragon spawn failed (check ChaosDragonActorBase is set in the CK, and that this save's quest instance picked it up).")
    elseif cmdType == "spawn_chickens"
        success = ExecuteSpawnChickens()
        resultMessage = FormatResult(success, viewer, "unleashed the chicken swarm!", "chicken spawn failed (check ChaosChickenBase is set in the CK, and that this save's quest instance picked it up).")
    elseif cmdType == "invert_controls"
        success = ExecuteInvertControls()
        resultMessage = FormatResult(success, viewer, "inverted your controls!", "invert controls failed.")
    elseif cmdType == "low_gravity"
        success = ExecuteLowGravity()
        resultMessage = FormatResult(success, viewer, "turned on low gravity!", "low gravity failed.")
    elseif cmdType == "add_gold"
        success = ExecuteGoldDelta(true)
        resultMessage = FormatResult(success, viewer, "gave the Dragonborn gold!", "add gold failed (check Gold001 is set in the CK).")
    elseif cmdType == "remove_gold"
        success = ExecuteGoldDelta(false)
        resultMessage = FormatResult(success, viewer, "stole the Dragonborn's gold!", "remove gold failed (check Gold001 is set in the CK).")
    elseif cmdType == "spawn_cheese"
        success = ExecuteSpawnCheese()
        resultMessage = FormatResult(success, viewer, "buried you in cheese!", "cheese spawn failed (check ChaosCheeseItem1-4 are set in the CK).")
    else
        resultMessage = "Unknown command type: " + cmdType
        Debug.Trace("SkyrimChaosRouter: unknown command type '" + cmdType + "' (id=" + id + ")")
    endif

    STE_Native.ReportCommandResult(id, success, resultMessage)
EndFunction

; Builds a result message that actually reflects whether the effect
; succeeded — previously this always used the success-worded text
; regardless of the `success` bool passed alongside it, so a failed
; command still claimed to have worked.
string Function FormatResult(bool success, string viewer, string successText, string failureText)
    if success
        return viewer + " " + successText
    endif
    return viewer + "'s command failed: " + failureText
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
    if !dragon
        return false
    endif

    ; PlaceActorAtMe drops the dragon essentially on top of the player —
    ; fine for the chicken swarm (crowding is the point), but a hostile
    ; dragon spawning point-blank is an unfair instant breath attack.
    ; Reposition it a fixed distance in front of the player's facing
    ; instead.
    float angle = player.GetAngleZ()
    float distance = 1200.0
    float newX = player.GetPositionX() + (distance * Math.sin(angle))
    float newY = player.GetPositionY() + (distance * Math.cos(angle))
    dragon.SetPosition(newX, newY, player.GetPositionZ())

    return true
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

    int amount
    if isAdd
        amount = STE_Native.GetSettingInt("chaos.add_gold.amount", 100)
    else
        amount = -STE_Native.GetSettingInt("chaos.remove_gold.amount", 100)
    endif

    player.AddItem(Gold001, amount, true)
    return true
EndFunction

bool Function ExecuteSpawnCheese()
    Actor player = Game.GetPlayer()
    if !player
        return false
    endif

    Form[] cheeseForms = new Form[4]
    cheeseForms[0] = ChaosCheeseItem1
    cheeseForms[1] = ChaosCheeseItem2
    cheeseForms[2] = ChaosCheeseItem3
    cheeseForms[3] = ChaosCheeseItem4

    ; Not all 4 slots are guaranteed to be filled in the CK, so retry a few
    ; times rather than risk landing on an unset (None) slot.
    Form cheeseForm = None
    int attempts = 0
    while !cheeseForm && attempts < 10
        cheeseForm = cheeseForms[Utility.RandomInt(0, 3)]
        attempts += 1
    endwhile

    if !cheeseForm
        return false
    endif

    int count = Utility.RandomInt(15, 40)
    player.PlaceAtMe(cheeseForm, count)
    return true
EndFunction
