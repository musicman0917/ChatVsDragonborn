Scriptname STE_MCMConfig extends MCM_ConfigBase
{
  Bridges MCM Helper's own per-mod setting storage (the ModSettingInt
  sourceType used throughout Data/MCM/Config/SkyrimTwitchExpansion/
  config.json) into this mod's own shared settings store
  (STE_Native.GetSetting/SetSetting, backed by
  Data/SKSE/Plugins/SkyrimTwitchExpansion.json). MCM Helper persists its
  ModSettings to its own file under Data/MCM/Settings/ -- a separate store
  from ours -- so without this bridge, moving an MCM slider would change
  nothing the SKSE plugin or TwitchBridge actually reads. See
  SKSEPlugin/src/Settings/Settings.h for how a chaos.* change then reaches
  TwitchBridge over the pipe.

  Attach this as a SECOND script on the same quest SkyrimChaosRouter.psc is
  already attached to (a Quest form can carry more than one script) --
  MCM Helper finds this menu by "modName" in config.json, not by which
  quest hosts the script, so a dedicated quest isn't needed.
}

; ModName is a plain (non-readonly) Property inherited from SKI_ConfigBase --
; SkyUI's own registration code (SKI_ConfigBase.OnInit -> ... ->
; OnConfigManagerReady -> SKI_ConfigManager.RegisterMod) reads it to decide
; what name to register this menu under, and ConfigStore::ReadConfig then
; looks for Data/MCM/Config/<that name>/config.json. Set explicitly here
; rather than left for the Creation Kit's property editor: it defaults to an
; empty string, and the CK's own property UI for SkyUI-derived scripts is
; unreliable enough (see this session's history) that a wrong/stale value
; is easy to end up with by hand. parent.OnInit() must still run -- it's
; what registers the SKICP_configManagerReady listener in the first place.
Event OnInit()
    ModName = "SkyrimTwitchExpansion"
    Debug.Trace("STE_MCMConfig.OnInit: ModName set to '" + ModName + "' before calling parent.OnInit()")
    parent.OnInit()
    Debug.Trace("STE_MCMConfig.OnInit: ModName is '" + ModName + "' after parent.OnInit() returned")
EndEvent

; One entry per interactive control in config.json, mapping its "id" to the
; settings key STE_Native.GetSettingInt/GetSetting reads elsewhere. Kept as
; an if/elseif chain rather than a lookup table -- Papyrus has no Dictionary
; type, and the list is short enough that this reads fine.
Event OnSettingChange(string a_ID)
    if a_ID == "iRagdollPrice:ChaosPrices"
        STE_Native.SetSetting("chaos.ragdoll.price", GetModSettingInt(a_ID) as String)
    elseif a_ID == "iEarthquakePrice:ChaosPrices"
        STE_Native.SetSetting("chaos.earthquake.price", GetModSettingInt(a_ID) as String)
    elseif a_ID == "iDragonPrice:ChaosPrices"
        STE_Native.SetSetting("chaos.spawn_dragon.price", GetModSettingInt(a_ID) as String)
    elseif a_ID == "iChickensPrice:ChaosPrices"
        STE_Native.SetSetting("chaos.spawn_chickens.price", GetModSettingInt(a_ID) as String)
    elseif a_ID == "iCheesePrice:ChaosPrices"
        STE_Native.SetSetting("chaos.spawn_cheese.price", GetModSettingInt(a_ID) as String)
    elseif a_ID == "iAddGoldPrice:ChaosPrices"
        STE_Native.SetSetting("chaos.add_gold.price", GetModSettingInt(a_ID) as String)
    elseif a_ID == "iRemoveGoldPrice:ChaosPrices"
        STE_Native.SetSetting("chaos.remove_gold.price", GetModSettingInt(a_ID) as String)
    elseif a_ID == "iInvertPrice:ChaosPrices"
        STE_Native.SetSetting("chaos.invert_controls.price", GetModSettingInt(a_ID) as String)
    elseif a_ID == "iLowGravityPrice:ChaosPrices"
        STE_Native.SetSetting("chaos.low_gravity.price", GetModSettingInt(a_ID) as String)
    elseif a_ID == "iAddGoldAmount:GoldAmounts"
        STE_Native.SetSetting("chaos.add_gold.amount", GetModSettingInt(a_ID) as String)
    elseif a_ID == "iRemoveGoldAmount:GoldAmounts"
        STE_Native.SetSetting("chaos.remove_gold.amount", GetModSettingInt(a_ID) as String)
    elseif a_ID == "iInvertDuration:Timers"
        STE_Native.SetSetting("chaos.invert_controls.duration_seconds", GetModSettingInt(a_ID) as String)
    elseif a_ID == "iLowGravityDuration:Timers"
        STE_Native.SetSetting("chaos.low_gravity.duration_seconds", GetModSettingInt(a_ID) as String)
    elseif a_ID == "iPollInterval:Timers"
        STE_Native.SetSetting("poll.interval_minutes", GetModSettingInt(a_ID) as String)
    elseif a_ID == "iPollDuration:Timers"
        STE_Native.SetSetting("poll.duration_seconds", GetModSettingInt(a_ID) as String)
    endif
EndEvent
