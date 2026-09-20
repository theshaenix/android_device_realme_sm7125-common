#include "../Uevent.h"
#include <cassert>
#include <string>
int main() {
    const auto event = [](std::string name, std::string temperature) {
        std::string s;
        for (const auto& field : {std::string("change@/devices/virtual/thermal/thermal_zone9"),
             std::string("SUBSYSTEM=thermal"), "NAME=" + name, "TEMP=" + temperature,
             std::string("TRIP=0"), std::string("EVENT=1")}) { s += field; s += '\0'; }
        return s;
    };
    auto s = event("cpu-0-0-usr", "95000");
    auto r = parseThermalUevent(s);
    assert(r && r->first == "cpu-0-0-usr" && r->second == 95000);
    assert(!parseThermalUevent(event(std::string(100, 'x'), "1")));
    assert(!parseThermalUevent(event("cpu", "2147483648")));
    assert(!parseThermalUevent(event("cpu", "12junk")));
    assert(!parseThermalUevent(s.substr(0, s.size() - 1)));
    assert(!parseThermalUevent(std::string("SUBSYSTEM=thermal\0NAME=cpu\0", 27)));
    s.replace(s.find("TRIP=0"), 6, "HYST=1");
    assert(parseThermalUevent(s));
}
