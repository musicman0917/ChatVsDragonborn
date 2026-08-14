#pragma once

// Precompiled header — CommonLibSSE-NG + STL + third-party deps used across
// the plugin. Keep this list to things that genuinely change rarely; anything
// churny belongs in the .cpp that needs it.

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include <RE/Skyrim.h>
#include <REL/Relocation.h>
#include <SKSE/SKSE.h>

#include <nlohmann/json.hpp>
#include <spdlog/sinks/basic_file_sink.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <deque>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace logger = SKSE::log;
namespace json = nlohmann;

using namespace std::literals;
