#pragma once

// Wire protocol shared (conceptually) with TwitchBridge/Models/ChaosCommand.cs.
// Transport: one JSON object per line ("\n"-terminated) over the named pipe
// \\.\pipe\SkyrimTwitchExpansion. Keep both sides in sync manually — there is
// no shared IDL step in this scaffold.

namespace STE::Bridge
{
    // Inbound: TwitchBridge -> SKSE plugin. A single chaos effect to execute.
    struct ChaosCommand
    {
        std::string id;      // GUID assigned by TwitchBridge, echoed back in acks
        std::string type;    // "ragdoll" | "spawn_dragon" | "spawn_chickens" |
                              // "earthquake" | "invert_controls" | "add_gold" |
                              // "remove_gold" | "low_gravity" | ...
        std::string viewer;  // Twitch display name that triggered it
        int price = 0;       // points spent (0 for free/poll-winner commands)
        json::json args = json::json::object();  // effect-specific payload

        static ChaosCommand FromJson(const json::json& j)
        {
            ChaosCommand cmd;
            cmd.id = j.value("id", std::string{});
            cmd.type = j.value("type", std::string{});
            cmd.viewer = j.value("viewer", std::string{});
            cmd.price = j.value("price", 0);
            if (j.contains("args")) {
                cmd.args = j.at("args");
            }
            return cmd;
        }
    };

    // Outbound: SKSE plugin -> TwitchBridge. Result of executing a ChaosCommand,
    // or a native engine event (OnPlayerHit, GameHour, ...) surfaced to chat.
    struct OutboundEvent
    {
        std::string kind;  // "command_result" | "engine_event"
        std::string id;    // ChaosCommand::id when kind == "command_result"
        bool success = false;
        std::string message;
        json::json data = json::json::object();

        json::json ToJson() const
        {
            return json::json{
                { "kind", kind },
                { "id", id },
                { "success", success },
                { "message", message },
                { "data", data },
            };
        }
    };
}
