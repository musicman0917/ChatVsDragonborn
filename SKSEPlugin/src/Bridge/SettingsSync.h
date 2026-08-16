#pragma once

#include "Bridge/MessageQueue.h"
#include "Bridge/Protocol.h"
#include "Settings/Settings.h"

namespace STE::Bridge
{
    // Pushes the current chaos.* settings (prices, gold amounts, effect
    // durations) as a "settings_sync" OutboundEvent -- see Settings.h's
    // class comment for why the plugin pushes these over the pipe instead
    // of TwitchBridge reading the settings JSON file directly. Called on
    // every TwitchBridge (re)connect and whenever SetSetting changes a
    // chaos.* key, so MCM edits reach TwitchBridge live.
    inline void PushSettingsSyncEvent()
    {
        OutboundEvent evt;
        evt.kind = "settings_sync";
        evt.data = Settings::Get().GetAllWithPrefix("chaos.");
        Queues::Get().outbound.Push(std::move(evt));
    }
}
