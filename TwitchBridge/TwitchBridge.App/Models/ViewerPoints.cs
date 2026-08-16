namespace TwitchBridge.Models;

/// <summary>A single viewer's balance and activity/bonus bookkeeping.</summary>
public sealed class ViewerPoints
{
    public required string Username { get; init; }
    public string DisplayName { get; set; } = "";
    public long Balance { get; set; }

    /// <summary>Updated on every chat message; passive income only pays viewers seen within PointsOptions.ActivityWindowMinutes of now.</summary>
    public DateTimeOffset LastSeenUtc { get; set; } = DateTimeOffset.UtcNow;

    /// <summary>True once the one-time follow-after-first-message top-up has fired. Never re-checked afterward, even across unfollow/refollow.</summary>
    public bool FollowBonusGranted { get; set; }

    /// <summary>Throttles the Helix follow lookup; null means never checked.</summary>
    public DateTimeOffset? LastFollowCheckUtc { get; set; }
}

/// <summary>Root of the local JSON ledger persisted to Points:LedgerPath.</summary>
public sealed class PointsLedger
{
    public Dictionary<string, ViewerPoints> Viewers { get; init; } = new(StringComparer.OrdinalIgnoreCase);
}
