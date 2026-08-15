using Microsoft.Extensions.Options;
using TwitchBridge.Models;
using TwitchLib.Client;
using TwitchLib.Client.Events;
using TwitchLib.Client.Models;
using TwitchLib.Communication.Clients;
using TwitchLib.Communication.Models;

namespace TwitchBridge.Services;

public sealed class TwitchOptions
{
    public string Channel { get; set; } = "";
    public string BotUsername { get; set; } = "";
    public string OAuthToken { get; set; } = "";
    public string ClientId { get; set; } = "";
    public string ClientSecret { get; set; } = "";
}

/// <summary>
/// Owns the Twitch IRC connection. Parses `!buy &lt;action&gt;` chat commands
/// and chat votes, checks/debits the viewer's balance via
/// <see cref="PointsEconomyService"/>, and hands off resulting
/// <see cref="ChaosCommand"/>s to <see cref="SkyrimIpcClient"/>. All Twitch
/// networking happens on TwitchLib's own connection thread — nothing here
/// touches Skyrim directly (see docs/ARCHITECTURE.md threading table).
/// </summary>
public sealed class TwitchIrcService : BackgroundService
{
    private readonly ILogger<TwitchIrcService> _logger;
    private readonly TwitchOptions _options;
    private readonly PointsEconomyService _points;
    private readonly SkyrimIpcClient _skyrim;
    private readonly OverlayHttpServer _overlay;
    private TwitchClient? _client;

    public TwitchIrcService(
        ILogger<TwitchIrcService> logger,
        IOptions<TwitchOptions> options,
        PointsEconomyService points,
        SkyrimIpcClient skyrim,
        OverlayHttpServer overlay)
    {
        _logger = logger;
        _options = options.Value;
        _points = points;
        _skyrim = skyrim;
        _overlay = overlay;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (string.IsNullOrWhiteSpace(_options.OAuthToken))
        {
            _logger.LogWarning("Twitch:OAuthToken is not configured; TwitchIrcService will not connect. " +
                                "Set it via user-secrets or the TwitchBridge__Twitch__OAuthToken environment variable.");
            return;
        }

        var credentials = new ConnectionCredentials(_options.BotUsername, _options.OAuthToken);
        var connectionOptions = new ClientOptions { MessagesAllowedInPeriod = 750, ThrottlingPeriod = TimeSpan.FromSeconds(30) };
        var webSocketClient = new WebSocketClient(connectionOptions);

        _client = new TwitchClient(webSocketClient);
        _client.Initialize(credentials, _options.Channel);

        _client.OnMessageReceived += OnMessageReceived;
        _client.OnConnected += (_, e) => _logger.LogInformation("Connected to Twitch as {Bot}", e.BotUsername);
        _client.OnDisconnected += (_, _) => _logger.LogWarning("Disconnected from Twitch");

        _client.Connect();

        stoppingToken.Register(() => _client.Disconnect());
        await Task.Delay(Timeout.Infinite, stoppingToken).ContinueWith(_ => { });
    }

    private async void OnMessageReceived(object? sender, OnMessageReceivedArgs e)
    {
        var message = e.ChatMessage.Message.Trim();
        var viewer = e.ChatMessage.Username;

        if (message.StartsWith("!buy ", StringComparison.OrdinalIgnoreCase))
        {
            var action = message["!buy ".Length..].Trim().ToLowerInvariant();
            await HandleBuyCommandAsync(viewer, action);
        }
        else if (message.StartsWith("!give ", StringComparison.OrdinalIgnoreCase))
        {
            await HandleGiveCommandAsync(e.ChatMessage);
        }
        // !vote 1/2/3 handling lives in PollEngine once wired in (Phase 4 of
        // docs/IMPLEMENTATION_PLAN.md); TwitchIrcService only owns the raw
        // chat parsing entry point.
    }

    private static readonly Dictionary<string, string> ActionPriceKeys = new(StringComparer.OrdinalIgnoreCase)
    {
        ["ragdoll"] = "chaos.ragdoll.price",
        ["earthquake"] = "chaos.earthquake.price",
        ["dragon"] = "chaos.spawn_dragon.price",
        ["chickens"] = "chaos.spawn_chickens.price",
        ["invert"] = "chaos.invert_controls.price",
        ["lowgravity"] = "chaos.low_gravity.price",
        ["addgold"] = "chaos.add_gold.price",
        ["removegold"] = "chaos.remove_gold.price",
    };

    private static readonly Dictionary<string, string> ActionCommandTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        ["ragdoll"] = "ragdoll",
        ["earthquake"] = "earthquake",
        ["dragon"] = "spawn_dragon",
        ["chickens"] = "spawn_chickens",
        ["invert"] = "invert_controls",
        ["lowgravity"] = "low_gravity",
        ["addgold"] = "add_gold",
        ["removegold"] = "remove_gold",
    };

    private async Task HandleBuyCommandAsync(string viewer, string action)
    {
        if (!ActionCommandTypes.TryGetValue(action, out var commandType))
        {
            SendChatMessage($"@{viewer} unknown chaos action '{action}'.");
            return;
        }

        // NOTE: prices are cached from Skyrim's live settings file in a real
        // implementation (Phase 6); this scaffold uses a flat placeholder so
        // the purchase flow is demonstrable end-to-end without that wiring.
        const int placeholderPrice = 100;

        if (!await _points.TrySpendAsync(viewer, placeholderPrice))
        {
            SendChatMessage($"@{viewer} you don't have enough points for {action} ({placeholderPrice} needed).");
            return;
        }

        var command = new ChaosCommand
        {
            Type = commandType,
            Viewer = viewer,
            Price = placeholderPrice,
        };

        await _skyrim.SendAsync(command);
        await _overlay.BroadcastAsync(new { type = "toast", text = $"{viewer} bought {action}!" });
        _logger.LogInformation("Queued chaos command {Type} from {Viewer}", commandType, viewer);
    }

    // Mod/broadcaster-only point grant: "!give @username <amount>". Useful
    // for testing and for rewarding viewers manually until real earn-rate
    // ticks and sub/bits grants (Phase 1 of docs/IMPLEMENTATION_PLAN.md) are
    // wired up.
    private async Task HandleGiveCommandAsync(ChatMessage chatMessage)
    {
        if (!chatMessage.IsBroadcaster && !chatMessage.IsModerator)
        {
            return; // silently ignore — avoid rewarding chat spam with an error message
        }

        var parts = chatMessage.Message.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length != 3 || !int.TryParse(parts[2], out var amount) || amount <= 0)
        {
            SendChatMessage("Usage: !give @username <amount>");
            return;
        }

        var target = parts[1].TrimStart('@');
        await _points.GrantAsync(target, amount);
        SendChatMessage($"@{chatMessage.Username} gave {amount} points to @{target}!");
        _logger.LogInformation("{Granter} granted {Amount} points to {Target}", chatMessage.Username, amount, target);
    }

    private void SendChatMessage(string text)
    {
        if (_client is { IsConnected: true })
        {
            _client.SendMessage(_options.Channel, text);
        }
    }
}
