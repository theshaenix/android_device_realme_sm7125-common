#! /vendor/bin/sh

# Copyright (c) 2012-2013, 2016-2020, The Linux Foundation. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of The Linux Foundation nor
#       the names of its contributors may be used to endorse or promote
#       products derived from this software without specific prior written
#       permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NON-INFRINGEMENT ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# Changes from Qualcomm Innovation Center are provided under the following license:
# Copyright (c) 2022 Qualcomm Innovation Center, Inc. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause-Clear
#

function configure_read_ahead_kb_values() {
    # Atoll uses UFS, not mmcblk. Large 512 KB readahead wastes page cache on
    # random app workloads; 128 KB keeps useful pages resident for longer.
    for read_ahead in /sys/block/sd*/queue/read_ahead_kb \
                      /sys/block/dm-*/queue/read_ahead_kb; do
        [ -f "$read_ahead" ] && echo 128 > "$read_ahead"
    done
}

function configure_memory_parameters() {
    # Unified memory configuration for Atoll device (Realme 6 Pro: 6GB/8GB RAM)
    # Combines ZRAM setup and memory management parameters
    
    MemTotalStr=`cat /proc/meminfo | grep MemTotal`
    MemTotal=${MemTotalStr:16:8}
    
    echo 100 > /proc/sys/vm/swappiness
    echo 100 > /proc/sys/vm/direct_swappiness
    echo 0 > /proc/sys/vm/page-cluster

    # This oneshot can be started in charger mode and again after boot. Never
    # format an active swap device a second time.
    if [ -f /sys/block/zram0/disksize ] &&
       ! grep -q '[/]zram0' /proc/swaps 2>/dev/null; then
        # The live device uses far less than the available 4 GB swap. Prefer
        # low-latency compression over zstd's unused extra density.
        echo lz4 > /sys/block/zram0/comp_algorithm

        if [ -f /sys/block/zram0/use_dedup ]; then
            echo 0 > /sys/block/zram0/use_dedup
        fi
        
        # Configure ZRAM size based on total RAM
        if [ $MemTotal -le 4194304 ]; then
            # 4GB RAM: 2.5GB ZRAM
            echo 2684354560 > /sys/block/zram0/disksize
        elif [ $MemTotal -le 6291456 ]; then
            # 6GB RAM: 3GB ZRAM
            echo 3221225472 > /sys/block/zram0/disksize
        elif [ $MemTotal -le 8388608 ]; then
            # 8GB RAM: 4GB ZRAM
            echo 4294967296 > /sys/block/zram0/disksize
        else
            # 12GB+ RAM: 5GB ZRAM
            echo 5368709120 > /sys/block/zram0/disksize
        fi
        
        # Initialize and enable ZRAM swap
        mkswap /dev/block/zram0 && swapon /dev/block/zram0 -p 32758
    fi

    # Set global VM parameters
    # wsf was forced to 1 (laziest reclaim -> kswapd wakes late -> direct-reclaim
    # stalls/jank). Keep the upstream default distance so short-lived allocation
    # bursts do not look like sustained low-memory pressure to userspace lmkd.
    echo 10 > /proc/sys/vm/watermark_scale_factor
    
    # Configure read-ahead values
    configure_read_ahead_kb_values
    
}

# Core control parameters on silver
echo 0 0 0 0 1 1 > /sys/devices/system/cpu/cpu0/core_ctl/not_preferred
echo 4 > /sys/devices/system/cpu/cpu0/core_ctl/min_cpus
echo 60 > /sys/devices/system/cpu/cpu0/core_ctl/busy_up_thres
echo 40 > /sys/devices/system/cpu/cpu0/core_ctl/busy_down_thres
echo 100 > /sys/devices/system/cpu/cpu0/core_ctl/offline_delay_ms
echo 8 > /sys/devices/system/cpu/cpu0/core_ctl/task_thres
echo 0 > /sys/devices/system/cpu/cpu6/core_ctl/enable

# Setting b.L scheduler parameters
# default sched up and down migrate values are 95 and 85
echo 65 > /proc/sys/kernel/sched_downmigrate
echo 71 > /proc/sys/kernel/sched_upmigrate
# default sched up and down migrate values are 100 and 95
echo 85 > /proc/sys/kernel/sched_group_downmigrate
echo 100 > /proc/sys/kernel/sched_group_upmigrate
echo 1 > /proc/sys/kernel/sched_walt_rotate_big_tasks

# Colocation v3 settings
echo 740000 > /proc/sys/kernel/sched_little_cluster_coloc_fmin_khz

# Configure governor settings for little cluster
echo "schedutil" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
echo 500 > /sys/devices/system/cpu/cpu0/cpufreq/schedutil/up_rate_limit_us
echo 20000 > /sys/devices/system/cpu/cpu0/cpufreq/schedutil/down_rate_limit_us
echo 1248000 > /sys/devices/system/cpu/cpu0/cpufreq/schedutil/hispeed_freq
echo 576000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq

# Configure governor settings for big cluster
echo "schedutil" > /sys/devices/system/cpu/cpu6/cpufreq/scaling_governor
echo 500 > /sys/devices/system/cpu/cpu6/cpufreq/schedutil/up_rate_limit_us
echo 20000 > /sys/devices/system/cpu/cpu6/cpufreq/schedutil/down_rate_limit_us
echo 1267200 > /sys/devices/system/cpu/cpu6/cpufreq/schedutil/hispeed_freq
echo 652800 > /sys/devices/system/cpu/cpu6/cpufreq/scaling_min_freq

# sched_load_boost as -6 is equivalent to target load as 85. It is per cpu tunable.
echo -6 > /sys/devices/system/cpu/cpu6/sched_load_boost
echo -6 > /sys/devices/system/cpu/cpu7/sched_load_boost
echo 85 > /sys/devices/system/cpu/cpu6/cpufreq/schedutil/hispeed_load

# Conservative predictive-load OFF: was a power-save lean that damps the freq ramp.
# Off = scheduler uses full WALT prediction -> quicker ramp, snappier (minor battery cost).
echo 0 > /proc/sys/kernel/sched_conservative_pl

# Input boost: also wake the big cluster (cpu6) on touch, not just little (cpu0). 1267200
# is the big-cluster hispeed OPP -> snappier app launch / touch without slamming to 2.3GHz max.
echo "0:1248000 6:1267200" > /sys/module/cpu_boost/parameters/input_boost_freq
echo 40 > /sys/module/cpu_boost/parameters/input_boost_ms

# Set Memory parameters
configure_memory_parameters

# Enable bus-dcvs
for device in /sys/devices/platform/soc
do
    for cpubw in $device/*cpu-cpu-llcc-bw/devfreq/*cpu-cpu-llcc-bw
    do
        echo "bw_hwmon" > $cpubw/governor
        echo "2288 4577 7110 9155 12298 14236" > $cpubw/bw_hwmon/mbps_zones
        echo 4 > $cpubw/bw_hwmon/sample_ms
        echo 68 > $cpubw/bw_hwmon/io_percent
        echo 20 > $cpubw/bw_hwmon/hist_memory
        echo 0 > $cpubw/bw_hwmon/hyst_length
        echo 80 > $cpubw/bw_hwmon/down_thres
        echo 0 > $cpubw/bw_hwmon/guard_band_mbps
        echo 250 > $cpubw/bw_hwmon/up_scale
        echo 1600 > $cpubw/bw_hwmon/idle_mbps
        echo 50 > $cpubw/polling_interval
    done

    for llccbw in $device/*cpu-llcc-ddr-bw/devfreq/*cpu-llcc-ddr-bw
    do
        echo "bw_hwmon" > $llccbw/governor
        echo "1144 1720 2086 2929 3879 5931 6881 8137" > $llccbw/bw_hwmon/mbps_zones
        echo 4 > $llccbw/bw_hwmon/sample_ms
        echo 68 > $llccbw/bw_hwmon/io_percent
        echo 20 > $llccbw/bw_hwmon/hist_memory
        echo 0 > $llccbw/bw_hwmon/hyst_length
        echo 80 > $llccbw/bw_hwmon/down_thres
        echo 0 > $llccbw/bw_hwmon/guard_band_mbps
        echo 250 > $llccbw/bw_hwmon/up_scale
        echo 1600 > $llccbw/bw_hwmon/idle_mbps
        echo 40 > $llccbw/polling_interval
    done

    for npubw in $device/*npu*-npu-ddr-bw/devfreq/*npu*-npu-ddr-bw
    do
        echo 1 > /sys/devices/virtual/npu/msm_npu/pwr
        echo "bw_hwmon" > $npubw/governor
        echo "1144 1720 2086 2929 3879 5931 6881 8137" > $npubw/bw_hwmon/mbps_zones
        echo 4 > $npubw/bw_hwmon/sample_ms
        echo 80 > $npubw/bw_hwmon/io_percent
        echo 20 > $npubw/bw_hwmon/hist_memory
        echo 10 > $npubw/bw_hwmon/hyst_length
        echo 30 > $npubw/bw_hwmon/down_thres
        echo 0 > $npubw/bw_hwmon/guard_band_mbps
        echo 250 > $npubw/bw_hwmon/up_scale
        echo 0 > $npubw/bw_hwmon/idle_mbps
        echo 40 > $npubw/polling_interval
        echo 0 > /sys/devices/virtual/npu/msm_npu/pwr
    done
done

# memlat specific settings are moved to separate file under
# device/target specific folder
setprop vendor.dcvs.prop 1

# cpuset parameters for power save
echo 0-3 > /dev/cpuset/background/cpus
echo 0-5 > /dev/cpuset/system-background/cpus

# Turn off scheduler boost at the end
echo 0 > /proc/sys/kernel/sched_boost

# Turn on sleep modes
echo 0 > /sys/module/lpm_levels/parameters/sleep_disabled

# Use deadline on all UFS LUNs (matches kernel default). noop does no request
# reordering -> worse read tail-latency / "feels slow initially" on UFS. Cover sda-sdf,
# not just sda, so every LUN (incl. the one backing /data) gets the better scheduler.
for q in /sys/block/sd*/queue/scheduler; do echo deadline > $q; done

# ---- GPU (Adreno 618) tuning ----
# Stock had NO gpu governor setup, leaving the Adreno on raw defaults. Keep the correct
# msm-adreno-tz governor but bias it to ramp sooner and hold clocks a touch longer between
# frames -> smoother 90Hz scroll/animation + steadier game fps. Full pwrlevel range stays
# governor-controlled (no forced floor), so idle power is unchanged.
if [ -d /sys/class/kgsl/kgsl-3d0 ]; then
    echo msm-adreno-tz > /sys/class/kgsl/kgsl-3d0/devfreq/governor
    echo 2 > /sys/class/kgsl/kgsl-3d0/devfreq/adrenoboost   # 0..3; 2 = snappier ramp under load
    echo 100 > /sys/class/kgsl/kgsl-3d0/idle_timer          # ms; hold clocks slightly longer between bursts
    # adrenoboost is created root:root, so the RealmeParts "GPU boost" toggle
    # (uid system) can't write it. Hand the node to system so the app can.
    chown system system /sys/class/kgsl/kgsl-3d0/devfreq/adrenoboost
    chmod 0664 /sys/class/kgsl/kgsl-3d0/devfreq/adrenoboost
fi
