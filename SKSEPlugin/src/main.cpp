#include "PCH.h"

#include "Bridge/IPCServer.h"
#include "Bridge/MessageQueue.h"
#include "Hooks/EventSink.h"
#include "Papyrus/ChaosNativeFunctions.h"
#include "Settings/Settings.h"
#include "Update/UpdateChecker.h"

namespace
{
    constexpr auto kGitHubOwner = "musicman0917";
    constexpr auto kGitHubRepo = "ChatVsDragonborn";
    constexpr auto kPluginVersion = "0.1.0";

    void InitializeLogging()
    {
        auto path = SKSE::log::log_directory();
        if (!path) {
            return;
        }

        *path /= "SkyrimTwitchExpansion.log"sv;

        auto sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>(path->string(), true);
        auto log = std::make_shared<spdlog::logger>("global", std::move(sink));

        log->set_level(spdlog::level::info);
        log->flush_on(spdlog::level::info);

        spdlog::set_default_logger(std::move(log));
        spdlog::set_pattern("[%H:%M:%S] [%l] %v"s);
    }

    // Pushes deferred work (engine-event polling, update notifications) that
    // has to happen on the main/game thread — the only thread allowed to
    // touch RE:: types (see docs/ARCHITECTURE.md §3). SKSE's task queue has
    // no built-in "every frame" hook, so this task re-arms itself at the end
    // of each run, giving a lightweight perpetual per-frame tick.
    void OnMainThreadTick()
    {
        STE::Hooks::PollGameHour();

        if (const auto newVersion = STE::Update::TakePendingNotification()) {
            RE::DebugNotification("SkyrimTwitchExpansion update available!");
            logger::info("Notified player of update to v{}", *newVersion);
        }

        // Note: SkyrimChaosRouter.psc pulls inbound commands itself via
        // STE_Native.PollNextCommand(), so nothing to drain here for the
        // inbound queue — this tick only handles work the C++ side owns
        // directly (engine-event polling, update notifications, etc).

        if (auto* taskInterface = SKSE::GetTaskInterface()) {
            taskInterface->AddTask(&OnMainThreadTick);
        }
    }

    void MessageHandler(SKSE::MessagingInterface::Message* message)
    {
        switch (message->type) {
        case SKSE::MessagingInterface::kDataLoaded:
            {
                STE::Settings::Get().Load();
                STE::Hooks::RegisterAll();
                STE::Bridge::IPCServer::Get().Start();
                STE::Update::CheckForUpdatesAsync(kGitHubOwner, kGitHubRepo, kPluginVersion);

                if (auto* taskInterface = SKSE::GetTaskInterface()) {
                    taskInterface->AddTask(&OnMainThreadTick);
                }

                logger::info("kDataLoaded: subsystems started");
                break;
            }
        default:
            break;
        }
    }
}

SKSEPluginLoad(const SKSE::LoadInterface* skse)
{
    InitializeLogging();
    logger::info("SkyrimTwitchExpansion v{} loading", kPluginVersion);

    SKSE::Init(skse);

    if (auto* messaging = SKSE::GetMessagingInterface()) {
        messaging->RegisterListener(MessageHandler);
    }

    if (auto* papyrus = SKSE::GetPapyrusInterface()) {
        papyrus->Register(STE::Papyrus::Register);
    }

    return true;
}

extern "C" __declspec(dllexport) constinit auto SKSEPlugin_Version = []() {
    SKSE::PluginVersionData v;
    v.PluginVersion({ 0, 1, 0, 0 });
    v.PluginName("SkyrimTwitchExpansion");
    v.AuthorName("musicman0917");
    v.UsesAddressLibrary(true);
    v.UsesUpdatedStructs(true);
    v.CompatibleVersions({ SKSE::RUNTIME_LATEST });
    return v;
}();
