Scriptname ChaosSpawnManager extends Quest
{
  Safe-spawn helpers for chaos effects that place actors near the player.
  SkyrimChaosRouter holds a Property pointing at the attached instance of
  this script and calls these as instance methods — they can't be global
  functions because global functions have no `self` and therefore can't
  read the ChaosDragonLeveledActor / ChaosChickenBase Properties below.
  Phase 3 of docs/IMPLEMENTATION_PLAN.md fleshes these out with real
  cell/interior safety checks; this is the stub call shape the router
  already expects.
}

LeveledActor Property ChaosDragonLeveledActor Auto
ActorBase Property ChaosChickenBase Auto
{ An NPC_ record (e.g. the vanilla "Chicken" ActorBase) — PlaceActorAtMe
  needs an ActorBase template, not a placed Actor reference. }

Actor Function SpawnHostileDragon(Actor akPlayer, EncounterZone akZone)
    if !akPlayer || !ChaosDragonLeveledActor
        return None
    endif

    ObjectReference spawnMarker = FindSafeSpawnPoint(akPlayer)
    if !spawnMarker
        return None
    endif

    ; ChaosDragonLeveledActor is a LeveledActor, not an ActorBase, so this
    ; has to go through PlaceAtMe (which takes any Form and resolves leveled
    ; lists) rather than PlaceActorAtMe (which requires a concrete
    ; ActorBase template and can't accept a leveled list).
    ;
    ; NOTE: there is no Papyrus-native way to assign an EncounterZone to a
    ; runtime-placed actor, so akZone is accepted here for a future native
    ; STE_Native helper (see docs/IMPLEMENTATION_PLAN.md) rather than used
    ; directly yet.
    Actor dragon = spawnMarker.PlaceAtMe(ChaosDragonLeveledActor) as Actor
    return dragon
EndFunction

int Function SpawnChickenSwarm(Actor akPlayer, int count)
    if !akPlayer || !ChaosChickenBase
        return 0
    endif

    ObjectReference spawnMarker = FindSafeSpawnPoint(akPlayer)
    if !spawnMarker
        return 0
    endif

    int spawned = 0
    int i = 0
    while i < count
        if spawnMarker.PlaceActorAtMe(ChaosChickenBase)
            spawned += 1
        endif
        i += 1
    endwhile
    return spawned
EndFunction

; Placeholder for the interior/cell-safety logic called out as an open risk
; in docs/IMPLEMENTATION_PLAN.md ("Spawn safety"). For now this just returns
; the player ref itself as the spawn origin.
ObjectReference Function FindSafeSpawnPoint(Actor akPlayer)
    return akPlayer
EndFunction
