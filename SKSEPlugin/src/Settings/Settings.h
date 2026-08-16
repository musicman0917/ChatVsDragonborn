#pragma once

namespace STE
{
    // Live-editable settings store. Backed by
    // Data/SKSE/Plugins/SkyrimTwitchExpansion.json (distinct from the .ini,
    // which only holds boot-time options like the pipe name / log level).
    // The MCM menu edits this through ChaosNativeFunctions::GetSetting/
    // SetSetting. TwitchBridge runs as a separate process with no fixed
    // relationship to the game's install directory, so rather than also
    // reading this file directly (a second Windows-path/working-directory
    // footgun on top of the ones already hit getting the plugin itself
    // launching correctly), the plugin instead pushes a "settings_sync"
    // OutboundEvent over the existing pipe -- on every TwitchBridge
    // (re)connect, and again whenever SetSetting changes a chaos.* key --
    // so both sides observe changes without a restart via the one transport
    // they already share.
    class Settings
    {
    public:
        static Settings& Get()
        {
            static Settings instance;
            return instance;
        }

        void Load();
        void Save();

        [[nodiscard]] std::string GetString(const std::string& key, std::string defaultValue = "") const;
        void SetString(const std::string& key, const std::string& value);

        // Settings are stored as strings (see GetString) so MCM/JSON edits
        // stay simple; this just parses that string for callers (Papyrus,
        // via ChaosNativeFunctions::GetSettingInt) that want an int.
        [[nodiscard]] int GetInt(const std::string& key, int defaultValue = 0) const;

        // All key/value pairs whose key starts with `prefix`, as a JSON
        // object of strings. Used to build the settings_sync payload (see
        // class comment above) without exposing the whole store.
        [[nodiscard]] json::json GetAllWithPrefix(const std::string& prefix) const;

    private:
        Settings() = default;

        mutable std::mutex _mutex;
        json::json _values;
        std::filesystem::path _path;
    };
}
