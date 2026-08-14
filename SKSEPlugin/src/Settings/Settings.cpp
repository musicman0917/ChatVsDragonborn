#include "Settings/Settings.h"

namespace STE
{
    void Settings::Load()
    {
        std::lock_guard lock(_mutex);

        _path = std::filesystem::path("Data/SKSE/Plugins/SkyrimTwitchExpansion.json");

        if (!std::filesystem::exists(_path)) {
            _values = json::json::object({
                { "chaos.earthquake.price", "150" },
                { "chaos.ragdoll.price", "50" },
                { "chaos.spawn_dragon.price", "1000" },
                { "chaos.spawn_chickens.price", "200" },
                { "chaos.invert_controls.price", "300" },
                { "chaos.invert_controls.duration_seconds", "20" },
                { "chaos.low_gravity.price", "400" },
                { "chaos.low_gravity.duration_seconds", "30" },
                { "poll.interval_minutes", "15" },
                { "poll.duration_seconds", "60" },
            });
            Save();
            return;
        }

        std::ifstream file(_path);
        if (!file) {
            logger::error("Settings::Load: could not open {}", _path.string());
            _values = json::json::object();
            return;
        }

        try {
            file >> _values;
        } catch (const std::exception& e) {
            logger::error("Settings::Load: failed to parse {}: {}", _path.string(), e.what());
            _values = json::json::object();
        }
    }

    void Settings::Save()
    {
        // NOTE: caller holds _mutex when invoked from SetString(); Load() also
        // holds it. Keep this method free of its own lock to avoid recursion.
        std::filesystem::create_directories(_path.parent_path());

        const auto tmpPath = _path.string() + ".tmp";
        {
            std::ofstream file(tmpPath);
            file << _values.dump(2);
        }
        std::filesystem::rename(tmpPath, _path);
    }

    std::string Settings::GetString(const std::string& key, std::string defaultValue) const
    {
        std::lock_guard lock(_mutex);
        if (auto it = _values.find(key); it != _values.end() && it->is_string()) {
            return it->get<std::string>();
        }
        return defaultValue;
    }

    void Settings::SetString(const std::string& key, const std::string& value)
    {
        std::lock_guard lock(_mutex);
        _values[key] = value;
        Save();
    }
}
