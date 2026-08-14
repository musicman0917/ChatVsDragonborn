#pragma once

namespace STE::Update
{
    // Fire-and-forget GitHub Releases check. Spawns its own thread; never
    // touches game state. On finding a newer tag than the compiled-in
    // version, stages a flag that the main thread surfaces as an in-game
    // notification on the next safe tick.
    void CheckForUpdatesAsync(std::string_view repoOwner, std::string_view repoName, std::string_view currentVersion);

    // Called from the main-thread per-frame task. Returns the new version
    // string once (and only once) if an update was found, then clears it.
    std::optional<std::string> TakePendingNotification();
}
