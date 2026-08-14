using System.Text.Json.Serialization;

namespace TwitchBridge.Models;

/// <summary>
/// Mirrors SKSEPlugin/src/Bridge/Protocol.h ChaosCommand. Serialized as one
/// JSON line and written to the named pipe the SKSE plugin listens on. Keep
/// both sides in sync manually — there is no shared IDL step in this scaffold.
/// </summary>
public sealed class ChaosCommand
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = Guid.NewGuid().ToString("N");

    [JsonPropertyName("type")]
    public required string Type { get; init; }

    [JsonPropertyName("viewer")]
    public required string Viewer { get; init; }

    [JsonPropertyName("price")]
    public int Price { get; init; }

    [JsonPropertyName("args")]
    public Dictionary<string, object?> Args { get; init; } = new();
}

/// <summary>Mirrors SKSEPlugin/src/Bridge/Protocol.h OutboundEvent.</summary>
public sealed class OutboundEvent
{
    [JsonPropertyName("kind")]
    public string Kind { get; init; } = "";

    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("success")]
    public bool Success { get; init; }

    [JsonPropertyName("message")]
    public string Message { get; init; } = "";

    [JsonPropertyName("data")]
    public Dictionary<string, object?> Data { get; init; } = new();
}
