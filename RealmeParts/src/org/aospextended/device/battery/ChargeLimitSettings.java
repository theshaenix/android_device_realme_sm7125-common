/*
 * Copyright (C) 2026 ShadowBladeX
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.aospextended.device.battery;

import android.content.Context;

import org.aospextended.device.util.Utils;

/**
 * Battery charge limit, backed by the OPLUS charger driver's
 * "mmi_charging_enable" switch (1 = allow charging, 0 = hold). There is no
 * SOC-ceiling node on this platform (charge_control_limit is read-only and
 * charge_control_limit_max is 0), so we implement the cap ourselves: a small
 * monitor watches the battery level and gates this switch around the target.
 *
 * The node is owned system:system, so RealmeParts (uid system) may write it.
 */
public class ChargeLimitSettings {

    public static final String NODE =
            "/sys/class/power_supply/battery/mmi_charging_enable";

    public static final String KEY_ENABLE = "charge_limit_enable";
    public static final String KEY_LEVEL = "charge_limit_level";
    public static final String DEFAULT_LEVEL = "80";

    /** Resume charging once we fall this far below the cap (anti-flap). */
    private static final int HYSTERESIS = 2;

    public static boolean isSupported() {
        return Utils.fileWritable(NODE);
    }

    public static boolean isEnabled(Context context) {
        return Utils.getSharedPreferences(context).getBoolean(KEY_ENABLE, false);
    }

    public static int getLevel(Context context) {
        try {
            return Integer.parseInt(Utils.getSharedPreferences(context)
                    .getString(KEY_LEVEL, DEFAULT_LEVEL));
        } catch (NumberFormatException e) {
            return Integer.parseInt(DEFAULT_LEVEL);
        }
    }

    /** Write the OPLUS charge-enable switch (1 = charge, 0 = hold). */
    public static void setChargingEnabled(boolean enabled) {
        Utils.writeLine(NODE, enabled ? "1" : "0");
    }

    /**
     * Core policy: hold charging at/above the cap, resume once we drop
     * HYSTERESIS below it. Inside the dead-band we leave the node untouched so
     * the charge IC doesn't chatter on/off around the threshold.
     */
    public static void apply(Context context, int batteryLevel) {
        if (!isSupported() || !isEnabled(context)) {
            return;
        }
        final int limit = getLevel(context);
        if (batteryLevel >= limit) {
            setChargingEnabled(false);
        } else if (batteryLevel <= limit - HYSTERESIS) {
            setChargingEnabled(true);
        }
    }

    /** React to the user toggling the feature on/off. */
    public static void onEnableChanged(Context context, boolean enabled) {
        if (enabled) {
            ChargeLimitService.start(context);
        } else {
            ChargeLimitService.stop(context);
            // Never leave the battery stuck not-charging when the cap is off.
            setChargingEnabled(true);
        }
    }

    /** Called on boot: start the monitor only if the cap is enabled. */
    public static void restore(Context context) {
        if (isSupported() && isEnabled(context)) {
            ChargeLimitService.start(context);
        }
    }
}
