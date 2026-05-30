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

import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.BatteryManager;
import android.os.IBinder;
import android.os.UserHandle;

/**
 * Lightweight monitor for the {@link ChargeLimitSettings} charge cap. It holds
 * a runtime ACTION_BATTERY_CHANGED receiver (that broadcast cannot be declared
 * in the manifest) and gates the OPLUS charge switch as the level crosses the
 * configured cap. Started/stopped as the system user, matching DozeService, so
 * the background-start restriction doesn't apply to this privileged app.
 */
public class ChargeLimitService extends Service {

    private boolean mRegistered;

    private final BroadcastReceiver mBatteryReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            handleBatteryIntent(intent);
        }
    };

    public static void start(Context context) {
        context.startServiceAsUser(new Intent(context, ChargeLimitService.class),
                UserHandle.CURRENT);
    }

    public static void stop(Context context) {
        context.stopServiceAsUser(new Intent(context, ChargeLimitService.class),
                UserHandle.CURRENT);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        final IntentFilter filter = new IntentFilter(Intent.ACTION_BATTERY_CHANGED);
        Intent sticky;
        if (!mRegistered) {
            // registerReceiver returns the current sticky battery intent.
            sticky = registerReceiver(mBatteryReceiver, filter);
            mRegistered = true;
        } else {
            // Already listening (e.g. re-started after a cap change): peek at the
            // current sticky battery state without re-registering.
            sticky = registerReceiver(null, filter);
        }
        // Apply immediately rather than waiting for the next battery tick.
        handleBatteryIntent(sticky);
        return START_STICKY;
    }

    private void handleBatteryIntent(Intent intent) {
        if (intent == null) {
            return;
        }
        final int level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
        final int scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
        if (level < 0 || scale <= 0) {
            return;
        }
        ChargeLimitSettings.apply(this, Math.round(level * 100f / scale));
    }

    @Override
    public void onDestroy() {
        if (mRegistered) {
            unregisterReceiver(mBatteryReceiver);
            mRegistered = false;
        }
        // Safety: never leave the charger gated off after the monitor stops.
        ChargeLimitSettings.setChargingEnabled(true);
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
