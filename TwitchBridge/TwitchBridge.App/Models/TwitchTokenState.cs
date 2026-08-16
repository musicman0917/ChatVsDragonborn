namespace TwitchBridge.Models;

/// <summary>
/// Persisted OAuth state for the moderator-scoped Helix token (see
/// HelixApiService.IsFollowingAsync / ModeratorTokenStore). Twitch rotates
/// the refresh token on every refresh call, so both fields are re-saved
/// together each time.
/// </summary>
public sealed class TwitchTokenState
{
    public string AccessToken { get; set; } = "";
    public string RefreshToken { get; set; } = "";
    public DateTimeOffset ExpiresAtUtc { get; set; }
}
