using System.Text.Json;

namespace TwitchBridge.Services;

/// <summary>
/// Caches the chaos.* settings (prices, gold amounts, effect durations) the
/// SKSE plugin pushes over the pipe as a "settings_sync" OutboundEvent --
/// see SKSEPlugin/src/Settings/Settings.h for why this arrives over IPC
/// instead of TwitchBridge reading the plugin's settings JSON file
/// directly. Populated on every Skyrim (re)connect and again whenever an
/// MCM edit changes a chaos.* key, so !buy prices track the in-game menu
/// live. Before the first sync arrives -- or if the game/plugin is never
/// running at all -- GetInt falls back to the caller's default, which
/// callers should keep matching SKSEPlugin/src/Settings/Settings.cpp's own
/// defaults so behavior is sane either way.
/// </summary>
public sealed class ChaosSettingsCache
{
    private readonly object _lock = new();
    private readonly Dictionary<string, string> _values = new(StringComparer.OrdinalIgnoreCase);

    public void Apply(IReadOnlyDictionary<string, object?> data)
    {
        lock (_lock)
        {
            foreach (var (key, value) in data)
            {
                if (value is JsonElement { ValueKind: JsonValueKind.String } element)
                {
                    _values[key] = element.GetString() ?? "";
                }
            }
        }
    }

    public int GetInt(string key, int defaultValue)
    {
        lock (_lock)
        {
            return _values.TryGetValue(key, out var raw) && int.TryParse(raw, out var parsed)
                ? parsed
                : defaultValue;
        }
    }
}
