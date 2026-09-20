#!/usr/bin/env python3
"""Compile the real hooks against a fake QTI backend; exercise fallback lifecycle."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as directory:
    d = Path(directory)
    headers = {
        'log/log.h': '#pragma once\n#define ALOGE(...) ((void)0)\n',
        'aidl/android/hardware/power/BnPower.h': '''#pragma once
namespace aidl::android::hardware::power {
enum class Mode { LAUNCH, OTHER }; enum class Boost { INTERACTION, OTHER };
}
''',
        'power-common.h': '''#pragma once
#define HINT_HANDLED 1
#define HINT_NONE 0
#define CHECK_HANDLE(h) ((h) > 0)
#define VENDOR_HINT_FIRST_LAUNCH_BOOST 1
#define LAUNCH_BOOST_V1 1
#define VENDOR_HINT_SCROLL_BOOST 2
#define SCROLL_VERTICAL 1
''',
        'hint-data.h': '', 'metadata-defs.h': '',
        'performance.h': '''#pragma once
extern int next_handle, requests, releases;
inline int perf_hint_enable_with_type(int, int, int) { ++requests; return next_handle; }
inline void release_request(int) { ++releases; }
''',
        'utils.h': '''#pragma once
#include <time.h>
inline long long calc_timespan_us(timespec, timespec) { return 1000000; }
''',
    }
    for name, text in headers.items():
        p = d / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
    source = '#include <cassert>\nextern "C" { int next_handle=-1, requests=0, releases=0; }\n'
    source += f'#include "{root / "mode-ext.cpp"}"\n#include "{root / "boost-ext.cpp"}"\n'
    source += '''
int main() {
    using namespace aidl::google::hardware::power::impl::pixel;
    using aidl::android::hardware::power::Mode;
    using aidl::android::hardware::power::Boost;
    assert(!setDeviceSpecificMode(Mode::LAUNCH, true));
    assert(!setDeviceSpecificMode(Mode::LAUNCH, false));
    assert(!setDeviceSpecificBoost(Boost::INTERACTION, 100));
    next_handle=7;
    assert(setDeviceSpecificMode(Mode::LAUNCH, true));
    assert(setDeviceSpecificMode(Mode::LAUNCH, false));
    assert(releases==1);
    assert(setDeviceSpecificBoost(Boost::INTERACTION, 100));
    assert(!setDeviceSpecificMode(Mode::OTHER, true));
}
'''
    (d / 'test.cpp').write_text(source)
    subprocess.run(['clang++', '-std=c++17', '-I', str(d), '-fsanitize=address,undefined',
                    str(d / 'test.cpp'), '-o', str(d / 'test')], check=True)
    subprocess.run([str(d / 'test')], check=True)
