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
                { "chaos.add_gold.price", "50" },
                { "chaos.remove_gold.price", "150" },
                { "chaos.spawn_cheese.price", "75" },
                { "chaos.add_gold.amount", "100" },
                { "chaos.remove_gold.amount", "100" },
                { "chaos.give_10_gold.price", "10" },
                { "chaos.give_100_gold.price", "100" },
                { "chaos.give_1000_gold.price", "1000" },
                { "chaos.give_apples.price", "20" },
                { "chaos.give_arrows.price", "40" },
                { "chaos.give_baked_potatoes.price", "20" },
                { "chaos.give_diamond.price", "300" },
                { "chaos.give_dragon_bone.price", "150" },
                { "chaos.give_dragon_scales.price", "150" },
                { "chaos.give_gold_ingot.price", "100" },
                { "chaos.give_iron_ingot.price", "30" },
                { "chaos.give_potatoes.price", "15" },
                { "chaos.give_silver_ingot.price", "60" },
                { "chaos.give_soul_gem_common.price", "120" },
                { "chaos.scroll_blizzard.price", "200" },
                { "chaos.scroll_conjure_flame_atronach.price", "150" },
                { "chaos.scroll_conjure_frost_atronach.price", "150" },
                { "chaos.scroll_conjure_storm_atronach.price", "200" },
                { "chaos.scroll_flame_thrall.price", "180" },
                { "chaos.scroll_frost_thrall.price", "180" },
                { "chaos.scroll_harmony.price", "250" },
                { "chaos.scroll_hysteria.price", "250" },
                { "chaos.scroll_invisibility.price", "220" },
                { "chaos.scroll_mayhem.price", "300" },
                { "chaos.scroll_storm_thrall.price", "220" },
                { "chaos.scroll_water_breathing.price", "100" },
                { "chaos.cheese_splosion.price", "150" },
                { "chaos.yeet.price", "120" },
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

    int Settings::GetInt(const std::string& key, int defaultValue) const
    {
        const auto raw = GetString(key);
        if (raw.empty()) {
            return defaultValue;
        }
        try {
            return std::stoi(raw);
        } catch (const std::exception&) {
            return defaultValue;
        }
    }

    json::json Settings::GetAllWithPrefix(const std::string& prefix) const
    {
        std::lock_guard lock(_mutex);
        auto result = json::json::object();
        for (const auto& [key, value] : _values.items()) {
            if (key.rfind(prefix, 0) == 0 && value.is_string()) {
                result[key] = value;
            }
        }
        return result;
    }
}
