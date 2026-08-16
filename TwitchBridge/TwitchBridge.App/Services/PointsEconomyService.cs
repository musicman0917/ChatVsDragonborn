using System.Text.Json;
using Microsoft.Extensions.Options;
using TwitchBridge.Models;

namespace TwitchBridge.Services;

public sealed class PointsOptions
{
    public string LedgerPath { get; set; } = "data/points-ledger.json";

    // Starting balance tiers, applied once at first-ever chat message. Follower
    // isn't checkable synchronously from a chat badge (see PointsEconomyService
    // remarks), so new accounts only ever start at Base or VipModBroadcaster;
    // the Follower tier is reached later, if at all, via the one-time top-up in
    // TryGrantFollowBonusAsync.
    public long StartingBalanceBase { get; set; } = 250;
    public long StartingBalanceFollower { get; set; } = 500;
    public long StartingBalanceVipModBroadcaster { get; set; } = 1000;

    // Passive income: PassiveIncomeAmount points, every PassiveIncomeIntervalMinutes,
    // to every viewer who has chatted within the last ActivityWindowMinutes.
    public long PassiveIncomeAmount { get; set; } = 10;
    public int PassiveIncomeIntervalMinutes { get; set; } = 1;
    public int ActivityWindowMinutes { get; set; } = 10;

    // Throttle for the Helix follow-bonus lookup so a chatty non-follower
    // doesn't trigger a network call on every message.
    public int FollowCheckIntervalMinutes { get; set; } = 15;

    public long SubscriberPointsPerTier { get; set; } = 500;
    public long GiftedSubPointsPerTier { get; set; } = 500;
    public long BitsToPointsRatio { get; set; } = 1;
}

/// <summary>
/// Local JSON-persisted points economy: passive income for active chatters,
/// event-based grants (subs, gifted subs, bits, manual !give), a one-time
/// follow bonus, and debits for chaos-command purchases. Ledger writes are
/// atomic (write-temp + rename) so a crash mid-write can't corrupt the file.
///
/// Mirrors WaterparkSimTwitchExpansion's PointsManager design (see the
/// point-system write-up shared for this port): a single lock-protected
/// dictionary instead of that project's ConcurrentDictionary, since here
/// every mutation already goes through async methods behind a semaphore
/// (matching the rest of this file's persistence pattern) rather than a
/// per-frame engine tick.
/// </summary>
public sealed class PointsEconomyService
{
    private readonly ILogger<PointsEconomyService> _logger;
    private readonly PointsOptions _options;
    private readonly SemaphoreSlim _lock = new(1, 1);
    private PointsLedger _ledger = new();

    public PointsEconomyService(ILogger<PointsEconomyService> logger, IOptions<PointsOptions> options)
    {
        _logger = logger;
        _options = options.Value;
    }

    public async Task LoadAsync(CancellationToken ct = default)
    {
        await _lock.WaitAsync(ct);
        try
        {
            if (File.Exists(_options.LedgerPath))
            {
                await using var stream = File.OpenRead(_options.LedgerPath);
                _ledger = await JsonSerializer.DeserializeAsync<PointsLedger>(stream, cancellationToken: ct) ?? new PointsLedger();
            }
        }
        catch (JsonException ex)
        {
            _logger.LogError(ex, "Points ledger at {Path} is corrupt; starting from an empty ledger", _options.LedgerPath);
            _ledger = new PointsLedger();
        }
        finally
        {
            _lock.Release();
        }
    }

    public async Task<long> GetBalanceAsync(string username, CancellationToken ct = default)
    {
        await _lock.WaitAsync(ct);
        try
        {
            return GetViewerOrNull(username)?.Balance ?? 0;
        }
        finally
        {
            _lock.Release();
        }
    }

    public async Task<bool> HasAccountAsync(string username, CancellationToken ct = default)
    {
        await _lock.WaitAsync(ct);
        try
        {
            return _ledger.Viewers.ContainsKey(username);
        }
        finally
        {
            _lock.Release();
        }
    }

    /// <summary>Attempts to debit <paramref name="amount"/> points; returns false (no-op) on insufficient balance.</summary>
    public async Task<bool> TrySpendAsync(string username, long amount, CancellationToken ct = default)
    {
        await _lock.WaitAsync(ct);
        try
        {
            var viewer = GetOrCreateViewer(username, username, _options.StartingBalanceBase);
            if (viewer.Balance < amount)
            {
                return false;
            }
            viewer.Balance -= amount;
            await SaveLockedAsync(ct);
            return true;
        }
        finally
        {
            _lock.Release();
        }
    }

    public async Task GrantAsync(string username, long amount, CancellationToken ct = default)
    {
        await _lock.WaitAsync(ct);
        try
        {
            var viewer = GetOrCreateViewer(username, username, _options.StartingBalanceBase);
            viewer.Balance += amount;
            await SaveLockedAsync(ct);
        }
        finally
        {
            _lock.Release();
        }
    }

    /// <summary>
    /// Call on every chat message. Creates the account on first sight with
    /// <paramref name="startingBalance"/> (caller decides the tier from the
    /// message's own badges: VIP/mod/broadcaster get StartingBalanceVipModBroadcaster,
    /// everyone else StartingBalanceBase). A no-op for balance on every
    /// message after that -- only DisplayName/LastSeenUtc update, so it's
    /// safe to call unconditionally without checking existence first.
    /// </summary>
    public async Task RegisterActivityAsync(string username, string displayName, long startingBalance, CancellationToken ct = default)
    {
        await _lock.WaitAsync(ct);
        try
        {
            var viewer = GetOrCreateViewer(username, displayName, startingBalance);
            viewer.DisplayName = displayName;
            viewer.LastSeenUtc = DateTimeOffset.UtcNow;
            await SaveLockedAsync(ct);
        }
        finally
        {
            _lock.Release();
        }
    }

    /// <summary>
    /// True if this account is due for a follow-bonus recheck: it exists,
    /// hasn't already received the bonus, and either has never been checked
    /// or wasn't checked within FollowCheckIntervalMinutes. Callers should
    /// also skip this for viewers who are currently VIP/mod/broadcaster --
    /// they already started at the top tier, so a follow bonus is moot.
    /// </summary>
    public async Task<bool> ShouldCheckFollowBonusAsync(string username, CancellationToken ct = default)
    {
        await _lock.WaitAsync(ct);
        try
        {
            var viewer = GetViewerOrNull(username);
            if (viewer is null || viewer.FollowBonusGranted)
            {
                return false;
            }
            var dueAt = viewer.LastFollowCheckUtc?.AddMinutes(_options.FollowCheckIntervalMinutes);
            return dueAt is null || dueAt <= DateTimeOffset.UtcNow;
        }
        finally
        {
            _lock.Release();
        }
    }

    /// <summary>Records that a follow check just happened, win or lose, so the throttle in ShouldCheckFollowBonusAsync advances either way.</summary>
    public async Task MarkFollowCheckedAsync(string username, CancellationToken ct = default)
    {
        await _lock.WaitAsync(ct);
        try
        {
            var viewer = GetViewerOrNull(username);
            if (viewer is null)
            {
                return;
            }
            viewer.LastFollowCheckUtc = DateTimeOffset.UtcNow;
            await SaveLockedAsync(ct);
        }
        finally
        {
            _lock.Release();
        }
    }

    /// <summary>
    /// One-time top-up from the base tier to the follower tier. No-ops if
    /// already granted (idempotent even if called twice for the same
    /// confirmed-follower before the flag is observed).
    /// </summary>
    public async Task<bool> TryGrantFollowBonusAsync(string username, CancellationToken ct = default)
    {
        await _lock.WaitAsync(ct);
        try
        {
            var viewer = GetViewerOrNull(username);
            if (viewer is null || viewer.FollowBonusGranted)
            {
                return false;
            }
            var bonus = _options.StartingBalanceFollower - _options.StartingBalanceBase;
            if (bonus > 0)
            {
                viewer.Balance += bonus;
            }
            viewer.FollowBonusGranted = true;
            await SaveLockedAsync(ct);
            return true;
        }
        finally
        {
            _lock.Release();
        }
    }

    public Task GrantSubAsync(string username, int tier, CancellationToken ct = default)
        => GrantAsync(username, tier * _options.SubscriberPointsPerTier, ct);

    /// <summary>Credited to the gifter, not the recipient -- called once per recipient, so a mass/community gift of N naturally pays out N times.</summary>
    public Task GrantGiftedSubAsync(string gifterUsername, int tier, CancellationToken ct = default)
        => GrantAsync(gifterUsername, tier * _options.GiftedSubPointsPerTier, ct);

    public Task GrantBitsAsync(string username, int bits, CancellationToken ct = default)
        => GrantAsync(username, bits * _options.BitsToPointsRatio, ct);

    /// <summary>
    /// Pays PassiveIncomeAmount to every account seen within
    /// ActivityWindowMinutes of now. Called on a timer (see
    /// PassiveIncomeService) rather than accumulating a per-frame delta,
    /// since this host has no render loop to hook. Returns the number of
    /// viewers paid, for logging.
    /// </summary>
    public async Task<int> RunPassiveIncomeTickAsync(CancellationToken ct = default)
    {
        await _lock.WaitAsync(ct);
        try
        {
            var cutoff = DateTimeOffset.UtcNow.AddMinutes(-_options.ActivityWindowMinutes);
            var paid = 0;
            foreach (var viewer in _ledger.Viewers.Values)
            {
                if (viewer.LastSeenUtc >= cutoff)
                {
                    viewer.Balance += _options.PassiveIncomeAmount;
                    paid++;
                }
            }
            if (paid > 0)
            {
                await SaveLockedAsync(ct);
            }
            return paid;
        }
        finally
        {
            _lock.Release();
        }
    }

    private ViewerPoints? GetViewerOrNull(string username)
        => _ledger.Viewers.TryGetValue(username, out var viewer) ? viewer : null;

    private ViewerPoints GetOrCreateViewer(string username, string displayName, long startingBalance)
    {
        if (!_ledger.Viewers.TryGetValue(username, out var viewer))
        {
            viewer = new ViewerPoints { Username = username, DisplayName = displayName, Balance = startingBalance };
            _ledger.Viewers[username] = viewer;
        }
        return viewer;
    }

    private async Task SaveLockedAsync(CancellationToken ct)
    {
        var directory = Path.GetDirectoryName(_options.LedgerPath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var tmpPath = _options.LedgerPath + ".tmp";
        await using (var stream = File.Create(tmpPath))
        {
            await JsonSerializer.SerializeAsync(stream, _ledger, new JsonSerializerOptions { WriteIndented = true }, ct);
        }
        File.Move(tmpPath, _options.LedgerPath, overwrite: true);
    }
}
