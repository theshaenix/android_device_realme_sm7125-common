#pragma once

#include <cstdint>
#include <limits>

namespace realme::sensors {

// The polling BMI160 firmware drains its FIFO only for batches longer than
// one sample. Keep explicit batching requests and invalid inputs unchanged.
inline int64_t batchLatency(bool pollingSensor, int64_t periodNs, int64_t latencyNs) {
    if (!pollingSensor || periodNs <= 0 || latencyNs != 0) return latencyNs;
    const int64_t halfPeriod = periodNs / 2 + periodNs % 2;
    const int64_t limit = std::numeric_limits<int64_t>::max();
    return periodNs > limit - halfPeriod ? limit : periodNs + halfPeriod;
}

}  // namespace realme::sensors
