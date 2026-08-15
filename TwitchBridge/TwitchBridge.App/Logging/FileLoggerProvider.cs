using System.Collections.Concurrent;

namespace TwitchBridge.Logging;

/// <summary>
/// Minimal file logging provider — writes every log line to a single
/// timestamped file for the session, alongside whatever's already going to
/// the console. Kept dependency-free (no Serilog/NLog): a plain append-only
/// text file is all a local companion app needs, and it mirrors the SKSE
/// plugin's own file logging (SKSEPlugin/src/main.cpp) so both halves of
/// the system leave a session log to review after the fact.
/// </summary>
public sealed class FileLoggerProvider : ILoggerProvider
{
    private readonly StreamWriter _writer;
    private readonly object _lock = new();
    private readonly ConcurrentDictionary<string, FileLogger> _loggers = new();

    public FileLoggerProvider(string filePath)
    {
        var directory = Path.GetDirectoryName(filePath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }
        _writer = new StreamWriter(filePath, append: false) { AutoFlush = true };
    }

    public ILogger CreateLogger(string categoryName)
        => _loggers.GetOrAdd(categoryName, name => new FileLogger(name, _writer, _lock));

    public void Dispose()
    {
        foreach (var logger in _loggers.Values)
        {
            logger.Dispose();
        }
        _writer.Dispose();
    }
}

internal sealed class FileLogger(string category, StreamWriter writer, object writeLock) : ILogger, IDisposable
{
    public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

    public bool IsEnabled(LogLevel logLevel) => logLevel != LogLevel.None;

    public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
    {
        if (!IsEnabled(logLevel))
        {
            return;
        }

        var line = $"[{DateTimeOffset.Now:HH:mm:ss}] [{logLevel}] {category}: {formatter(state, exception)}";
        if (exception is not null)
        {
            line += Environment.NewLine + exception;
        }

        lock (writeLock)
        {
            writer.WriteLine(line);
        }
    }

    public void Dispose() { }
}
