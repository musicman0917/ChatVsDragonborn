using TwitchBridge.Services;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.Configure<TwitchOptions>(builder.Configuration.GetSection("Twitch"));
builder.Services.Configure<PointsOptions>(builder.Configuration.GetSection("Points"));
builder.Services.Configure<SkyrimBridgeOptions>(builder.Configuration.GetSection("Skyrim"));
builder.Services.Configure<OverlayOptions>(builder.Configuration.GetSection("Overlay"));

builder.Services.AddSingleton<PointsEconomyService>();
builder.Services.AddSingleton<HelixApiService>();

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
