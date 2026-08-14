#pragma once

namespace STE::Bridge
{
    // Owns the named-pipe connection to TwitchBridge. Runs its own reader
    // thread and its own writer thread; neither ever calls into CommonLibSSE
    // or touches game state directly — they only move JSON lines in and out
    // of the shared Queues (see MessageQueue.h).
    class IPCServer
    {
    public:
        static IPCServer& Get()
        {
            static IPCServer instance;
            return instance;
        }

        // Starts the reader/writer threads. Safe to call once, typically from
        // SKSEPluginLoad after SKSE::Init.
        void Start();

        // Signals both threads to exit and joins them. Called on plugin
        // teardown / kPreLoadGame if we ever need a clean restart.
        void Stop();

        [[nodiscard]] bool IsConnected() const { return _connected.load(); }

    private:
        IPCServer() = default;
        ~IPCServer() { Stop(); }
        IPCServer(const IPCServer&) = delete;
        IPCServer& operator=(const IPCServer&) = delete;

        void ReaderThreadMain();
        void WriterThreadMain();

        std::atomic<bool> _running{ false };
        std::atomic<bool> _connected{ false };
        std::thread _readerThread;
        std::thread _writerThread;
        void* _pipeHandle = nullptr;  // HANDLE, opaque here to keep Win32 out of the header
    };
}
