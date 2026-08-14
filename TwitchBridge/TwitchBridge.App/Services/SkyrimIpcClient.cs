using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using TwitchBridge.Models;

namespace TwitchBridge.Services;

public sealed class SkyrimBridgeOptions
{
    public string PipeName { get; set; } = "SkyrimTwitchExpansion";
    public int ReconnectDelaySeconds { get; set; } = 5;
}

/// <summary>
/// Client side of the named-pipe transport described in
/// docs/ARCHITECTURE.md — connects out to the SKSE plugin's
/// \\.\pipe\SkyrimTwitchExpansion server, writes ChaosCommand JSON lines,
/// and reads back OutboundEvent JSON lines (command results + engine
/// events). Runs entirely on background tasks; nothing here blocks the
/// Twitch IRC thread or vice versa.
/// </summary>
public sealed class SkyrimIpcClient : BackgroundService
{
    private readonly ILogger<SkyrimIpcClient> _logger;
    private readonly SkyrimBridgeOptions _options;
    private readonly System.Threading.Channels.Channel<ChaosCommand> _outbox =
        System.Threading.Channels.Channel.CreateUnbounded<ChaosCommand>();

    public event Action<OutboundEvent>? EventReceived;

    public SkyrimIpcClient(ILogger<SkyrimIpcClient> logger, IOptions<SkyrimBridgeOptions> options)
    {
        _logger = logger;
        _options = options.Value;
    }

    /// <summary>Enqueues a chaos command for delivery to the SKSE plugin.</summary>
    public ValueTask SendAsync(ChaosCommand command, CancellationToken ct = default)
        => _outbox.Writer.WriteAsync(command, ct);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await using var pipe = new NamedPipeClientStream(".", _options.PipeName, PipeDirection.InOut, PipeOptions.Asynchronous);
                _logger.LogInformation("Connecting to Skyrim pipe {PipeName}...", _options.PipeName);
                await pipe.ConnectAsync(stoppingToken);
                _logger.LogInformation("Connected to Skyrim plugin");

                var readTask = ReadLoopAsync(pipe, stoppingToken);
                var writeTask = WriteLoopAsync(pipe, stoppingToken);
                await Task.WhenAny(readTask, writeTask);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Skyrim pipe connection lost, retrying in {Delay}s", _options.ReconnectDelaySeconds);
            }

            await Task.Delay(TimeSpan.FromSeconds(_options.ReconnectDelaySeconds), stoppingToken).ContinueWith(_ => { });
        }
    }

    private async Task WriteLoopAsync(NamedPipeClientStream pipe, CancellationToken ct)
    {
        await foreach (var command in _outbox.Reader.ReadAllAsync(ct))
        {
            var line = JsonSerializer.Serialize(command) + "\n";
            var bytes = Encoding.UTF8.GetBytes(line);
            await pipe.WriteAsync(bytes, ct);
            await pipe.FlushAsync(ct);
        }
    }

    private async Task ReadLoopAsync(NamedPipeClientStream pipe, CancellationToken ct)
    {
        using var reader = new StreamReader(pipe, Encoding.UTF8, leaveOpen: true);
        while (!ct.IsCancellationRequested)
        {
            var line = await reader.ReadLineAsync(ct);
            if (line is null)
            {
                break; // pipe closed by the plugin
            }
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            try
            {
                var evt = JsonSerializer.Deserialize<OutboundEvent>(line);
                if (evt is not null)
                {
                    EventReceived?.Invoke(evt);
                }
            }
            catch (JsonException ex)
            {
                _logger.LogWarning(ex, "Failed to parse event line from Skyrim plugin: {Line}", line);
            }
        }
    }
}
