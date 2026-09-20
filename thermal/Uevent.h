// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <charconv>
#include <optional>
#include <string>
#include <string_view>
#include <utility>

inline std::optional<std::pair<std::string, int>> parseThermalUevent(std::string_view data) {
    if (data.empty() || data.size() >= 1024 || data.back() != '\0') return std::nullopt;
    std::string name;
    int temperature = 0;
    unsigned fields = 0;
    while (!data.empty()) {
        const auto end = data.find('\0');
        if (end == std::string_view::npos) return std::nullopt;
        const auto field = data.substr(0, end);
        data.remove_prefix(end + 1);
        const auto equals = field.find('=');
        if (equals == std::string_view::npos) continue;
        const auto key = field.substr(0, equals);
        const auto value = field.substr(equals + 1);
        unsigned bit = 0;
        if (key == "SUBSYSTEM") {
            if (value != "thermal") return std::nullopt;
            bit = 1;
        } else if (key == "NAME") {
            if (value.empty() || value.size() >= 30) return std::nullopt;
            name = value;
            bit = 2;
        } else if (key == "TEMP" || key == "TRIP" || key == "HYST" || key == "EVENT") {
            int number = 0;
            const auto parsed = std::from_chars(value.data(), value.data() + value.size(), number);
            if (parsed.ec != std::errc{} || parsed.ptr != value.data() + value.size())
                return std::nullopt;
            if (key == "TEMP") { temperature = number; bit = 4; }
            else if (key == "EVENT") bit = 8;
            else bit = 16;
        }
        if (fields & bit) return std::nullopt;
        fields |= bit;
    }
    if (fields != 31) return std::nullopt;
    return std::make_pair(name, temperature);
}
