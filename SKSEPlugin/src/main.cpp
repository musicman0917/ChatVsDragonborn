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

    void MessageHandler(SKSE::MessagingInterface::Message* message)
    {
        switch (message->type) {
        case SKSE::MessagingInterface::kDataLoaded:
            {
                STE::Settings::Get().Load();
                STE::Hooks::RegisterAll();
                STE::Bridge::IPCServer::Get().Start();
                STE::Update::CheckForUpdatesAsync(kGitHubOwner, kGitHubRepo, kPluginVersion);

                // NOTE: engine-hour polling (Hooks::PollGameHour) and surfacing
                // update notifications (Update::TakePendingNotification) both
                // need to run repeatedly on the main thread, but they're
                // deliberately not wired up yet. The obvious approach —
                // SKSE::GetTaskInterface()->AddTask() re-adding itself at the
                // end of each run to fake a per-frame tick — hung the game at
                // the main menu the one time it was tried live: AddTask's
                // queue-draining behavior when a task re-adds itself was never
                // actually verified against SKSE's source, and it's plausible
                // newly-added tasks get processed within the same drain pass
                // rather than deferred to the next frame, producing a tight
                // synchronous loop with no chance to render. A real per-frame
                // hook (e.g. via Xbyak/trampoline on the main update loop —
                // see SKSE_SUPPORT_XBYAK in CMakePresets.json, currently off)
                // is needed before either of these features comes back.

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
    v.UsesStructsPost629(true);
    // Leaving CompatibleVersions() unset (rather than listing specific
    // versions) is the standard idiom for an address-library-only plugin:
    // it signals "compatible with every runtime version" instead of
    // needing a recompile whenever Skyrim patches.
    return v;
}();
