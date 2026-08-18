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

    /// <summary>
    /// A user token -- belonging to the broadcaster or a mod, not the bot --
    /// carrying moderator:read:followers. Only used by HelixApiService for
    /// the one-time follow-bonus check; leave blank to disable that feature
    /// entirely (ShouldCheckFollowBonusAsync/IsFollowingAsync both degrade to
    /// "no bonus" rather than erroring). Only ever read once, as the initial
    /// seed -- see ModeratorTokenStore, which takes over persisting/
    /// refreshing it after the first run.
    /// </summary>
    public string ModeratorAccessToken { get; set; } = "";

    /// <summary>The refresh token paired with ModeratorAccessToken. Required for auto-refresh; without it the seeded access token is used until it expires and then the follow-bonus feature silently stops working.</summary>
    public string ModeratorRefreshToken { get; set; } = "";
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
    private readonly PointsOptions _pointsOptions;
    private readonly PointsEconomyService _points;
    private readonly HelixApiService _helix;
    private readonly ChaosSettingsCache _chaosSettings;
    private readonly SkyrimIpcClient _skyrim;
    private readonly OverlayHttpServer _overlay;
    private TwitchClient? _client;

    public TwitchIrcService(
        ILogger<TwitchIrcService> logger,
        IOptions<TwitchOptions> options,
        IOptions<PointsOptions> pointsOptions,
        PointsEconomyService points,
        HelixApiService helix,
        ChaosSettingsCache chaosSettings,
        SkyrimIpcClient skyrim,
        OverlayHttpServer overlay)
    {
        _logger = logger;
        _options = options.Value;
        _pointsOptions = pointsOptions.Value;
        _points = points;
        _helix = helix;
        _chaosSettings = chaosSettings;
        _skyrim = skyrim;
        _overlay = overlay;

        // Surfaces whether a queued command actually succeeded once Papyrus
        // executed it — previously the only visible signal was "Queued
        // chaos command X", with no way to tell success from silent
        // failure without watching the game itself.
        _skyrim.EventReceived += OnSkyrimEventReceived;
    }

    private void OnSkyrimEventReceived(OutboundEvent evt)
    {
        switch (evt.Kind)
        {
            case "command_result":
                if (evt.Success)
                {
                    _logger.LogInformation("Command {Id} succeeded: {Message}", evt.Id, evt.Message);
                }
                else
                {
                    _logger.LogWarning("Command {Id} FAILED: {Message}", evt.Id, evt.Message);
                }
                SendChatMessage(evt.Message);
                break;
            case "engine_event":
                _logger.LogInformation("Engine event: {Message}", evt.Message);
                break;
            case "settings_sync":
                _chaosSettings.Apply(evt.Data);
                _logger.LogInformation("Synced {Count} chaos setting(s) from Skyrim", evt.Data.Count);
                break;
        }
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
        _client.OnNewSubscriber += OnNewSubscriber;
        _client.OnReSubscriber += OnReSubscriber;
        _client.OnGiftedSubscription += OnGiftedSubscription;

        _client.Connect();

        stoppingToken.Register(() => _client.Disconnect());
        await Task.Delay(Timeout.Infinite, stoppingToken).ContinueWith(_ => { });
    }

    private async void OnMessageReceived(object? sender, OnMessageReceivedArgs e)
    {
        var chatMessage = e.ChatMessage;
        var message = chatMessage.Message.Trim();
        var viewer = chatMessage.Username;

        // Every message counts as activity, not just commands -- this is what
        // creates the account (at the right starting tier) and keeps
        // LastSeenUtc fresh for the passive-income activity window.
        var isPrivileged = chatMessage.IsBroadcaster || chatMessage.IsModerator || chatMessage.IsVip;
        var startingBalance = isPrivileged ? _pointsOptions.StartingBalanceVipModBroadcaster : _pointsOptions.StartingBalanceBase;
        await _points.RegisterActivityAsync(viewer, chatMessage.DisplayName, startingBalance);

        // Bits arrive as a tag on a regular chat message, not a separate
        // event (TwitchLib.Client has no OnBitsReceived for IRC-sourced
        // cheers -- confirmed against the library source for the pinned
        // TwitchLib.Client version before writing this).
        if (chatMessage.Bits > 0)
        {
            await _points.GrantBitsAsync(viewer, chatMessage.Bits);
            _logger.LogInformation("{Viewer} cheered {Bits} bits", viewer, chatMessage.Bits);
        }

        // Follow status has no chat badge/tag (Twitch removed it from IRC in
        // 2023), so it's checked out-of-band via Helix, throttled, and only
        // for viewers who didn't already start at the top tier.
        if (!isPrivileged && await _points.ShouldCheckFollowBonusAsync(viewer))
        {
            _ = CheckFollowBonusAsync(viewer);
        }

        if (message.StartsWith("!buy ", StringComparison.OrdinalIgnoreCase))
        {
            var action = message["!buy ".Length..].Trim().ToLowerInvariant();
            await HandleBuyCommandAsync(viewer, action);
        }
        else if (message.StartsWith("!give ", StringComparison.OrdinalIgnoreCase))
        {
            await HandleGiveCommandAsync(chatMessage);
        }
        // !vote 1/2/3 handling lives in PollEngine once wired in (Phase 4 of
        // docs/IMPLEMENTATION_PLAN.md); TwitchIrcService only owns the raw
        // chat parsing entry point.
    }

    // Deliberately not awaited at the call site -- a follow lookup is a
    // network round-trip and must never block chat message processing.
    // Failures already degrade to "no bonus" inside HelixApiService, so
    // there's nothing worth surfacing back to the caller here beyond a log.
    private async Task CheckFollowBonusAsync(string viewer)
    {
        try
        {
            if (await _helix.IsFollowingAsync(viewer))
            {
                if (await _points.TryGrantFollowBonusAsync(viewer))
                {
                    _logger.LogInformation("{Viewer} confirmed as a follower; follow bonus granted", viewer);
                }
            }
        }
        finally
        {
            await _points.MarkFollowCheckedAsync(viewer);
        }
    }

    // Prime counts as tier 1, same as WaterparkSimTwitchExpansion's PointsManager.
    private static int TierValue(TwitchLib.Client.Enums.SubscriptionPlan plan) => plan switch
    {
        TwitchLib.Client.Enums.SubscriptionPlan.Tier2 => 2,
        TwitchLib.Client.Enums.SubscriptionPlan.Tier3 => 3,
        _ => 1,
    };

    private async void OnNewSubscriber(object? sender, OnNewSubscriberArgs e)
    {
        var tier = TierValue(e.Subscriber.SubscriptionPlan);
        await _points.GrantSubAsync(e.Subscriber.Login, tier);
        SendChatMessage($"Thanks for subscribing, {e.Subscriber.DisplayName}!");
        _logger.LogInformation("{Viewer} subscribed (tier {Tier})", e.Subscriber.Login, tier);
    }

    private async void OnReSubscriber(object? sender, OnReSubscriberArgs e)
    {
        var tier = TierValue(e.ReSubscriber.SubscriptionPlan);
        await _points.GrantSubAsync(e.ReSubscriber.Login, tier);
        SendChatMessage($"Thanks for resubscribing, {e.ReSubscriber.DisplayName}!");
        _logger.LogInformation("{Viewer} resubscribed (tier {Tier})", e.ReSubscriber.Login, tier);
    }

    // Fires once per recipient -- a mass/community gift of N shows up as N of
    // these, so no separate OnCommunitySubscription handling is needed to
    // pay out the gifter correctly.
    private async void OnGiftedSubscription(object? sender, OnGiftedSubscriptionArgs e)
    {
        var gift = e.GiftedSubscription;
        if (gift.IsAnonymous)
        {
            return; // no real gifter account to credit
        }

        var tier = TierValue(gift.MsgParamSubPlan);
        await _points.GrantGiftedSubAsync(gift.Login, tier);
        _logger.LogInformation("{Gifter} gifted a sub (tier {Tier}) to {Recipient}", gift.Login, tier, gift.MsgParamRecipientUserName);
    }

    private static readonly Dictionary<string, string> ActionPriceKeys = new(StringComparer.OrdinalIgnoreCase)
    {
        ["ragdoll"] = "chaos.ragdoll.price",
        ["earthquake"] = "chaos.earthquake.price",
        ["dragon"] = "chaos.spawn_dragon.price",
        ["chickens"] = "chaos.spawn_chickens.price",
        ["invert"] = "chaos.invert_controls.price",
        ["lowgravity"] = "chaos.low_gravity.price",
        ["yeet"] = "chaos.yeet.price",
        ["addgold"] = "chaos.add_gold.price",
        ["removegold"] = "chaos.remove_gold.price",
        ["cheese"] = "chaos.spawn_cheese.price",
        ["cheesemageddon"] = "chaos.cheese_mageddon.price",
        ["give10gold"] = "chaos.give_10_gold.price",
        ["give100gold"] = "chaos.give_100_gold.price",
        ["give1000gold"] = "chaos.give_1000_gold.price",
        ["giveapples"] = "chaos.give_apples.price",
        ["givearrows"] = "chaos.give_arrows.price",
        ["givebakedpotatoes"] = "chaos.give_baked_potatoes.price",
        ["givediamond"] = "chaos.give_diamond.price",
        ["givedragonbone"] = "chaos.give_dragon_bone.price",
        ["givedragonscales"] = "chaos.give_dragon_scales.price",
        ["givegoldingot"] = "chaos.give_gold_ingot.price",
        ["giveironingot"] = "chaos.give_iron_ingot.price",
        ["givepotatoes"] = "chaos.give_potatoes.price",
        ["givesilveringot"] = "chaos.give_silver_ingot.price",
        ["givesoulgem"] = "chaos.give_soul_gem_common.price",
        ["scrollblizzard"] = "chaos.scroll_blizzard.price",
        ["scrollflameatronach"] = "chaos.scroll_conjure_flame_atronach.price",
        ["scrollfrostatronach"] = "chaos.scroll_conjure_frost_atronach.price",
        ["scrollstormatronach"] = "chaos.scroll_conjure_storm_atronach.price",
        ["scrollflamethrall"] = "chaos.scroll_flame_thrall.price",
        ["scrollfrostthrall"] = "chaos.scroll_frost_thrall.price",
        ["scrollharmony"] = "chaos.scroll_harmony.price",
        ["scrollhysteria"] = "chaos.scroll_hysteria.price",
        ["scrollinvisibility"] = "chaos.scroll_invisibility.price",
        ["scrollmayhem"] = "chaos.scroll_mayhem.price",
        ["scrollstormthrall"] = "chaos.scroll_storm_thrall.price",
        ["scrollwaterbreathing"] = "chaos.scroll_water_breathing.price",
        ["superjump"] = "chaos.super_jump.price",
        ["ragdollblast"] = "chaos.ragdoll_blast.price",
        ["tinydovahkiin"] = "chaos.tiny_dovahkiin.price",
        ["giantdovahkiin"] = "chaos.giant_dovahkiin.price",
        ["drunkvision"] = "chaos.drunk_vision.price",
        ["wildmagic"] = "chaos.wild_magic.price",
        ["midasweight"] = "chaos.midas_weight.price",
        ["pocketchangeblast"] = "chaos.pocket_change_blast.price",
    };

    private static readonly Dictionary<string, string> ActionCommandTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        ["ragdoll"] = "ragdoll",
        ["earthquake"] = "earthquake",
        ["dragon"] = "spawn_dragon",
        ["chickens"] = "spawn_chickens",
        ["invert"] = "invert_controls",
        ["lowgravity"] = "low_gravity",
        ["yeet"] = "yeet",
        ["addgold"] = "add_gold",
        ["removegold"] = "remove_gold",
        ["cheese"] = "spawn_cheese",
        ["cheesemageddon"] = "cheese_mageddon",
        ["give10gold"] = "give_10_gold",
        ["give100gold"] = "give_100_gold",
        ["give1000gold"] = "give_1000_gold",
        ["giveapples"] = "give_apples",
        ["givearrows"] = "give_arrows",
        ["givebakedpotatoes"] = "give_baked_potatoes",
        ["givediamond"] = "give_diamond",
        ["givedragonbone"] = "give_dragon_bone",
        ["givedragonscales"] = "give_dragon_scales",
        ["givegoldingot"] = "give_gold_ingot",
        ["giveironingot"] = "give_iron_ingot",
        ["givepotatoes"] = "give_potatoes",
        ["givesilveringot"] = "give_silver_ingot",
        ["givesoulgem"] = "give_soul_gem_common",
        ["scrollblizzard"] = "scroll_blizzard",
        ["scrollflameatronach"] = "scroll_conjure_flame_atronach",
        ["scrollfrostatronach"] = "scroll_conjure_frost_atronach",
        ["scrollstormatronach"] = "scroll_conjure_storm_atronach",
        ["scrollflamethrall"] = "scroll_flame_thrall",
        ["scrollfrostthrall"] = "scroll_frost_thrall",
        ["scrollharmony"] = "scroll_harmony",
        ["scrollhysteria"] = "scroll_hysteria",
        ["scrollinvisibility"] = "scroll_invisibility",
        ["scrollmayhem"] = "scroll_mayhem",
        ["scrollstormthrall"] = "scroll_storm_thrall",
        ["scrollwaterbreathing"] = "scroll_water_breathing",
        ["superjump"] = "super_jump",
        ["ragdollblast"] = "ragdoll_blast",
        ["tinydovahkiin"] = "tiny_dovahkiin",
        ["giantdovahkiin"] = "giant_dovahkiin",
        ["drunkvision"] = "drunk_vision",
        ["wildmagic"] = "wild_magic",
        ["midasweight"] = "midas_weight",
        ["pocketchangeblast"] = "pocket_change_blast",
    };

    // Used only until the first settings_sync arrives from Skyrim (or if the
    // game/plugin never connects at all) -- kept identical to
    // SKSEPlugin/src/Settings/Settings.cpp's own defaults so pricing is
    // sane either way, live-synced or not.
    private static readonly Dictionary<string, int> DefaultPrices = new(StringComparer.OrdinalIgnoreCase)
    {
        ["ragdoll"] = 50,
        ["earthquake"] = 150,
        ["dragon"] = 1000,
        ["chickens"] = 200,
        ["invert"] = 300,
        ["lowgravity"] = 400,
        ["yeet"] = 120,
        ["addgold"] = 50,
        ["removegold"] = 150,
        ["cheese"] = 75,
        ["cheesemageddon"] = 150,
        ["give10gold"] = 10,
        ["give100gold"] = 100,
        ["give1000gold"] = 1000,
        ["giveapples"] = 20,
        ["givearrows"] = 40,
        ["givebakedpotatoes"] = 20,
        ["givediamond"] = 300,
        ["givedragonbone"] = 150,
        ["givedragonscales"] = 150,
        ["givegoldingot"] = 100,
        ["giveironingot"] = 30,
        ["givepotatoes"] = 15,
        ["givesilveringot"] = 60,
        ["givesoulgem"] = 120,
        ["scrollblizzard"] = 200,
        ["scrollflameatronach"] = 150,
        ["scrollfrostatronach"] = 150,
        ["scrollstormatronach"] = 200,
        ["scrollflamethrall"] = 180,
        ["scrollfrostthrall"] = 180,
        ["scrollharmony"] = 250,
        ["scrollhysteria"] = 250,
        ["scrollinvisibility"] = 220,
        ["scrollmayhem"] = 300,
        ["scrollstormthrall"] = 220,
        ["scrollwaterbreathing"] = 100,
        ["superjump"] = 150,
        ["ragdollblast"] = 200,
        ["tinydovahkiin"] = 150,
        ["giantdovahkiin"] = 200,
        ["drunkvision"] = 120,
        ["wildmagic"] = 250,
        ["midasweight"] = 180,
        ["pocketchangeblast"] = 100,
    };

    private async Task HandleBuyCommandAsync(string viewer, string action)
    {
        if (!ActionCommandTypes.TryGetValue(action, out var commandType))
        {
            SendChatMessage($"@{viewer} unknown chaos action '{action}'.");
            return;
        }

        var price = _chaosSettings.GetInt(ActionPriceKeys[action], DefaultPrices[action]);

        if (!await _points.TrySpendAsync(viewer, price))
        {
            SendChatMessage($"@{viewer} you don't have enough points for {action} ({price} needed).");
            return;
        }

        var command = new ChaosCommand
        {
            Type = commandType,
            Viewer = viewer,
            Price = price,
        };

        await _skyrim.SendAsync(command);
        await _overlay.BroadcastAsync(new { type = "toast", text = $"{viewer} bought {action}!" });
        _logger.LogInformation("Queued chaos command {Type} from {Viewer} for {Price} points", commandType, viewer, price);
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
