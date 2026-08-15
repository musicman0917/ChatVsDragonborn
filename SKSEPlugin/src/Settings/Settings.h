#pragma once

namespace STE
{
    // Live-editable settings store. Backed by
    // Data/SKSE/Plugins/SkyrimTwitchExpansion.json (distinct from the .ini,
    // which only holds boot-time options like the pipe name / log level).
    // Both the MCM menu (via ChaosNativeFunctions::GetSetting/SetSetting) and
    // TwitchBridge (reading the same file) observe changes without a restart.
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

    private:
        Settings() = default;

        mutable std::mutex _mutex;
        json::json _values;
        std::filesystem::path _path;
    };
}
