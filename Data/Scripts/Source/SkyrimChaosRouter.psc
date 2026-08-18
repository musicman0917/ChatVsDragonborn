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

; --- Item/scroll grants ------------------------------------------------------
; Same reasoning as the cheese properties above: each is typed as the most
; specific real Papyrus type for its record (Potion for ALCH food, Ammo for
; arrows, MiscObject for crafting materials, SoulGem for soul gems, Scroll
; for SCRL records) rather than the generic Form, since that's what makes
; the CK's picker actually work. All handled by the shared ExecuteGiveItem()
; below rather than one function each.

Potion Property ChaosGiveApples Auto
{ e.g. the vanilla Apple. }
Ammo Property ChaosGiveArrows Auto
{ e.g. the vanilla Iron Arrow. }
Potion Property ChaosGiveBakedPotatoes Auto
{ e.g. the vanilla Baked Potato. }
MiscObject Property ChaosGiveDiamond Auto
{ e.g. the vanilla flawless/regular Diamond. }
MiscObject Property ChaosGiveDragonBone Auto
{ Vanilla Dragon Bone. }
MiscObject Property ChaosGiveDragonScales Auto
{ Vanilla Dragon Scales. }
MiscObject Property ChaosGiveGoldIngot Auto
{ Vanilla Gold Ingot. }
MiscObject Property ChaosGiveIronIngot Auto
{ Vanilla Iron Ingot. }
Potion Property ChaosGivePotatoes Auto
{ e.g. the vanilla raw Potato. }
MiscObject Property ChaosGiveSilverIngot Auto
{ Vanilla Silver Ingot. }
SoulGem Property ChaosGiveSoulGemCommon Auto
{ A common (not petty/grand) Soul Gem, empty or filled. }

Scroll Property ChaosScrollBlizzard Auto
Scroll Property ChaosScrollConjureFlameAtronach Auto
Scroll Property ChaosScrollConjureFrostAtronach Auto
Scroll Property ChaosScrollConjureStormAtronach Auto
Scroll Property ChaosScrollFlameThrall Auto
Scroll Property ChaosScrollFrostThrall Auto
Scroll Property ChaosScrollHarmony Auto
Scroll Property ChaosScrollHysteria Auto
Scroll Property ChaosScrollInvisibility Auto
Scroll Property ChaosScrollMayhem Auto
Scroll Property ChaosScrollStormThrall Auto
Scroll Property ChaosScrollWaterBreathing Auto
{ All twelve are vanilla scrolls, found in the Object Window under their
  matching "Scroll of ..." names. Granted to the Dragonborn's inventory
  like any other item grant, not cast automatically -- "Activate" in the
  chat command name just means "use !buy" the same as everything else. }

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
;                       "remove_gold" | "low_gravity" | "spawn_cheese" |
;                       "cheese_mageddon" | "give_10_gold" | "give_100_gold" |
;                       "give_1000_gold" | "give_apples" | "give_arrows" |
;                       "give_baked_potatoes" | "give_diamond" |
;                       "give_dragon_bone" | "give_dragon_scales" |
;                       "give_gold_ingot" | "give_iron_ingot" |
;                       "give_potatoes" | "give_silver_ingot" |
;                       "give_soul_gem_common" | "scroll_blizzard" |
;                       "scroll_conjure_flame_atronach" |
;                       "scroll_conjure_frost_atronach" |
;                       "scroll_conjure_storm_atronach" | "scroll_flame_thrall" |
;                       "scroll_frost_thrall" | "scroll_harmony" |
;                       "scroll_hysteria" | "scroll_invisibility" |
;                       "scroll_mayhem" | "scroll_storm_thrall" |
;                       "scroll_water_breathing" | "yeet")
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
    elseif cmdType == "cheese_mageddon"
        success = ExecuteCheeseMageddon()
        resultMessage = FormatResult(success, viewer, "triggered CHEESE-MAGEDDON!", "cheese-mageddon failed (check ChaosCheeseItem1-4 are set in the CK).")
    elseif cmdType == "give_10_gold"
        success = ExecuteGiveGold(10)
        resultMessage = FormatResult(success, viewer, "got 10 gold!", "give gold failed (check Gold001 is set in the CK).")
    elseif cmdType == "give_100_gold"
        success = ExecuteGiveGold(100)
        resultMessage = FormatResult(success, viewer, "got 100 gold!", "give gold failed (check Gold001 is set in the CK).")
    elseif cmdType == "give_1000_gold"
        success = ExecuteGiveGold(1000)
        resultMessage = FormatResult(success, viewer, "got 1000 gold!", "give gold failed (check Gold001 is set in the CK).")
    elseif cmdType == "give_apples"
        success = ExecuteGiveItem(ChaosGiveApples, 1)
        resultMessage = FormatResult(success, viewer, "got an apple!", "give apples failed (check ChaosGiveApples is set in the CK).")
    elseif cmdType == "give_arrows"
        success = ExecuteGiveItem(ChaosGiveArrows, 20)
        resultMessage = FormatResult(success, viewer, "got a quiver of arrows!", "give arrows failed (check ChaosGiveArrows is set in the CK).")
    elseif cmdType == "give_baked_potatoes"
        success = ExecuteGiveItem(ChaosGiveBakedPotatoes, 1)
        resultMessage = FormatResult(success, viewer, "got a baked potato!", "give baked potatoes failed (check ChaosGiveBakedPotatoes is set in the CK).")
    elseif cmdType == "give_diamond"
        success = ExecuteGiveItem(ChaosGiveDiamond, 1)
        resultMessage = FormatResult(success, viewer, "got a diamond!", "give diamond failed (check ChaosGiveDiamond is set in the CK).")
    elseif cmdType == "give_dragon_bone"
        success = ExecuteGiveItem(ChaosGiveDragonBone, 1)
        resultMessage = FormatResult(success, viewer, "got a dragon bone!", "give dragon bone failed (check ChaosGiveDragonBone is set in the CK).")
    elseif cmdType == "give_dragon_scales"
        success = ExecuteGiveItem(ChaosGiveDragonScales, 1)
        resultMessage = FormatResult(success, viewer, "got dragon scales!", "give dragon scales failed (check ChaosGiveDragonScales is set in the CK).")
    elseif cmdType == "give_gold_ingot"
        success = ExecuteGiveItem(ChaosGiveGoldIngot, 1)
        resultMessage = FormatResult(success, viewer, "got a gold ingot!", "give gold ingot failed (check ChaosGiveGoldIngot is set in the CK).")
    elseif cmdType == "give_iron_ingot"
        success = ExecuteGiveItem(ChaosGiveIronIngot, 1)
        resultMessage = FormatResult(success, viewer, "got an iron ingot!", "give iron ingot failed (check ChaosGiveIronIngot is set in the CK).")
    elseif cmdType == "give_potatoes"
        success = ExecuteGiveItem(ChaosGivePotatoes, 5)
        resultMessage = FormatResult(success, viewer, "got 5 potatoes!", "give potatoes failed (check ChaosGivePotatoes is set in the CK).")
    elseif cmdType == "give_silver_ingot"
        success = ExecuteGiveItem(ChaosGiveSilverIngot, 1)
        resultMessage = FormatResult(success, viewer, "got a silver ingot!", "give silver ingot failed (check ChaosGiveSilverIngot is set in the CK).")
    elseif cmdType == "give_soul_gem_common"
        success = ExecuteGiveItem(ChaosGiveSoulGemCommon, 1)
        resultMessage = FormatResult(success, viewer, "got a common soul gem!", "give soul gem failed (check ChaosGiveSoulGemCommon is set in the CK).")
    elseif cmdType == "scroll_blizzard"
        success = ExecuteGiveItem(ChaosScrollBlizzard, 1)
        resultMessage = FormatResult(success, viewer, "got a Scroll of Blizzard!", "scroll grant failed (check ChaosScrollBlizzard is set in the CK).")
    elseif cmdType == "scroll_conjure_flame_atronach"
        success = ExecuteGiveItem(ChaosScrollConjureFlameAtronach, 1)
        resultMessage = FormatResult(success, viewer, "got a Scroll of Conjure Flame Atronach!", "scroll grant failed (check ChaosScrollConjureFlameAtronach is set in the CK).")
    elseif cmdType == "scroll_conjure_frost_atronach"
        success = ExecuteGiveItem(ChaosScrollConjureFrostAtronach, 1)
        resultMessage = FormatResult(success, viewer, "got a Scroll of Conjure Frost Atronach!", "scroll grant failed (check ChaosScrollConjureFrostAtronach is set in the CK).")
    elseif cmdType == "scroll_conjure_storm_atronach"
        success = ExecuteGiveItem(ChaosScrollConjureStormAtronach, 1)
        resultMessage = FormatResult(success, viewer, "got a Scroll of Conjure Storm Atronach!", "scroll grant failed (check ChaosScrollConjureStormAtronach is set in the CK).")
    elseif cmdType == "scroll_flame_thrall"
        success = ExecuteGiveItem(ChaosScrollFlameThrall, 1)
        resultMessage = FormatResult(success, viewer, "got a Scroll of Flame Thrall!", "scroll grant failed (check ChaosScrollFlameThrall is set in the CK).")
    elseif cmdType == "scroll_frost_thrall"
        success = ExecuteGiveItem(ChaosScrollFrostThrall, 1)
        resultMessage = FormatResult(success, viewer, "got a Scroll of Frost Thrall!", "scroll grant failed (check ChaosScrollFrostThrall is set in the CK).")
    elseif cmdType == "scroll_harmony"
        success = ExecuteGiveItem(ChaosScrollHarmony, 1)
        resultMessage = FormatResult(success, viewer, "got a Scroll of Harmony!", "scroll grant failed (check ChaosScrollHarmony is set in the CK).")
    elseif cmdType == "scroll_hysteria"
        success = ExecuteGiveItem(ChaosScrollHysteria, 1)
        resultMessage = FormatResult(success, viewer, "got a Scroll of Hysteria!", "scroll grant failed (check ChaosScrollHysteria is set in the CK).")
    elseif cmdType == "scroll_invisibility"
        success = ExecuteGiveItem(ChaosScrollInvisibility, 1)
        resultMessage = FormatResult(success, viewer, "got a Scroll of Invisibility!", "scroll grant failed (check ChaosScrollInvisibility is set in the CK).")
    elseif cmdType == "scroll_mayhem"
        success = ExecuteGiveItem(ChaosScrollMayhem, 1)
        resultMessage = FormatResult(success, viewer, "got a Scroll of Mayhem!", "scroll grant failed (check ChaosScrollMayhem is set in the CK).")
    elseif cmdType == "scroll_storm_thrall"
        success = ExecuteGiveItem(ChaosScrollStormThrall, 1)
        resultMessage = FormatResult(success, viewer, "got a Scroll of Storm Thrall!", "scroll grant failed (check ChaosScrollStormThrall is set in the CK).")
    elseif cmdType == "scroll_water_breathing"
        success = ExecuteGiveItem(ChaosScrollWaterBreathing, 1)
        resultMessage = FormatResult(success, viewer, "got a Scroll of Water Breathing!", "scroll grant failed (check ChaosScrollWaterBreathing is set in the CK).")
    elseif cmdType == "yeet"
        success = ExecuteYeet()
        resultMessage = FormatResult(success, viewer, "yeeted a nearby NPC!", "yeet failed (no valid nearby target in view).")
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

; A bigger, pricier version of !buy cheese for viewers who want to go all in.
; Reuses the same ChaosCheeseItem1-4 pool, just far more of it.
bool Function ExecuteCheeseMageddon()
    Actor player = Game.GetPlayer()
    if !player
        return false
    endif

    Form[] cheeseForms = new Form[4]
    cheeseForms[0] = ChaosCheeseItem1
    cheeseForms[1] = ChaosCheeseItem2
    cheeseForms[2] = ChaosCheeseItem3
    cheeseForms[3] = ChaosCheeseItem4

    Form cheeseForm = None
    int attempts = 0
    while !cheeseForm && attempts < 10
        cheeseForm = cheeseForms[Utility.RandomInt(0, 3)]
        attempts += 1
    endwhile

    if !cheeseForm
        return false
    endif

    int count = Utility.RandomInt(60, 100)
    player.PlaceAtMe(cheeseForm, count)
    return true
EndFunction

; Shared by every !buy give*/scroll* command -- see the "Item/scroll grants"
; properties above. Kept as one function rather than 23 near-identical ones.
bool Function ExecuteGiveItem(Form itemForm, int quantity)
    Actor player = Game.GetPlayer()
    if !player || !itemForm
        return false
    endif
    player.AddItem(itemForm, quantity, true)
    return true
EndFunction

; Shared by !buy give10gold/give100gold/give1000gold -- reuses the same
; Gold001 property ExecuteGoldDelta() already uses.
bool Function ExecuteGiveGold(int amount)
    Actor player = Game.GetPlayer()
    if !player
        return false
    endif
    player.AddItem(Gold001, amount, true)
    return true
EndFunction

; Launches a random nearby NPC into a brief comedic ragdoll -- no CK
; property needed, target is picked live via the engine's own actor search.
bool Function ExecuteYeet()
    Actor player = Game.GetPlayer()
    if !player
        return false
    endif

    ; FindRandomActor can hand back the player, a corpse, or someone the
    ; player can't actually see get launched -- retry a few times rather
    ; than yeet blind, same retry-on-miss shape as the cheese pickers above.
    Actor target = None
    int attempts = 0
    while !target && attempts < 10
        Actor candidate = Game.FindRandomActor(player, 1500.0)
        if candidate && candidate != player && !candidate.IsDead() && candidate.HasLOS(player)
            target = candidate
        endif
        attempts += 1
    endwhile

    if !target
        return false
    endif

    ; 8-12 is a stumble/pop-into-the-air force, well below what causes real
    ; fall damage or counts as a lethal hit.
    player.PushActorAway(target, Utility.RandomFloat(8.0, 12.0))

    ; PushActorAway doesn't go through the crime/hostile-spell system, but
    ; the target's own AI can still read the shove as an attack and
    ; retaliate or alert nearby witnesses -- clear both explicitly so a yeet
    ; never turns into a bounty or a brawl.
    target.StopCombat()
    player.StopCombatAlarm()

    return true
EndFunction
