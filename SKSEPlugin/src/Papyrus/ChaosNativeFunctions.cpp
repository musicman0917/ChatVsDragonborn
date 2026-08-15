#include "Papyrus/ChaosNativeFunctions.h"

#include "Bridge/MessageQueue.h"
#include "Bridge/Protocol.h"
#include "Settings/Settings.h"

namespace STE::Papyrus
{
    namespace
    {
        constexpr auto kPapyrusObjectName = "STE_Native";

        // Holds the args payload of whichever ChaosCommand PollNextCommand
        // most recently popped, so GetCommandArgInt can hand Papyrus an
        // already-typed int without Papyrus ever touching raw JSON itself.
        // Only ever read/written from the Papyrus VM tick (main thread), so
        // no extra locking is needed beyond what MessageQueue already does.
        json::json g_lastCommandArgs = json::json::object();

        // SkyrimChaosRouter.psc polls this on a short RegisterForSingleUpdate
        // loop. Returns an empty array when nothing is queued, otherwise
        // [id, type, viewer, priceAsString] — Papyrus routes on `type` and,
        // if a handler needs a numeric arg, calls GetCommandArgInt below
        // rather than parsing JSON itself.
        std::vector<std::string> PollNextCommand(RE::StaticFunctionTag*)
        {
            auto cmd = Bridge::Queues::Get().inbound.PopOne();
            if (!cmd) {
                g_lastCommandArgs = json::json::object();
                return {};
            }

            g_lastCommandArgs = cmd->args;

            return {
                cmd->id,
                cmd->type,
                cmd->viewer,
                std::to_string(cmd->price),
            };
        }

        // Reads a single integer arg out of the most recently popped
        // command's payload (e.g. "count" for spawn_chickens, "amount" for
        // add_gold/remove_gold).
        int GetCommandArgInt(RE::StaticFunctionTag*, std::string key, int missingValue)
        {
            return g_lastCommandArgs.value(key, missingValue);
        }

        // Called by the router after a handler finishes, so TwitchBridge can
        // show a success/failure toast and, on failure, refund the viewer.
        void ReportCommandResult(RE::StaticFunctionTag*, std::string id, bool success, std::string message)
        {
            Bridge::OutboundEvent evt;
            evt.kind = "command_result";
            evt.id = std::move(id);
            evt.success = success;
            evt.message = std::move(message);
            Bridge::Queues::Get().outbound.Push(std::move(evt));
        }

        // Backing store for MCM: prices, cooldowns, poll interval, per-effect
        // enable flags. Persisted to the same live-editable JSON file the
        // TwitchBridge process also reads, so edits apply without a restart.
        std::string GetSetting(RE::StaticFunctionTag*, std::string key)
        {
            return Settings::Get().GetString(key);
        }

        void SetSetting(RE::StaticFunctionTag*, std::string key, std::string value)
        {
            Settings::Get().SetString(key, value);
        }

        int GetSettingInt(RE::StaticFunctionTag*, std::string key, int missingValue)
        {
            return Settings::Get().GetInt(key, missingValue);
        }
    }

    bool Register(RE::BSScript::IVirtualMachine* vm)
    {
        vm->RegisterFunction("PollNextCommand", kPapyrusObjectName, PollNextCommand);
        vm->RegisterFunction("GetCommandArgInt", kPapyrusObjectName, GetCommandArgInt);
        vm->RegisterFunction("ReportCommandResult", kPapyrusObjectName, ReportCommandResult);
        vm->RegisterFunction("GetSetting", kPapyrusObjectName, GetSetting);
        vm->RegisterFunction("SetSetting", kPapyrusObjectName, SetSetting);
        vm->RegisterFunction("GetSettingInt", kPapyrusObjectName, GetSettingInt);
        return true;
    }
}
