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

package org.aospextended.device.gpu;

import android.content.Context;

import org.aospextended.device.util.Utils;

/**
 * GPU Boost control, backed by the ShadowBladeX kernel's downstream KGSL
 * "adrenoboost" tunable for the msm-adreno-tz governor on the Adreno 618.
 *
 * Range 0..3: 0 = off (stock ramp), 1 = light, 2 = aggressive (kernel default),
 * 3 = maximum. Higher values bias the governor toward higher clocks under load
 * for smoother 90Hz UI / steadier game fps, at a small power cost.
 */
public class GpuBoostSettings {

    public static final String NODE = "/sys/class/kgsl/kgsl-3d0/devfreq/adrenoboost";
    public static final String KEY = "gpu_boost_level";
    public static final String DEFAULT = "2";

    public static boolean isSupported() {
        return Utils.fileWritable(NODE);
    }

    public static String getValue(Context context) {
        return Utils.getSharedPreferences(context).getString(KEY, DEFAULT);
    }

    public static void setValue(String value) {
        Utils.writeLine(NODE, value);
    }

    /** Re-apply the saved level to the kernel node (called on boot). */
    public static void restore(Context context) {
        if (!isSupported()) {
            return;
        }
        setValue(getValue(context));
    }
}
