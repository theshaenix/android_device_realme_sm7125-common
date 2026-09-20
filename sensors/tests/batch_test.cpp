#include "../Batch.h"

#include <cassert>
#include <limits>

int main() {
    using realme::sensors::batchLatency;
    assert(batchLatency(true, 20000000, 0) == 30000000);
    assert(batchLatency(true, 5000000, 0) == 7500000);
    assert(batchLatency(true, 1, 0) == 2);
    assert(batchLatency(true, 3, 0) == 5);
    assert(batchLatency(true, 20000000, 100000000) == 100000000);
    assert(batchLatency(false, 20000000, 0) == 0);
    assert(batchLatency(true, 0, 0) == 0);
    assert(batchLatency(true, -1, 0) == 0);
    assert(batchLatency(true, 20000000, -1) == -1);
    assert(batchLatency(true, std::numeric_limits<int64_t>::max(), 0) ==
           std::numeric_limits<int64_t>::max());
}
