using TwitchBridge.Logging;
using TwitchBridge.Services;

var builder = Host.CreateApplicationBuilder(args);

// The default host builder only wires up the User Secrets provider when
// the environment is "Development" — this runs as "Production" by default
// (no ASPNETCORE_ENVIRONMENT/DOTNET_ENVIRONMENT set), which silently
// ignored every `dotnet user-secrets set` value. This is a personal local
// tool with no real prod/dev split, so load user secrets unconditionally.
builder.Configuration.AddUserSecrets<Program>();

// One log file per session (logs/twitchbridge-<timestamp>.log), alongside
// the console output — lets you review what happened after a stream ends
// without having to keep the console window scrolled back.
var logPath = Path.Combine("logs", $"twitchbridge-{DateTime.Now:yyyyMMdd-HHmmss}.log");
builder.Logging.AddProvider(new FileLoggerProvider(logPath));

builder.Services.Configure<TwitchOptions>(builder.Configuration.GetSection("Twitch"));
builder.Services.Configure<PointsOptions>(builder.Configuration.GetSection("Points"));
builder.Services.Configure<SkyrimBridgeOptions>(builder.Configuration.GetSection("Skyrim"));
builder.Services.Configure<OverlayOptions>(builder.Configuration.GetSection("Overlay"));

builder.Services.AddSingleton<PointsEconomyService>();
builder.Services.AddSingleton<ModeratorTokenStore>();
builder.Services.AddSingleton<HelixApiService>();
builder.Services.AddSingleton<ChaosSettingsCache>();
builder.Services.AddHostedService<PassiveIncomeService>();

// BackgroundServices that also need to be resolved as concrete singletons
// elsewhere (SkyrimIpcClient::SendAsync, OverlayHttpServer::BroadcastAsync)
// are registered both ways so DI hands out the same instance either path.
builder.Services.AddSingleton<SkyrimIpcClient>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<SkyrimIpcClient>());

builder.Services.AddSingleton<OverlayHttpServer>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<OverlayHttpServer>());

builder.Services.AddHostedService<TwitchIrcService>();

var host = builder.Build();

// Wire the SKSE plugin's command-result / engine-event stream straight into
// the overlay broadcast so toasts show up without extra plumbing.
var skyrim = host.Services.GetRequiredService<SkyrimIpcClient>();
var overlay = host.Services.GetRequiredService<OverlayHttpServer>();
skyrim.EventReceived += evt => _ = overlay.BroadcastAsync(new
{
    type = evt.Kind,
    id = evt.Id,
    success = evt.Success,
    message = evt.Message,
    data = evt.Data,
});

var points = host.Services.GetRequiredService<PointsEconomyService>();
await points.LoadAsync();

await host.RunAsync();
