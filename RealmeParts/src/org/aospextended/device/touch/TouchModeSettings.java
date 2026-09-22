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

package org.aospextended.device.touch;

import android.content.ComponentName;
import android.content.Context;
import android.service.quicksettings.TileService;

import org.aospextended.device.util.Utils;

/**
 * Touch panel work modes exposed by the OPLUS touchscreen driver under
 * /proc/touchpanel. Both nodes go through ts_ops->mode_switch on the panel
 * IC (Goodix / Novatek / Samsung / Focal on sm7125):
 *
 *  - game_switch_enable: "game mode" — the IC raises its report rate and
 *    drops the noise/jitter filtering that adds latency. The driver turns it
 *    OFF at every panel suspend and does NOT re-apply it on resume (only
 *    glove/edge/charge modes are restored by operate_mode_switch), so
 *    {@link TouchModeService} re-writes it after each screen-on.
 *
 *  - glove_mode_enable: raises touch sensitivity for gloves or thick screen
 *    protectors. The driver restores this one itself on resume.
 *
 * Both nodes are created 0666 by proc_create and system_app already has
 * proc_touchpanel rw in sepolicy, so no extra init.rc or policy is needed.
 */
public class TouchModeSettings {

    public static final String GAME_NODE = "/proc/touchpanel/game_switch_enable";
    public static final String GLOVE_NODE = "/proc/touchpanel/glove_mode_enable";

    public static final String KEY_GAME_MODE = "game_touch_mode";
    public static final String KEY_GLOVE_MODE = "glove_mode";

    public static boolean isGameModeSupported() {
        return Utils.fileWritable(GAME_NODE);
    }

    public static boolean isGloveModeSupported() {
        return Utils.fileWritable(GLOVE_NODE);
    }

    public static boolean isGameModeEnabled(Context context) {
        return Utils.getSharedPreferences(context).getBoolean(KEY_GAME_MODE, false);
    }

    public static boolean isGloveModeEnabled(Context context) {
        return Utils.getSharedPreferences(context).getBoolean(KEY_GLOVE_MODE, false);
    }

    /** Persist the game-mode choice, push it to the panel and (un)arm the re-apply service. */
    public static void setGameModeEnabled(Context context, boolean enabled) {
        Utils.getSharedPreferences(context).edit()
                .putBoolean(KEY_GAME_MODE, enabled).apply();
        writeGameMode(enabled);
        if (enabled) {
            TouchModeService.start(context);
        } else {
            TouchModeService.stop(context);
        }
        TileService.requestListeningState(context,
                new ComponentName(context, GameModeTileService.class));
    }

    /** Persist the glove-mode choice and push it to the panel. */
    public static void setGloveModeEnabled(Context context, boolean enabled) {
        Utils.getSharedPreferences(context).edit()
                .putBoolean(KEY_GLOVE_MODE, enabled).apply();
        writeGloveMode(enabled);
        TileService.requestListeningState(context,
                new ComponentName(context, GloveModeTileService.class));
    }

    /** Write the saved game-mode state to the panel (used after screen-on). */
    public static void applyGameMode(Context context) {
        if (isGameModeSupported()) {
            writeGameMode(isGameModeEnabled(context));
        }
    }

    /** Called on boot: re-apply both saved modes and arm the game-mode keeper. */
    public static void restore(Context context) {
        if (isGloveModeSupported()) {
            writeGloveMode(isGloveModeEnabled(context));
        }
        if (isGameModeSupported() && isGameModeEnabled(context)) {
            writeGameMode(true);
            TouchModeService.start(context);
        }
    }

    // The driver parses game_switch_enable with "%x" and rejects writes longer
    // than 4 bytes; glove_mode_enable parses "%d" and rejects more than 2.
    // A bare "1"/"0" (no newline) satisfies both.
    private static void writeGameMode(boolean enabled) {
        Utils.writeLine(GAME_NODE, enabled ? "1" : "0");
    }

    private static void writeGloveMode(boolean enabled) {
        Utils.writeLine(GLOVE_NODE, enabled ? "1" : "0");
    }
}
