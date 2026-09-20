# BMI160 batch compatibility

`sensors.realme_sm7125.so` implements the standard Multi-HAL 2.0 sub-HAL
interface and delegates to the shipped `sensors.ssc.so`. The installed SSC
library was checked to export the 2.0 `sensorsHalGetSubHal` entry point.

Only BMI160 accelerometer/gyroscope descriptors are selected. For those
sensors, a zero-latency batch request is translated to 1.5 sample periods,
using the descriptor's minimum period when necessary. Explicit batching,
unrelated sensors, activation, event callbacks, flushing, injection, and
direct-channel operations are passed through. No sensor is held active by
the adapter, and no root service or framework patch is required.

This compensates for the proprietary polling-mode firmware's FIFO delivery
behavior; it does not change interrupt routing or repair that firmware.
The added batching latency is intentional and must be measured on-device.

`common.mk` places the device hals.conf before the inherited vendor copy.
Android's PRODUCT_COPY_FILES processing keeps the first source for a given
destination. Verify the final image contains only `sensors.realme_sm7125.so`
in `/vendor/etc/sensors/hals.conf`, and retains the original SSC library.

Host regression check:

```sh
clang++ -std=c++17 -Wall -Wextra -Werror -fsanitize=undefined,address \
    sensors/tests/batch_test.cpp -o /tmp/realme-batch-test
/tmp/realme-batch-test
```

Build in the ROM checkout with `m sensors.realme_sm7125`. Before testing
the new ROM, disable the old `atoll_memfix` KernelSU module. Check
`dumpsys sensorservice`, gyro/accelerometer event timing, auto-rotation,
flush behavior, and suspend with the module disabled. A host helper test
does not verify the Android ABI or proprietary firmware behavior.
