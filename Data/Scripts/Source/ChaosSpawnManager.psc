Scriptname ChaosSpawnManager extends Quest
{
  Safe-spawn helpers for chaos effects that place actors near the player.
  Called from SkyrimChaosRouter as global functions. Phase 3 of
  docs/IMPLEMENTATION_PLAN.md fleshes these out with real cell/interior
  safety checks; this is the stub call shape the router already expects.
}

LeveledActor Property ChaosDragonLeveledActor Auto
Actor Property ChaosChickenBase Auto

Actor Function SpawnHostileDragon(Actor akPlayer, EncounterZone akZone) global
    if !akPlayer || !ChaosDragonLeveledActor
        return None
    endif

    ObjectReference spawnMarker = FindSafeSpawnPoint(akPlayer)
    if !spawnMarker
        return None
    endif

    Actor dragon = spawnMarker.PlaceActorAtMe(ChaosDragonLeveledActor) as Actor
    if dragon && akZone
        dragon.SetEncounterZone(akZone)
    endif
    return dragon
EndFunction

int Function SpawnChickenSwarm(Actor akPlayer, int count) global
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
ObjectReference Function FindSafeSpawnPoint(Actor akPlayer) global
    return akPlayer
EndFunction
