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

; --- Physics & magic --------------------------------------------------------

Spell Property ChaosDrunkSpell Auto
{ A spell that applies a drunk-style visual distort/wobble to the player for
  !buy drunkvision -- e.g. the vanilla Skooma "high" effect, or a custom
  spell built around an ImageSpace Modifier of your choosing. Cast directly
  on the player; its own magic effect duration governs how long the effect
  lasts, so no separate timer is needed here (same as drinking any real
  in-game potion). }
Spell Property ChaosWildSpell1 Auto
Spell Property ChaosWildSpell2 Auto
Spell Property ChaosWildSpell3 Auto
{ Three high-cost offensive spells for !buy wildmagic -- e.g. the vanilla
  Fireball, Chain Lightning, and Ice Storm. One is picked at random and cast
  at a random nearby actor (same target-finding as !buy yeet). }
MiscObject Property ChaosMidasOre Auto
{ A heavy MiscObject to swap the Dragonborn's gold into for !buy
  midasweight -- e.g. the vanilla Iron Ore, so a big gold pile becomes a
  genuinely heavy problem. }

; --- Lifecycle --------------------------------------------------------------

; Plain (non-Property) fields for Super Jump/scale-effect revert bookkeeping
; -- deliberately not Auto properties, since the CK's Properties dialog has
; no business exposing pure runtime state that only this script ever reads
; or writes. Checked every poll tick in OnUpdate() below rather than via a
; second RegisterForSingleUpdate timer, since that would fire the same
; OnUpdate() event this script already uses for command polling and the two
; purposes would collide.
float _superJumpRevertAt = 0.0
bool _superJumpActive = false
float _origJumpHeightMin = 0.0

float _scaleRevertAt = 0.0
bool _scaleActive = false
float _origScale = 1.0

Event OnInit()
    RegisterForSingleUpdate(PollIntervalSeconds)
EndEvent

Event OnUpdate()
    string[] command = STE_Native.PollNextCommand()
    if command.Length > 0
        RouteCommand(command)
    endif

    float now = Utility.GetCurrentRealTime()
    if _superJumpActive && now >= _superJumpRevertAt
        RevertSuperJump()
    endif
    if _scaleActive && now >= _scaleRevertAt
        RevertScale()
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
;                       "scroll_water_breathing" | "yeet" | "super_jump" |
;                       "ragdoll_blast" | "tiny_dovahkiin" | "giant_dovahkiin" |
;                       "drunk_vision" | "wild_magic" | "midas_weight" |
;                       "pocket_change_blast")
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
    elseif cmdType == "super_jump"
        success = ExecuteSuperJump()
        resultMessage = FormatResult(success, viewer, "gave the Dragonborn moon legs!", "super jump failed (already active).")
    elseif cmdType == "ragdoll_blast"
        success = ExecuteRagdollBlast()
        resultMessage = FormatResult(success, viewer, "sent nearby NPCs stumbling!", "ragdoll blast failed (no valid nearby targets in view).")
    elseif cmdType == "tiny_dovahkiin"
        success = ExecuteSetScale(0.25)
        resultMessage = FormatResult(success, viewer, "shrunk the Dragonborn down to size!", "tiny Dovahkiin failed (a scale effect is already active).")
    elseif cmdType == "giant_dovahkiin"
        success = ExecuteSetScale(3.0)
        resultMessage = FormatResult(success, viewer, "grew the Dragonborn into a giant!", "giant Dovahkiin failed (a scale effect is already active).")
    elseif cmdType == "drunk_vision"
        success = ExecuteDrunkVision()
        resultMessage = FormatResult(success, viewer, "got the Dragonborn seeing double!", "drunk vision failed (check ChaosDrunkSpell is set in the CK).")
    elseif cmdType == "wild_magic"
        success = ExecuteWildMagic()
        resultMessage = FormatResult(success, viewer, "unleashed wild magic!", "wild magic failed (check ChaosWildSpell1-3 are set in the CK, and that a target was in view).")
    elseif cmdType == "midas_weight"
        success = ExecuteMidasWeight()
        resultMessage = FormatResult(success, viewer, "turned the Dragonborn's gold to ore!", "midas weight failed (check ChaosMidasOre is set in the CK, and the Dragonborn was carrying gold).")
    elseif cmdType == "pocket_change_blast"
        success = ExecutePocketChangeBlast()
        resultMessage = FormatResult(success, viewer, "spilled the Dragonborn's gold everywhere!", "pocket change blast failed (the Dragonborn wasn't carrying any gold).")
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

; Pushes fJumpHeightMin way up for a timed window, then restores whatever
; value it actually found (not a hardcoded default -- respects any other
; mod already touching this setting). Refuses to re-trigger while already
; active so a second buy mid-effect can't leak the original value.
bool Function ExecuteSuperJump()
    if _superJumpActive
        return false
    endif

    _origJumpHeightMin = Game.GetGameSettingFloat("fJumpHeightMin")
    Game.SetGameSettingFloat("fJumpHeightMin", _origJumpHeightMin * 4.0)
    _superJumpActive = true

    int durationSeconds = STE_Native.GetSettingInt("chaos.super_jump.duration_seconds", 20)
    _superJumpRevertAt = Utility.GetCurrentRealTime() + durationSeconds
    return true
EndFunction

Function RevertSuperJump()
    Game.SetGameSettingFloat("fJumpHeightMin", _origJumpHeightMin)
    _superJumpActive = false
EndFunction

; A small-radius, low-force version of !buy yeet that flops several nearby
; NPCs at once instead of launching one far -- same StopCombat/
; StopCombatAlarm cleanup so it doesn't start a fight or a bounty.
bool Function ExecuteRagdollBlast()
    Actor player = Game.GetPlayer()
    if !player
        return false
    endif

    Actor[] hit = new Actor[5]
    int hitCount = 0
    int attempts = 0
    while hitCount < 5 && attempts < 20
        Actor candidate = Game.FindRandomActor(player, 800.0)
        if candidate && candidate != player && !candidate.IsDead() && !AlreadyHit(hit, hitCount, candidate)
            hit[hitCount] = candidate
            hitCount += 1
        endif
        attempts += 1
    endwhile

    if hitCount == 0
        return false
    endif

    int i = 0
    while i < hitCount
        player.PushActorAway(hit[i], 3.0)
        hit[i].StopCombat()
        i += 1
    endwhile
    player.StopCombatAlarm()

    return true
EndFunction

bool Function AlreadyHit(Actor[] hit, int count, Actor candidate)
    int i = 0
    while i < count
        if hit[i] == candidate
            return true
        endif
        i += 1
    endwhile
    return false
EndFunction

; Shared by !buy tinydovahkiin (0.25) and !buy giantdovahkiin (3.0).
; Refuses to stack a second scale change mid-effect for the same reason as
; ExecuteSuperJump -- the original scale would otherwise be lost.
bool Function ExecuteSetScale(float scale)
    if _scaleActive
        return false
    endif

    Actor player = Game.GetPlayer()
    if !player
        return false
    endif

    _origScale = player.GetScale()
    player.SetScale(scale)
    _scaleActive = true

    int durationSeconds = STE_Native.GetSettingInt("chaos.scale_effect.duration_seconds", 20)
    _scaleRevertAt = Utility.GetCurrentRealTime() + durationSeconds
    return true
EndFunction

Function RevertScale()
    Actor player = Game.GetPlayer()
    if player
        player.SetScale(_origScale)
    endif
    _scaleActive = false
EndFunction

; Casts ChaosDrunkSpell directly on the player -- the spell's own magic
; effect duration governs how long it lasts, same as drinking a real potion,
; so there's no separate revert timer to manage here.
bool Function ExecuteDrunkVision()
    Actor player = Game.GetPlayer()
    if !player || !ChaosDrunkSpell
        return false
    endif
    player.Cast(ChaosDrunkSpell, player)
    return true
EndFunction

; Picks one of three configured high-cost spells at random and casts it at a
; random nearby actor -- reuses the exact target-finding retry loop from
; ExecuteYeet() so it can't hit the player or an actor with no line of sight.
bool Function ExecuteWildMagic()
    Actor player = Game.GetPlayer()
    if !player
        return false
    endif

    Spell[] wildSpells = new Spell[3]
    wildSpells[0] = ChaosWildSpell1
    wildSpells[1] = ChaosWildSpell2
    wildSpells[2] = ChaosWildSpell3

    Spell chosenSpell = None
    int spellAttempts = 0
    while !chosenSpell && spellAttempts < 10
        chosenSpell = wildSpells[Utility.RandomInt(0, 2)]
        spellAttempts += 1
    endwhile

    if !chosenSpell
        return false
    endif

    Actor target = None
    int targetAttempts = 0
    while !target && targetAttempts < 10
        Actor candidate = Game.FindRandomActor(player, 1500.0)
        if candidate && candidate != player && !candidate.IsDead() && candidate.HasLOS(player)
            target = candidate
        endif
        targetAttempts += 1
    endwhile

    if !target
        return false
    endif

    player.Cast(chosenSpell, target)
    return true
EndFunction

; Empties the Dragonborn's gold and replaces it 1-for-1 with ChaosMidasOre --
; a big gold pile becomes a genuinely heavy problem instead of dead weight
; disappearing quietly.
bool Function ExecuteMidasWeight()
    Actor player = Game.GetPlayer()
    if !player || !Gold001 || !ChaosMidasOre
        return false
    endif

    int goldCount = player.GetItemCount(Gold001)
    if goldCount <= 0
        return false
    endif

    player.RemoveItem(Gold001, goldCount, true)
    player.AddItem(ChaosMidasOre, goldCount, true)
    return true
EndFunction

; Drops the Dragonborn's entire gold count on the ground as a physics
; object, same as manually dropping an inventory stack -- no CK property
; needed, reuses Gold001.
bool Function ExecutePocketChangeBlast()
    Actor player = Game.GetPlayer()
    if !player || !Gold001
        return false
    endif

    int goldCount = player.GetItemCount(Gold001)
    if goldCount <= 0
        return false
    endif

    player.DropObject(Gold001, goldCount)
    return true
EndFunction
