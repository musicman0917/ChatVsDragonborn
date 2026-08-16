#include "Bridge/IPCServer.h"

#include "Bridge/MessageQueue.h"
#include "Bridge/Protocol.h"
#include "Bridge/SettingsSync.h"

#include <Windows.h>

namespace STE::Bridge
{
    namespace
    {
        constexpr auto kPipeName = R"(\\.\pipe\SkyrimTwitchExpansion)";
        constexpr DWORD kBufferSize = 64 * 1024;
    }

    void IPCServer::Start()
    {
        if (_running.exchange(true)) {
            return;  // already running
        }

        _readerThread = std::thread([this] { ReaderThreadMain(); });
        _writerThread = std::thread([this] { WriterThreadMain(); });

        logger::info("IPCServer started, listening on {}", kPipeName);
    }

    void IPCServer::Stop()
    {
        if (!_running.exchange(false)) {
            return;
        }

        if (_pipeHandle) {
            CancelIoEx(_pipeHandle, nullptr);
        }

        if (_readerThread.joinable()) {
            _readerThread.join();
        }
        if (_writerThread.joinable()) {
            _writerThread.join();
        }

        if (_pipeHandle) {
            CloseHandle(static_cast<HANDLE>(_pipeHandle));
            _pipeHandle = nullptr;
        }
    }

    void IPCServer::ReaderThreadMain()
    {
        while (_running.load()) {
            HANDLE pipe = CreateNamedPipeA(
                kPipeName,
                PIPE_ACCESS_DUPLEX,
                PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT,
                1,  // one TwitchBridge instance at a time
                kBufferSize,
                kBufferSize,
                0,
                nullptr);

            if (pipe == INVALID_HANDLE_VALUE) {
                logger::error("CreateNamedPipeA failed: {}", GetLastError());
                std::this_thread::sleep_for(2s);
                continue;
            }

            _pipeHandle = pipe;

            const bool connected = ConnectNamedPipe(pipe, nullptr) ? true : (GetLastError() == ERROR_PIPE_CONNECTED);
            if (!_running.load()) {
                CloseHandle(pipe);
                break;
            }
            if (!connected) {
                CloseHandle(pipe);
                continue;
            }

            _connected.store(true);
            logger::info("TwitchBridge connected");
            PushSettingsSyncEvent();

            std::string lineBuffer;
            std::vector<char> readBuf(kBufferSize);
            while (_running.load()) {
                DWORD bytesRead = 0;
                const BOOL ok = ReadFile(pipe, readBuf.data(), static_cast<DWORD>(readBuf.size()), &bytesRead, nullptr);
                if (!ok || bytesRead == 0) {
                    break;  // disconnect or shutdown
                }

                lineBuffer.append(readBuf.data(), bytesRead);

                size_t newlinePos;
                while ((newlinePos = lineBuffer.find('\n')) != std::string::npos) {
                    std::string line = lineBuffer.substr(0, newlinePos);
                    lineBuffer.erase(0, newlinePos + 1);
                    if (line.empty()) {
                        continue;
                    }

                    try {
                        const auto parsed = json::json::parse(line);
                        Queues::Get().inbound.Push(ChaosCommand::FromJson(parsed));
                    } catch (const std::exception& e) {
                        logger::warn("Failed to parse inbound pipe line: {}", e.what());
                    }
                }
            }

            _connected.store(false);
            DisconnectNamedPipe(pipe);
            CloseHandle(pipe);
            _pipeHandle = nullptr;
            logger::info("TwitchBridge disconnected, waiting for reconnect");
        }
    }

    void IPCServer::WriterThreadMain()
    {
        // Flushes outbound command-result / engine-event JSON lines whenever
        // present. The reader thread owns the live HANDLE; this thread only
        // writes to it while connected, which is safe for a duplex named pipe
        // with a single client.
        while (_running.load()) {
            if (!_connected.load() || !_pipeHandle) {
                std::this_thread::sleep_for(100ms);
                continue;
            }

            auto events = Queues::Get().outbound.PopAll();
            for (const auto& evt : events) {
                const std::string line = evt.ToJson().dump() + "\n";
                DWORD written = 0;
                if (!WriteFile(static_cast<HANDLE>(_pipeHandle), line.data(), static_cast<DWORD>(line.size()), &written, nullptr)) {
                    logger::warn("WriteFile to pipe failed: {}", GetLastError());
                    break;
                }
            }

            std::this_thread::sleep_for(50ms);
        }
    }
}
