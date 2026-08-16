using Microsoft.Extensions.Options;

namespace TwitchBridge.Services;

/// <summary>
/// Ticks PointsEconomyService.RunPassiveIncomeTickAsync on a fixed interval.
/// Split out from PointsEconomyService itself so the economy class stays a
/// plain on-demand data store (matching WaterparkSimTwitchExpansion's
/// PointsManager, which has no timer of its own -- its host engine drives
/// Tick() once per frame). Here there's no render loop, so a PeriodicTimer
/// stands in for it.
/// </summary>
public sealed class PassiveIncomeService : BackgroundService
{
    private readonly ILogger<PassiveIncomeService> _logger;
    private readonly PointsEconomyService _points;
    private readonly PointsOptions _options;

    public PassiveIncomeService(ILogger<PassiveIncomeService> logger, PointsEconomyService points, IOptions<PointsOptions> options)
    {
        _logger = logger;
        _points = points;
        _options = options.Value;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var interval = TimeSpan.FromMinutes(Math.Max(1, _options.PassiveIncomeIntervalMinutes));
        using var timer = new PeriodicTimer(interval);

        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                var paid = await _points.RunPassiveIncomeTickAsync(stoppingToken);
                if (paid > 0)
                {
                    _logger.LogInformation("Passive income tick: paid {Count} active viewer(s) {Amount} points each",
                        paid, _options.PassiveIncomeAmount);
                }
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogWarning(ex, "Passive income tick failed");
            }
        }
    }
}
