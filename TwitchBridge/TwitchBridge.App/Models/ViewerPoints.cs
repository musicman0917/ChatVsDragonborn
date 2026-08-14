namespace TwitchBridge.Models;

/// <summary>A single viewer's balance and earn-rate bookkeeping.</summary>
public sealed class ViewerPoints
{
    public required string Username { get; init; }
    public long Balance { get; set; }
    public DateTimeOffset LastEarnTick { get; set; } = DateTimeOffset.UtcNow;
}

/// <summary>Root of the local JSON ledger persisted to Points:LedgerPath.</summary>
public sealed class PointsLedger
{
    public Dictionary<string, ViewerPoints> Viewers { get; init; } = new(StringComparer.OrdinalIgnoreCase);
}
