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

import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.UserHandle;

/**
 * Keeps game touch mode armed across screen-off cycles. The OPLUS touch
 * driver clears MODE_GAME in tp_suspend and never restores it, so this
 * service listens for ACTION_SCREEN_ON (runtime-only broadcast) and re-writes
 * the node once the panel has finished its resume sequence.
 *
 * Started/stopped as the system user, matching ChargeLimitService, so the
 * background-start restriction doesn't apply to this privileged app.
 */
public class TouchModeService extends Service {

    /**
     * tp_resume queues speedup_resume() which resets the IC firmware and then
     * runs operate_mode_switch(); a write that lands before that reset is
     * lost. One second is comfortably after it on every supported IC.
     */
    private static final long REAPPLY_DELAY_MS = 1000;

    private final Handler mHandler = new Handler(Looper.getMainLooper());
    private final Runnable mReapply = () -> TouchModeSettings.applyGameMode(this);
    private boolean mRegistered;

    private final BroadcastReceiver mScreenOnReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            if (Intent.ACTION_SCREEN_ON.equals(intent.getAction())) {
                mHandler.removeCallbacks(mReapply);
                mHandler.postDelayed(mReapply, REAPPLY_DELAY_MS);
            }
        }
    };

    public static void start(Context context) {
        context.startServiceAsUser(new Intent(context, TouchModeService.class),
                UserHandle.CURRENT);
    }

    public static void stop(Context context) {
        context.stopServiceAsUser(new Intent(context, TouchModeService.class),
                UserHandle.CURRENT);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (!mRegistered) {
            registerReceiver(mScreenOnReceiver, new IntentFilter(Intent.ACTION_SCREEN_ON));
            mRegistered = true;
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        mHandler.removeCallbacks(mReapply);
        if (mRegistered) {
            unregisterReceiver(mScreenOnReceiver);
            mRegistered = false;
        }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
