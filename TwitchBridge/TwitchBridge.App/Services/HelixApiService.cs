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
    private readonly TwitchOptions _options;
    private readonly ModeratorTokenStore _moderatorToken;
    private readonly Dictionary<string, string> _userIdCache = new(StringComparer.OrdinalIgnoreCase);
    private readonly SemaphoreSlim _resolveLock = new(1, 1);
    private string? _broadcasterId;

    public HelixApiService(ILogger<HelixApiService> logger, IOptions<TwitchOptions> options, ModeratorTokenStore moderatorToken)
    {
        _logger = logger;
        _options = options.Value;
        _moderatorToken = moderatorToken;
        _api = new TwitchAPI();
        _api.Settings.ClientId = _options.ClientId;
        _api.Settings.Secret = _options.ClientSecret;
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
        var token = await _moderatorToken.GetAccessTokenAsync(ct);
        if (token is null)
        {
            return null;
        }

        try
        {
            var response = await _api.Helix.Channels.GetChannelFollowersAsync(broadcasterId, userId, accessToken: token);
            var follow = response.Data.FirstOrDefault();
            return follow is null ? null : DateTimeOffset.UtcNow - DateTimeOffset.Parse(follow.FollowedAt);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Helix follow-age lookup failed for user {UserId}", userId);
            return null;
        }
    }

    /// <summary>
    /// Checks whether <paramref name="username"/> currently follows the
    /// broadcaster channel (Twitch:Channel). Requires a moderator-scoped
    /// token (see ModeratorTokenStore) -- belonging to the broadcaster or a
    /// mod -- carrying the moderator:read:followers scope; the bot's own
    /// chat:read/chat:edit token cannot make this call (that's a Twitch
    /// Helix requirement, not a TwitchBridge choice). Returns false rather
    /// than throwing on any failure -- missing/expired token, unresolved
    /// user, network error -- so a misconfigured follow-bonus feature just
    /// means nobody gets the bonus rather than crashing chat handling.
    /// </summary>
    public async Task<bool> IsFollowingAsync(string username, CancellationToken ct = default)
    {
        var token = await _moderatorToken.GetAccessTokenAsync(ct);
        if (token is null)
        {
            return false;
        }

        try
        {
            var broadcasterId = await ResolveBroadcasterIdAsync(ct);
            var userId = await ResolveUserIdAsync(username, ct);
            if (broadcasterId is null || userId is null)
            {
                return false;
            }

            var response = await _api.Helix.Channels.GetChannelFollowersAsync(broadcasterId, userId, accessToken: token);
            return response.Data.Length > 0;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Helix follow check failed for {Username}", username);
            return false;
        }
    }

    private async Task<string?> ResolveBroadcasterIdAsync(CancellationToken ct)
    {
        if (_broadcasterId is not null)
        {
            return _broadcasterId;
        }
        await _resolveLock.WaitAsync(ct);
        try
        {
            _broadcasterId ??= await ResolveUserIdAsync(_options.Channel, ct);
            return _broadcasterId;
        }
        finally
        {
            _resolveLock.Release();
        }
    }

    private async Task<string?> ResolveUserIdAsync(string username, CancellationToken ct)
    {
        if (_userIdCache.TryGetValue(username, out var cached))
        {
            return cached;
        }

        var response = await _api.Helix.Users.GetUsersAsync(logins: new List<string> { username });
        var id = response.Users.FirstOrDefault()?.Id;
        if (id is not null)
        {
            _userIdCache[username] = id;
        }
        return id;
    }
}
