namespace TwitchBridge.Models;

public sealed class PollCandidate
{
    public required int Ballot { get; init; }
    public required string ChaosType { get; init; }
    public required string DisplayName { get; init; }
    public int Votes { get; set; }
}

public sealed class PollState
{
    public bool IsActive { get; set; }
    public DateTimeOffset OpenedAt { get; set; }
    public DateTimeOffset ClosesAt { get; set; }
    public List<PollCandidate> Candidates { get; init; } = new();

    /// <summary>Twitch usernames that have already voted this round, to prevent double voting.</summary>
    public HashSet<string> VotedUsernames { get; } = new(StringComparer.OrdinalIgnoreCase);
}
