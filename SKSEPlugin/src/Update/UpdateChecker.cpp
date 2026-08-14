#include "Update/UpdateChecker.h"

#include <Windows.h>
#include <winhttp.h>

namespace STE::Update
{
    namespace
    {
        std::mutex g_pendingMutex;
        std::optional<std::string> g_pendingVersion;

        // Minimal blocking WinHTTP GET; runs entirely on the caller's
        // background thread, never the main thread.
        std::optional<std::string> HttpsGet(std::wstring_view host, std::wstring_view path)
        {
            HINTERNET session = WinHttpOpen(
                L"SkyrimTwitchExpansion-UpdateChecker/1.0",
                WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                WINHTTP_NO_PROXY_NAME,
                WINHTTP_NO_PROXY_BYPASS,
                0);
            if (!session) {
                return std::nullopt;
            }

            HINTERNET connect = WinHttpConnect(session, host.data(), INTERNET_DEFAULT_HTTPS_PORT, 0);
            if (!connect) {
                WinHttpCloseHandle(session);
                return std::nullopt;
            }

            HINTERNET request = WinHttpOpenRequest(
                connect, L"GET", path.data(), nullptr, WINHTTP_NO_REFERER,
                WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
            if (!request) {
                WinHttpCloseHandle(connect);
                WinHttpCloseHandle(session);
                return std::nullopt;
            }

            // GitHub's REST API requires a User-Agent header.
            WinHttpAddRequestHeaders(
                request, L"User-Agent: SkyrimTwitchExpansion\r\nAccept: application/vnd.github+json\r\n",
                static_cast<DWORD>(-1), WINHTTP_ADDREQ_FLAG_ADD);

            std::optional<std::string> result;
            if (WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0) &&
                WinHttpReceiveResponse(request, nullptr)) {
                std::string body;
                DWORD available = 0;
                while (WinHttpQueryDataAvailable(request, &available) && available > 0) {
                    std::vector<char> buf(available);
                    DWORD read = 0;
                    if (!WinHttpReadData(request, buf.data(), available, &read)) {
                        break;
                    }
                    body.append(buf.data(), read);
                }
                result = std::move(body);
            }

            WinHttpCloseHandle(request);
            WinHttpCloseHandle(connect);
            WinHttpCloseHandle(session);
            return result;
        }
    }

    void CheckForUpdatesAsync(std::string_view repoOwner, std::string_view repoName, std::string_view currentVersion)
    {
        std::thread([owner = std::string(repoOwner), repo = std::string(repoName), current = std::string(currentVersion)] {
            const auto path = L"/repos/" + std::wstring(owner.begin(), owner.end()) + L"/" +
                               std::wstring(repo.begin(), repo.end()) + L"/releases/latest";

            const auto body = HttpsGet(L"api.github.com", path);
            if (!body) {
                logger::warn("UpdateChecker: request failed, skipping this session");
                return;
            }

            try {
                const auto parsed = json::json::parse(*body);
                const std::string latestTag = parsed.value("tag_name", std::string{});
                std::string latest = latestTag;
                if (!latest.empty() && latest.front() == 'v') {
                    latest.erase(0, 1);
                }

                if (!latest.empty() && latest != current) {
                    logger::info("UpdateChecker: current={} latest={} (update available)", current, latest);
                    std::lock_guard lock(g_pendingMutex);
                    g_pendingVersion = latest;
                } else {
                    logger::info("UpdateChecker: up to date ({})", current);
                }
            } catch (const std::exception& e) {
                logger::warn("UpdateChecker: failed to parse release JSON: {}", e.what());
            }
        }).detach();
    }

    std::optional<std::string> TakePendingNotification()
    {
        std::lock_guard lock(g_pendingMutex);
        auto value = std::move(g_pendingVersion);
        g_pendingVersion.reset();
        return value;
    }
}
