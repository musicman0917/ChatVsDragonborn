#include "Hooks/EventSink.h"

#include "Bridge/MessageQueue.h"
#include "Bridge/Protocol.h"

namespace STE::Hooks
{
    namespace
    {
        void PushEngineEvent(std::string type, json::json data)
        {
            Bridge::OutboundEvent evt;
            evt.kind = "engine_event";
            evt.message = std::move(type);
            evt.data = std::move(data);
            evt.success = true;
            Bridge::Queues::Get().outbound.Push(std::move(evt));
        }
    }

    RE::BSEventNotifyControl PlayerHitSink::ProcessEvent(const RE::TESHitEvent* event, RE::BSTEventSource<RE::TESHitEvent>*)
    {
        if (!event || !event->target || !event->target->IsPlayerRef()) {
            return RE::BSEventNotifyControl::kContinue;
        }

        PushEngineEvent("player_hit", json::json{
                                           { "aggressor", event->cause ? event->cause->GetName() : "unknown" },
                                       });

        return RE::BSEventNotifyControl::kContinue;
    }

    RE::BSEventNotifyControl SpellCastSink::ProcessEvent(const RE::TESSpellCastEvent* event, RE::BSTEventSource<RE::TESSpellCastEvent>*)
    {
        if (!event || !event->object || !event->object->IsPlayerRef()) {
            return RE::BSEventNotifyControl::kContinue;
        }

        const auto* spell = RE::TESForm::LookupByID<RE::SpellItem>(event->spell);
        PushEngineEvent("player_spell_cast", json::json{
                                                  { "spell", spell ? spell->GetName() : "unknown" },
                                              });

        return RE::BSEventNotifyControl::kContinue;
    }

    void RegisterAll()
    {
        if (auto* source = RE::ScriptEventSourceHolder::GetSingleton()) {
            source->AddEventSink(PlayerHitSink::GetSingleton());
            source->AddEventSink(SpellCastSink::GetSingleton());
        }
        logger::info("Hooks::RegisterAll: engine event sinks registered");
    }

    void PollGameHour()
    {
        static float lastHour = -1.f;

        auto* calendar = RE::Calendar::GetSingleton();
        if (!calendar) {
            return;
        }

        const float hour = calendar->GetHour();
        if (lastHour < 0.f) {
            lastHour = hour;
            return;
        }

        // Fired once per rollover, including wrap-around at midnight.
        if (static_cast<int>(hour) != static_cast<int>(lastHour)) {
            PushEngineEvent("game_hour", json::json{ { "hour", static_cast<int>(hour) } });
        }
        lastHour = hour;
    }
}
