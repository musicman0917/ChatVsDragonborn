#include "Papyrus/ChaosNativeFunctions.h"

#include "Bridge/MessageQueue.h"
#include "Bridge/Protocol.h"
#include "Settings/Settings.h"

namespace STE::Papyrus
{
    namespace
    {
        constexpr auto kPapyrusObjectName = "STE_Native";

        // SkyrimChaosRouter.psc polls this on a short RegisterForSingleUpdate
        // loop. Returns an empty array when nothing is queued, otherwise
        // [id, type, viewer, priceAsString, argsAsJson] — Papyrus routes on
        // `type` and, if a handler needs more detail, re-parses `argsAsJson`
        // via PapyrusUtil's JsonUtil (already a dependency for MCM storage).
        std::vector<std::string> PollNextCommand(RE::StaticFunctionTag*)
        {
            auto cmd = Bridge::Queues::Get().inbound.PopOne();
            if (!cmd) {
                return {};
            }

            return {
                cmd->id,
                cmd->type,
                cmd->viewer,
                std::to_string(cmd->price),
                cmd->args.dump(),
            };
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
    }

    bool Register(RE::BSScript::IVirtualMachine* vm)
    {
        vm->RegisterFunction("PollNextCommand", kPapyrusObjectName, PollNextCommand);
        vm->RegisterFunction("ReportCommandResult", kPapyrusObjectName, ReportCommandResult);
        vm->RegisterFunction("GetSetting", kPapyrusObjectName, GetSetting);
        vm->RegisterFunction("SetSetting", kPapyrusObjectName, SetSetting);
        return true;
    }
}
