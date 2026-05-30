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
    MemTotalStr=`cat /proc/meminfo | grep MemTotal`
    MemTotal=${MemTotalStr:16:8}

    dmpts=$(ls /sys/block/*/queue/read_ahead_kb | grep -e dm -e mmc)

    # Set 128 for <= 3GB &
    # set 512 for >= 4GB targets.
    if [ $MemTotal -le 3145728 ]; then
        echo 128 > /sys/block/mmcblk0/bdi/read_ahead_kb
        echo 128 > /sys/block/mmcblk0rpmb/bdi/read_ahead_kb
        for dm in $dmpts; do
            echo 128 > $dm
        done
    else
        echo 512 > /sys/block/mmcblk0/bdi/read_ahead_kb
        echo 512 > /sys/block/mmcblk0rpmb/bdi/read_ahead_kb
        for dm in $dmpts; do
            echo 512 > $dm
        done
    fi
}

function enable_swap() {
    # Enable swap if not already enabled
    if [ ! -f /proc/swaps ] || [ -z "$(cat /proc/swaps | grep zram0)" ]; then
        return 0
    fi
}

function configure_memory_parameters() {
    # Unified memory configuration for Atoll device (Realme 6 Pro: 6GB/8GB RAM)
    # Combines ZRAM setup and memory management parameters
    
    ProductName=`getprop ro.product.name`
    arch_type=`uname -m`
    MemTotalStr=`cat /proc/meminfo | grep MemTotal`
    MemTotal=${MemTotalStr:16:8}
    
    # Configure ZRAM parameters with LZ4 compression
    echo lz4 > /sys/block/zram0/comp_algorithm
    echo 100 > /proc/sys/vm/swappiness
    echo 60 > /proc/sys/vm/direct_swappiness
    echo 0 > /proc/sys/vm/page-cluster
    
    if [ -f /sys/block/zram0/disksize ]; then
        # Enable deduplication if available
        if [ -f /sys/block/zram0/use_dedup ]; then
            echo 1 > /sys/block/zram0/use_dedup
        fi
        
        # Configure ZRAM size based on total RAM
        if [ $MemTotal -le 4194304 ]; then
            # 4GB RAM: 2.5GB ZRAM
            echo 2684354560 > /sys/block/zram0/disksize
            echo 4 > /sys/module/lowmemorykiller/parameters/almk_totalram_ratio
        elif [ $MemTotal -le 6291456 ]; then
            # 6GB RAM: 3GB ZRAM
            echo 3221225472 > /sys/block/zram0/disksize
            echo 6 > /sys/module/lowmemorykiller/parameters/almk_totalram_ratio
        elif [ $MemTotal -le 8388608 ]; then
            # 8GB RAM: 4GB ZRAM
            echo 4294967296 > /sys/block/zram0/disksize
            echo 8 > /sys/module/lowmemorykiller/parameters/almk_totalram_ratio
        else
            # 12GB+ RAM: 5GB ZRAM
            echo 5368709120 > /sys/block/zram0/disksize
            echo 10 > /sys/module/lowmemorykiller/parameters/almk_totalram_ratio
        fi
        
        # Initialize and enable ZRAM swap
        mkswap /dev/block/zram0
        swapon /dev/block/zram0 -p 32758
    fi
    
    # Configure Low Memory Killer parameters
    # Read adj series and set adj threshold for PPR and ALMK
    adj_series=`cat /sys/module/lowmemorykiller/parameters/adj`
    adj_1="${adj_series#*,}"
    set_almk_ppr_adj="${adj_1%%,*}"
    
    # Calculate PPR adj threshold (HOME adj and below should not be affected)
    set_almk_ppr_adj=$(((set_almk_ppr_adj * 6) + 6))
    echo $set_almk_ppr_adj > /sys/module/lowmemorykiller/parameters/adj_max_shift
    
    # Calculate vmpressure_file_min for 64-bit architecture
    if [ "$arch_type" == "aarch64" ]; then
        minfree_series=`cat /sys/module/lowmemorykiller/parameters/minfree`
        minfree_1="${minfree_series#*,}"
        rem_minfree_1="${minfree_1%%,*}"
        minfree_2="${minfree_1#*,}"
        rem_minfree_2="${minfree_2%%,*}"
        minfree_3="${minfree_2#*,}"
        rem_minfree_3="${minfree_3%%,*}"
        minfree_4="${minfree_3#*,}"
        rem_minfree_4="${minfree_4%%,*}"
        minfree_5="${minfree_4#*,}"
        
        vmpres_file_min=$((minfree_5 + (minfree_5 - rem_minfree_4)))
        echo $vmpres_file_min > /sys/module/lowmemorykiller/parameters/vmpressure_file_min
    fi
    
    # Enable Adaptive LMK
    echo 1 > /sys/module/lowmemorykiller/parameters/enable_adaptive_lmk
    
    # Enable OOM reaper
    if [ -f /sys/module/lowmemorykiller/parameters/oom_reaper ]; then
        echo 1 > /sys/module/lowmemorykiller/parameters/oom_reaper
    fi
    
    # Configure Process Reclaim parameters
    if [ -f /sys/devices/soc0/soc_id ]; then
        soc_id=`cat /sys/devices/soc0/soc_id`
    else
        soc_id=`cat /sys/devices/system/soc/soc0/id`
    fi
    
    # Set PPR parameters (excluding premium SoCs)
    case "$soc_id" in
        "321" | "341" | "292" | "319" | "246" | "291" | "305" | "312")
            # Skip PPR for premium targets
            ;;
        *)
            echo $set_almk_ppr_adj > /sys/module/process_reclaim/parameters/min_score_adj
            echo 1 > /sys/module/process_reclaim/parameters/enable_process_reclaim
            echo 50 > /sys/module/process_reclaim/parameters/pressure_min
            echo 70 > /sys/module/process_reclaim/parameters/pressure_max
            echo 30 > /sys/module/process_reclaim/parameters/swap_opt_eff
            echo 512 > /sys/module/process_reclaim/parameters/per_swap_size
            ;;
    esac
    
    # Set global VM parameters
    echo 0 > /sys/module/vmpressure/parameters/allocstall_threshold
    echo 1 > /proc/sys/vm/watermark_scale_factor
    
    # Configure read-ahead values
    configure_read_ahead_kb_values
    
    # Enable swap
    enable_swap
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

# Enable conservative pl for power save
echo 1 > /proc/sys/kernel/sched_conservative_pl

echo "0:1248000" > /sys/module/cpu_boost/parameters/input_boost_freq
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

# 2 kswapd threads (OPLUS multi-kswapd). 8GB/8-core: a single kswapd can't keep up when
# zram reclaim is active, forcing foreground tasks into direct reclaim = stalls/jank.
echo 2 > /proc/sys/vm/kswapd_threads