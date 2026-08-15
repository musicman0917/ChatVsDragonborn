using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Options;

namespace TwitchBridge.Services;

public sealed class OverlayOptions
{
    public string ListenUrl { get; set; } = "http://127.0.0.1:9099";
}

/// <summary>
/// Local-only HTTP server for the OBS Browser Source overlay: serves the
/// static wwwroot/overlay.html (toasts + live poll widget) and pushes state
/// changes to connected browser sources over a WebSocket. Bound to
/// 127.0.0.1 by default (see appsettings.json) since this never needs to be
/// reachable off the streamer's own machine.
/// </summary>
public sealed class OverlayHttpServer : BackgroundService
{
    private readonly ILogger<OverlayHttpServer> _logger;
    private readonly OverlayOptions _options;
    private readonly ConcurrentDictionary<Guid, WebSocket> _sockets = new();
    private WebApplication? _app;

    public OverlayHttpServer(ILogger<OverlayHttpServer> logger, IOptions<OverlayOptions> options)
    {
        _logger = logger;
        _options = options.Value;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.UseUrls(_options.ListenUrl);
        builder.Logging.ClearProviders();

        _app = builder.Build();
        _app.UseWebSockets();
        _app.UseStaticFiles(); // serves wwwroot/overlay.html, .css, .js

        _app.Map("/ws", async (HttpContext context) =>
        {
            if (!context.WebSockets.IsWebSocketRequest)
            {
                context.Response.StatusCode = StatusCodes.Status400BadRequest;
                return;
            }

            var socket = await context.WebSockets.AcceptWebSocketAsync();
            var id = Guid.NewGuid();
            _sockets[id] = socket;
            _logger.LogInformation("Overlay client connected ({Count} total)", _sockets.Count);

            var buffer = new byte[1024];
            try
            {
                while (socket.State == WebSocketState.Open)
                {
                    var result = await socket.ReceiveAsync(buffer, context.RequestAborted);
                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        break;
                    }
                }
            }
            catch (OperationCanceledException) { }
            finally
            {
                _sockets.TryRemove(id, out _);
            }
        });

        _logger.LogInformation("Overlay server listening on {Url}", _options.ListenUrl);
        await _app.RunAsync(stoppingToken);
    }

    /// <summary>Pushes a JSON-serializable payload to every connected overlay browser source.</summary>
    public async Task BroadcastAsync(object payload, CancellationToken ct = default)
    {
        var json = JsonSerializer.Serialize(payload);
        var bytes = Encoding.UTF8.GetBytes(json);

        foreach (var (id, socket) in _sockets)
        {
            if (socket.State != WebSocketState.Open)
            {
                _sockets.TryRemove(id, out _);
                continue;
            }

            try
            {
                await socket.SendAsync(bytes, WebSocketMessageType.Text, endOfMessage: true, ct);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to send to overlay client {Id}, dropping", id);
                _sockets.TryRemove(id, out _);
            }
        }
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        if (_app is not null)
        {
            await _app.StopAsync(cancellationToken);
        }
        await base.StopAsync(cancellationToken);
    }
}
