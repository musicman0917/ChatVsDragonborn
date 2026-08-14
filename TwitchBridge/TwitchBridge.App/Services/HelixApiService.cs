using Microsoft.Extensions.Options;
using TwitchLib.Api;

namespace TwitchBridge.Services;

/// <summary>
/// Thin wrapper around TwitchLib.Api's Helix client for the lookups the
/// points economy and chat commands need: follower age (for earn-rate
/// bonuses), subscriber tier (for grant sizing), and channel-points custom
/// reward redemptions (via EventSub in the full implementation). Kept
/// separate from <see cref="TwitchIrcService"/> so REST calls never share a
/// thread with IRC message parsing.
/// </summary>
public sealed class HelixApiService
{
    private readonly ILogger<HelixApiService> _logger;
    private readonly TwitchAPI _api;

    public HelixApiService(ILogger<HelixApiService> logger, IOptions<TwitchOptions> options)
    {
        _logger = logger;
        _api = new TwitchAPI();
        _api.Settings.ClientId = options.Value.ClientId;
        _api.Settings.Secret = options.Value.ClientSecret;
    }

    public async Task<bool> IsSubscriberAsync(string broadcasterId, string userId, CancellationToken ct = default)
    {
        try
        {
            var response = await _api.Helix.Subscriptions.CheckUserSubscriptionAsync(broadcasterId, userId);
            return response.Data.Length > 0;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Helix subscription check failed for user {UserId}", userId);
            return false;
        }
    }

    public async Task<TimeSpan?> GetFollowAgeAsync(string broadcasterId, string userId, CancellationToken ct = default)
    {
        try
        {
            var response = await _api.Helix.Channels.GetChannelFollowersAsync(broadcasterId, userId);
            var follow = response.Data.FirstOrDefault();
            return follow is null ? null : DateTimeOffset.UtcNow - DateTimeOffset.Parse(follow.FollowedAt);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Helix follow-age lookup failed for user {UserId}", userId);
            return null;
        }
    }
}
