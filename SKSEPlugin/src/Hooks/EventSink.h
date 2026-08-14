#pragma once

namespace STE::Hooks
{
    // Native CommonLibSSE event sinks — the "engine events" half of the data
    // flow in docs/ARCHITECTURE.md §2. These observe the game directly
    // (OnPlayerHit, spell casts, GameHour ticks) instead of relying on
    // Papyrus polling, and forward notable events out through
    // Bridge::Queues::outbound so TwitchBridge/chat can react to them.
    class PlayerHitSink final : public RE::BSTEventSink<RE::TESHitEvent>
    {
    public:
        static PlayerHitSink* GetSingleton()
        {
            static PlayerHitSink instance;
            return &instance;
        }

        RE::BSEventNotifyControl ProcessEvent(const RE::TESHitEvent* event, RE::BSTEventSource<RE::TESHitEvent>*) override;
    };

    class SpellCastSink final : public RE::BSTEventSink<RE::TESSpellCastEvent>
    {
    public:
        static SpellCastSink* GetSingleton()
        {
            static SpellCastSink instance;
            return &instance;
        }

        RE::BSEventNotifyControl ProcessEvent(const RE::TESSpellCastEvent* event, RE::BSTEventSource<RE::TESSpellCastEvent>*) override;
    };

    // Registers all sinks with their respective event sources. Call once
    // from SKSEPluginLoad after kDataLoaded.
    void RegisterAll();

    // Polls RE::Calendar for game-hour rollover and forwards a lightweight
    // "engine_event" (type = "game_hour") once per in-game hour. Intended to
    // be called from the main-thread per-frame task alongside
    // MessageQueue::PopAll draining.
    void PollGameHour();
}
