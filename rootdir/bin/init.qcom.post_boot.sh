#!/vendor/bin/sh

# ============================================
# init.qcom.post_boot.sh - Universal All-in-One Edition v4.0
# Realme 6 Pro (SM7125 - Snapdragon 720G)
# Optimized for performance, battery, and multitasking
# ============================================

# -------------------------
# Intelligent CPU scaling with thermal awareness
# -------------------------
dynamic_cpu_scaling() {
    while true; do
        CPU_LOAD=$(awk '{u=$2+$4; t=$2+$4+$5; if(t>0) print int(u/t*100); else print 0}' < /proc/stat | head -n1)
        THERMAL_STATE=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | head -c 2)
        THERMAL_STATE=${THERMAL_STATE:-50}
        
        # Smart thermal throttling
        if [ "$THERMAL_STATE" -gt 85 ]; then
            THERMAL_FACTOR=0.7
        elif [ "$THERMAL_STATE" -gt 75 ]; then
            THERMAL_FACTOR=0.8
        elif [ "$THERMAL_STATE" -gt 65 ]; then
            THERMAL_FACTOR=0.9
        else
            THERMAL_FACTOR=1.0
        fi

        # LITTLE cores (0-5) - Adaptive scaling
        for cpu in 0 1 2 3 4 5; do
            [ ! -d "/sys/devices/system/cpu/cpu$cpu/cpufreq" ] && continue
            
            if [ "$CPU_LOAD" -lt 10 ]; then
                TARGET_FREQ=300000      # Idle
            elif [ "$CPU_LOAD" -lt 25 ]; then
                TARGET_FREQ=576000      # Light usage
            elif [ "$CPU_LOAD" -lt 45 ]; then
                TARGET_FREQ=768000      # Moderate usage
            elif [ "$CPU_LOAD" -lt 65 ]; then
                TARGET_FREQ=1248000     # Heavy usage
            elif [ "$CPU_LOAD" -lt 85 ]; then
                TARGET_FREQ=1516800     # Very heavy
            else
                TARGET_FREQ=1804800     # Maximum
            fi
            
            TARGET_FREQ=$(echo "$TARGET_FREQ * $THERMAL_FACTOR" | bc 2>/dev/null | cut -d. -f1 || echo $TARGET_FREQ)
            echo $TARGET_FREQ > /sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq 2>/dev/null
        done

        # BIG cores (6-7) - Performance focused with efficiency
        for cpu in 6 7; do
            [ ! -d "/sys/devices/system/cpu/cpu$cpu/cpufreq" ] && continue
            
            if [ "$CPU_LOAD" -lt 15 ]; then
                TARGET_FREQ=652800      # Idle/Light
            elif [ "$CPU_LOAD" -lt 35 ]; then
                TARGET_FREQ=1036800     # Light-moderate
            elif [ "$CPU_LOAD" -lt 55 ]; then
                TARGET_FREQ=1612800     # Moderate
            elif [ "$CPU_LOAD" -lt 75 ]; then
                TARGET_FREQ=1804800     # Heavy
            elif [ "$CPU_LOAD" -lt 90 ]; then
                TARGET_FREQ=2208000     # Very heavy
            else
                TARGET_FREQ=2300000     # Maximum performance
            fi
            
            TARGET_FREQ=$(echo "$TARGET_FREQ * $THERMAL_FACTOR" | bc 2>/dev/null | cut -d. -f1 || echo $TARGET_FREQ)
            echo $TARGET_FREQ > /sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq 2>/dev/null
        done

        sleep 2
    done &
}

# Zram Configuration 
configure_zram() {
    # Safely disable existing zram
    swapoff /dev/block/zram0 2>/dev/null || true
    
    # Reset zram device
    [ -w /sys/block/zram0/reset ] && echo 1 > /sys/block/zram0/reset
    
    # Set compression algorithm (LZ4 optimized for ARM Cortex-A76/A55)
    echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null || return 1
    
    # Optimize compression streams for 8-core big.LITTLE (2x A76 + 6x A55)
    echo 4 > /sys/block/zram0/max_comp_streams 2>/dev/null || true
    
    # Set 4GB zram size
    echo 4294967296 > /sys/block/zram0/disksize 2>/dev/null || return 1
    
    # Initialize and enable swap
    mkswap /dev/block/zram0 2>/dev/null || return 1
    swapon /dev/block/zram0 -p 32758 2>/dev/null || return 1
    
    # VM tuning - Optimized for Realme 6 Pro mobile workloads
    {
        # Swappiness: Slightly higher for 4GB zram to utilize it effectively
        echo 90 > /proc/sys/vm/swappiness
        
        # Cache pressure: Aggressive reclaim for mobile RAM management
        echo 100 > /proc/sys/vm/vfs_cache_pressure
        
        # Page-cluster: Small reads optimal for mobile flash + zram combo
        echo 1 > /proc/sys/vm/page-cluster
        
        # Dirty ratios: Conservative for mobile storage longevity
        echo 20 > /proc/sys/vm/dirty_ratio
        echo 5 > /proc/sys/vm/dirty_background_ratio
        
        # Extra free memory: Buffer for smooth operation
        echo 1024 > /proc/sys/vm/extra_free_kbytes
        
        # Memory overcommit: Conservative for stability
        echo 1 > /proc/sys/vm/overcommit_memory
        echo 50 > /proc/sys/vm/overcommit_ratio
        
        # Additional mobile optimizations for Snapdragon 720G
        echo 1 > /proc/sys/vm/compact_memory 2>/dev/null || true
        echo 0 > /proc/sys/vm/oom_kill_allocating_task 2>/dev/null || true
        
        # Optimize readahead for mobile storage patterns
        echo 128 > /sys/block/*/queue/read_ahead_kb 2>/dev/null || true
        
    } 2>/dev/null
    
    return 0
}

# -------------------------
# Stock-Plus CPU Governor Configuration
# -------------------------
configure_cpu_governor() {
    # Set schedutil governor (stock behavior)
    for cpu in 0 1 2 3 4 5 6 7; do
        if [ -d "/sys/devices/system/cpu/cpu$cpu/cpufreq" ]; then
            echo schedutil > /sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor 2>/dev/null
            
            # Keep stock schedutil parameters, just ensure they're set
            if [ -d "/sys/devices/system/cpu/cpu$cpu/cpufreq/schedutil" ]; then
                echo 500  > /sys/devices/system/cpu/cpu$cpu/cpufreq/schedutil/up_rate_limit_us 2>/dev/null
                echo 20000 > /sys/devices/system/cpu/cpu$cpu/cpufreq/schedutil/down_rate_limit_us 2>/dev/null
                echo 1 > /sys/devices/system/cpu/cpu$cpu/cpufreq/schedutil/iowait_boost_enable 2>/dev/null
            fi
        fi
    done

    # Stock-like input boost with slight improvement
    if [ -d "/sys/module/cpu_boost/parameters" ]; then
        echo "0:1036800 6:1612800" > /sys/module/cpu_boost/parameters/input_boost_freq 2>/dev/null
        echo 100 > /sys/module/cpu_boost/parameters/input_boost_ms 2>/dev/null
        echo 0 > /sys/module/cpu_boost/parameters/sched_boost_on_input 2>/dev/null
    fi
}

# -------------------------
# Universal GPU Configuration - Adreno 618
# -------------------------
configure_gpu() {
    GPU_DEVFREQ=""
    for d in /sys/class/devfreq/*; do
        if grep -qiE "(kgsl|adreno|gpu)" <<< "$(basename "$d")"; then
            [ -f "$d/available_governors" ] && GPU_DEVFREQ="$d" && break
        fi
    done

    [ -z "$GPU_DEVFREQ" ] && [ -d /sys/class/kgsl/kgsl-3d0/devfreq ] && GPU_DEVFREQ=/sys/class/kgsl/kgsl-3d0/devfreq

    if [ -n "$GPU_DEVFREQ" ]; then
        GOVS=$(cat "$GPU_DEVFREQ/available_governors" 2>/dev/null || true)

        # Prefer msm-adreno-tz for best performance/efficiency balance
        if echo "$GOVS" | grep -qw "msm-adreno-tz"; then
            GOV="msm-adreno-tz"
        elif echo "$GOVS" | grep -qw "simple_ondemand"; then
            GOV="simple_ondemand"
        else
            GOV=$(echo "$GOVS" | awk '{print $1}')
        fi

        [ -w "$GPU_DEVFREQ/governor" ] && echo "$GOV" > "$GPU_DEVFREQ/governor" 2>/dev/null

        # Adreno 618 optimal frequencies
        [ -w "$GPU_DEVFREQ/min_freq" ] && echo 180000000 > "$GPU_DEVFREQ/min_freq" 2>/dev/null
        [ -w "$GPU_DEVFREQ/max_freq" ] && echo 750000000 > "$GPU_DEVFREQ/max_freq" 2>/dev/null
        [ -w /sys/class/kgsl/kgsl-3d0/adrenoboost ] && echo 1 > /sys/class/kgsl/kgsl-3d0/adrenoboost 2>/dev/null
    fi
}

# -------------------------
# Enhanced Multitasking & Memory Management (Stock-Plus)
# -------------------------
configure_multitasking() {
    # LMK - Stock-like with better app retention
    if [ -f "/sys/module/lowmemorykiller/parameters/minfree" ]; then
        echo "18432,23040,27648,32256,55296,80640" > /sys/module/lowmemorykiller/parameters/minfree 2>/dev/null
    fi
    
    # Stock-like memory pressure settings
    echo 100 > /proc/sys/vm/watermark_scale_factor 2>/dev/null
    echo 0 > /proc/sys/vm/watermark_boost_factor 2>/dev/null
    
    # Keep stock OOM behavior
    echo 0 > /proc/sys/vm/oom_kill_allocating_task 2>/dev/null
    echo 0 > /proc/sys/vm/panic_on_oom 2>/dev/null
    
    # Minimal background process adjustments
    if [ -d "/dev/cpuctl" ]; then
        echo 1024 > /dev/cpuctl/background/cpu.shares 2>/dev/null
        echo -1 > /dev/cpuctl/background/cpu.cfs_quota_us 2>/dev/null
        echo 1024 > /dev/cpuctl/foreground/cpu.shares 2>/dev/null
        echo -1 > /dev/cpuctl/foreground/cpu.cfs_quota_us 2>/dev/null
    fi
    
    # Stock-like VM tunables with minor improvements
    echo 3000 > /proc/sys/vm/dirty_expire_centisecs 2>/dev/null
    echo 500 > /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null
    
    # Keep stock memory behavior mostly intact
    echo 1 > /proc/sys/vm/compact_unevictable_allowed 2>/dev/null
}

# -------------------------
# Stock-Plus Scheduler with NOOP I/O
# -------------------------
configure_scheduler() {
    # SchedTune - Stock-like with minor improvements
    if [ -d "/dev/stune" ]; then
        echo 10 > /dev/stune/top-app/schedtune.boost 2>/dev/null
        echo 1  > /dev/stune/top-app/schedtune.prefer_idle 2>/dev/null
        echo 5 > /dev/stune/foreground/schedtune.boost 2>/dev/null
        echo 0 > /dev/stune/background/schedtune.boost 2>/dev/null
        echo 0 > /dev/stune/system-background/schedtune.boost 2>/dev/null
    fi

    # Stock scheduler sysctls with small improvements
    echo 95 > /proc/sys/kernel/sched_upmigrate 2>/dev/null
    echo 85 > /proc/sys/kernel/sched_downmigrate 2>/dev/null
    echo 120 > /proc/sys/kernel/sched_group_upmigrate 2>/dev/null
    echo 95 > /proc/sys/kernel/sched_group_downmigrate 2>/dev/null
    echo 500000 > /proc/sys/kernel/sched_migration_cost_ns 2>/dev/null
    echo 1000000 > /proc/sys/kernel/sched_wakeup_granularity_ns 2>/dev/null
    echo 6000000 > /proc/sys/kernel/sched_latency_ns 2>/dev/null

    # NOOP I/O for responsiveness (only improvement over stock)
    for block in sda sdb sdc sdd sde sdf sdg mmcblk0 mmcblk1 dm-0 dm-1; do
        if [ -e "/sys/block/$block/queue/scheduler" ]; then
            echo noop > /sys/block/$block/queue/scheduler 2>/dev/null
            echo 128 > /sys/block/$block/queue/read_ahead_kb 2>/dev/null
            echo 1 > /sys/block/$block/queue/iostats 2>/dev/null
            echo 1 > /sys/block/$block/queue/rq_affinity 2>/dev/null
            echo 128 > /sys/block/$block/queue/nr_requests 2>/dev/null
        fi
    done
}

# -------------------------
# Universal Network Optimization
# -------------------------
configure_network() {
    # High-performance TCP stack
    echo 1 > /proc/sys/net/ipv4/tcp_low_latency 2>/dev/null
    echo 0 > /proc/sys/net/ipv4/tcp_timestamps 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/tcp_sack 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/tcp_window_scaling 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/tcp_tw_reuse 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/tcp_tw_recycle 2>/dev/null
    
    # Modern congestion control
    echo bbr > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || \
    echo cubic > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null

    # Optimized buffer sizes for 720G
    echo 4096 65536 16777216 > /proc/sys/net/ipv4/tcp_rmem 2>/dev/null
    echo 4096 65536 16777216 > /proc/sys/net/ipv4/tcp_wmem 2>/dev/null
    echo 262144 > /proc/sys/net/core/rmem_default 2>/dev/null
    echo 262144 > /proc/sys/net/core/wmem_default 2>/dev/null
    echo 8388608 > /proc/sys/net/core/rmem_max 2>/dev/null
    echo 8388608 > /proc/sys/net/core/wmem_max 2>/dev/null

    # Network performance tuning
    echo 5000 > /proc/sys/net/core/netdev_max_backlog 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/tcp_no_metrics_save 2>/dev/null
    echo 0 > /proc/sys/net/ipv4/tcp_slow_start_after_idle 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null

    # Wi-Fi optimization - balanced power/performance
    echo 0 > /sys/module/wlan/parameters/iw_power_save_disable 2>/dev/null
}

# -------------------------
# Universal Thermal Management
# -------------------------
configure_thermal() {
    for zone in /sys/class/thermal/thermal_zone*; do
        if [ -e "$zone/temp" ]; then
            # Balanced thermal thresholds
            [ -e "$zone/trip_point_0_temp" ] && echo 85000 > $zone/trip_point_0_temp 2>/dev/null
            [ -e "$zone/trip_point_1_temp" ] && echo 95000 > $zone/trip_point_1_temp 2>/dev/null
            [ -e "$zone/trip_point_2_temp" ] && echo 105000 > $zone/trip_point_2_temp 2>/dev/null
        fi
    done
}

# -------------------------
# Universal System Optimization (Boot tweaks removed)
# -------------------------
configure_system() {
    # File system optimization only
    echo 256 > /proc/sys/fs/inotify/max_user_instances 2>/dev/null
    echo 32768 > /proc/sys/fs/inotify/max_user_watches 2>/dev/null
    
    # Process scheduling
    echo 1 > /proc/sys/kernel/sched_autogroup_enabled 2>/dev/null
    echo 1 > /proc/sys/kernel/timer_migration 2>/dev/null
}

# ============================================
# Main Execution
# ============================================

# Execute all optimizations
configure_cpu_governor
configure_gpu
configure_multitasking
configure_scheduler
configure_network
configure_thermal
configure_system
dynamic_cpu_scaling
configure_zram
