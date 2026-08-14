using System.Text.Json;
using Microsoft.Extensions.Options;
using TwitchBridge.Models;

namespace TwitchBridge.Services;

public sealed class PointsOptions
{
    public string LedgerPath { get; set; } = "data/points-ledger.json";
    public int EarnRatePerMinute { get; set; } = 10;
    public int SubGrant { get; set; } = 500;
    public int BitsPerPoint { get; set; } = 1;
}

/// <summary>
/// Local JSON-persisted points economy: earn-over-time ticks plus
/// event-based grants (subs, bits, channel points), and debits for
/// chaos-command purchases. Ledger writes are atomic (write-temp + rename)
/// so a crash mid-write can't corrupt the file.
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
            return GetOrCreateViewer(username).Balance;
        }
        finally
        {
            _lock.Release();
        }
    }

    /// <summary>Attempts to debit <paramref name="amount"/> points; returns false (no-op) on insufficient balance.</summary>
    public async Task<bool> TrySpendAsync(string username, int amount, CancellationToken ct = default)
    {
        await _lock.WaitAsync(ct);
        try
        {
            var viewer = GetOrCreateViewer(username);
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
            var viewer = GetOrCreateViewer(username);
            viewer.Balance += amount;
            await SaveLockedAsync(ct);
        }
        finally
        {
            _lock.Release();
        }
    }

    /// <summary>Called on a periodic timer for each viewer currently active in chat.</summary>
    public Task GrantEarnTickAsync(string username, CancellationToken ct = default)
        => GrantAsync(username, _options.EarnRatePerMinute, ct);

    public Task GrantSubAsync(string username, CancellationToken ct = default)
        => GrantAsync(username, _options.SubGrant, ct);

    public Task GrantBitsAsync(string username, int bits, CancellationToken ct = default)
        => GrantAsync(username, bits * _options.BitsPerPoint, ct);

    private ViewerPoints GetOrCreateViewer(string username)
    {
        if (!_ledger.Viewers.TryGetValue(username, out var viewer))
        {
            viewer = new ViewerPoints { Username = username };
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
