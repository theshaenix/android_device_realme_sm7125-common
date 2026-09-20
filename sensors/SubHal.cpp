// SPDX-License-Identifier: Apache-2.0

#include <V2_0/SubHal.h>
#include <dlfcn.h>
#include <log/log.h>

#include <algorithm>
#include <cctype>
#include <mutex>
#include <string>
#include <unordered_map>
#include <utility>

#include "Batch.h"

namespace realme::sensors {

using ::android::sp;
using namespace ::android::hardware;
using namespace ::android::hardware::sensors::V1_0;
using ::android::hardware::sensors::V2_0::implementation::IHalProxyCallback;
using ::android::hardware::sensors::V2_0::implementation::ISensorsSubHal;

class SubHal final : public ISensorsSubHal {
  public:
    explicit SubHal(ISensorsSubHal* delegate) : delegate_(delegate) {}

    Return<void> getSensorsList(getSensorsList_cb callback) override {
        return delegate_->getSensorsList([&](const hidl_vec<SensorInfo>& sensors) {
            std::unordered_map<int32_t, int64_t> polling;
            for (const auto& sensor : sensors) {
                std::string name = sensor.name.c_str();
                std::transform(name.begin(), name.end(), name.begin(),
                               [](unsigned char c) { return std::tolower(c); });
                const bool motion = sensor.type == SensorType::ACCELEROMETER ||
                                    sensor.type == SensorType::ACCELEROMETER_UNCALIBRATED ||
                                    sensor.type == SensorType::GYROSCOPE ||
                                    sensor.type == SensorType::GYROSCOPE_UNCALIBRATED;
                if (motion && name.find("bmi160") != std::string::npos && sensor.minDelay > 0) {
                    polling.emplace(sensor.sensorHandle, int64_t{sensor.minDelay} * 1000);
                }
            }
            {
                std::lock_guard<std::mutex> lock(mutex_);
                polling_ = std::move(polling);
            }
            callback(sensors);
        });
    }

    Return<Result> batch(int32_t handle, int64_t periodNs, int64_t latencyNs) override {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            const auto it = polling_.find(handle);
            if (it != polling_.end() && periodNs > 0) {
                latencyNs = batchLatency(true, std::max(periodNs, it->second), latencyNs);
            }
        }
        return delegate_->batch(handle, periodNs, latencyNs);
    }

    Return<Result> initialize(const sp<IHalProxyCallback>& callback) override {
        return delegate_->initialize(callback);
    }
    const std::string getName() override { return delegate_->getName(); }
    Return<Result> setOperationMode(OperationMode mode) override {
        return delegate_->setOperationMode(mode);
    }
    Return<Result> activate(int32_t handle, bool enabled) override {
        return delegate_->activate(handle, enabled);
    }
    Return<Result> flush(int32_t handle) override { return delegate_->flush(handle); }
    Return<Result> injectSensorData(const Event& event) override {
        return delegate_->injectSensorData(event);
    }
    Return<void> registerDirectChannel(const SharedMemInfo& memory,
                                      registerDirectChannel_cb callback) override {
        return delegate_->registerDirectChannel(memory, callback);
    }
    Return<Result> unregisterDirectChannel(int32_t handle) override {
        return delegate_->unregisterDirectChannel(handle);
    }
    Return<void> configDirectReport(int32_t sensor, int32_t channel, RateLevel rate,
                                   configDirectReport_cb callback) override {
        return delegate_->configDirectReport(sensor, channel, rate, callback);
    }
    Return<void> debug(const hidl_handle& fd, const hidl_vec<hidl_string>& args) override {
        return delegate_->debug(fd, args);
    }

  private:
    ISensorsSubHal* const delegate_;
    std::mutex mutex_;
    std::unordered_map<int32_t, int64_t> polling_;
};

}  // namespace realme::sensors

extern "C" ISensorsSubHal* sensorsHalGetSubHal(uint32_t* version) {
    static realme::sensors::SubHal subhal([] {
        // Keep the original library loaded for the lifetime of its static sub-HAL.
        void* library = dlopen("sensors.ssc.so", RTLD_NOW | RTLD_LOCAL);
        LOG_ALWAYS_FATAL_IF(!library, "Cannot load sensors.ssc.so: %s", dlerror());
        auto getSubHal = reinterpret_cast<ISensorsSubHal* (*)(uint32_t*)>(
                dlsym(library, "sensorsHalGetSubHal"));
        LOG_ALWAYS_FATAL_IF(!getSubHal, "SSC sub-HAL entry point missing");
        uint32_t delegateVersion = 0;
        ISensorsSubHal* delegate = getSubHal(&delegateVersion);
        LOG_ALWAYS_FATAL_IF(!delegate || delegateVersion != SUB_HAL_2_0_VERSION,
                            "Unsupported SSC sub-HAL version: %#x", delegateVersion);
        return delegate;
    }());
    *version = SUB_HAL_2_0_VERSION;
    return &subhal;
}
