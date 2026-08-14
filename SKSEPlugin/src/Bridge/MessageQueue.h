#pragma once

#include "Bridge/Protocol.h"

namespace STE::Bridge
{
    // Thread-safe FIFO used to hop data between the IPC reader thread and the
    // Skyrim main/game thread. No engine calls happen here — this is a plain
    // data handoff, per the threading rules in docs/ARCHITECTURE.md.
    template <typename T>
    class MessageQueue
    {
    public:
        void Push(T item)
        {
            std::lock_guard lock(_mutex);
            _queue.push_back(std::move(item));
        }

        // Drains and returns everything currently queued. Intended to be called
        // once per frame/tick from the main thread.
        [[nodiscard]] std::vector<T> PopAll()
        {
            std::vector<T> drained;
            std::lock_guard lock(_mutex);
            drained.reserve(_queue.size());
            std::move(_queue.begin(), _queue.end(), std::back_inserter(drained));
            _queue.clear();
            return drained;
        }

        [[nodiscard]] std::optional<T> PopOne()
        {
            std::lock_guard lock(_mutex);
            if (_queue.empty()) {
                return std::nullopt;
            }
            T item = std::move(_queue.front());
            _queue.pop_front();
            return item;
        }

        [[nodiscard]] bool Empty() const
        {
            std::lock_guard lock(_mutex);
            return _queue.empty();
        }

    private:
        mutable std::mutex _mutex;
        std::deque<T> _queue;
    };

    // Inbound commands waiting to be polled by Papyrus, and outbound events
    // waiting to be flushed to the pipe writer. Declared here so both
    // IPCServer and ChaosNativeFunctions can share the same instances via
    // STE::Bridge::Queues::Get().
    class Queues
    {
    public:
        static Queues& Get()
        {
            static Queues instance;
            return instance;
        }

        MessageQueue<ChaosCommand> inbound;
        MessageQueue<OutboundEvent> outbound;

    private:
        Queues() = default;
    };
}
