/*
 * Copyright (C) 2020 The AospExtended Project
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

package org.aospextended.device;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.Intent;
import android.os.Bundle;
import androidx.preference.PreferenceFragmentCompat;
import androidx.preference.Preference;
import androidx.preference.ListPreference;
import androidx.preference.PreferenceCategory;
import androidx.preference.PreferenceManager;
import androidx.preference.PreferenceScreen;
import androidx.preference.SwitchPreference;
import androidx.preference.TwoStatePreference;

import org.aospextended.device.gestures.TouchGestures;
import org.aospextended.device.gestures.TouchGesturesActivity;
import org.aospextended.device.doze.DozeSettingsActivity;
import org.aospextended.device.vibration.VibratorStrengthPreference;
import org.aospextended.device.gpu.GpuBoostSettings;
import org.aospextended.device.battery.ChargeLimitSettings;
import org.aospextended.device.battery.ChargeLimitService;

import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.Locale;
import java.util.Date;

import android.util.Log;
import android.os.SystemProperties;
import java.io.*;
import android.widget.Toast;

import org.aospextended.device.R;
import org.aospextended.device.util.Utils;

public class RealmeParts extends PreferenceFragmentCompat implements
        Preference.OnPreferenceChangeListener {
    private static final boolean DEBUG = Utils.DEBUG;
    private static final String TAG = "RealmeParts";

    private Context mContext;
    private SharedPreferences mPreferences;

    private Preference mDozePref;
    private Preference mGesturesPref;
    private VibratorStrengthPreference mVibratorStrength;
    private ListPreference mGpuBoost;
    private SwitchPreference mChargeLimitEnable;
    private ListPreference mChargeLimitLevel;

    @Override
    public void onCreatePreferences(Bundle savedInstanceState, String rootKey) {
        setPreferencesFromResource(R.xml.RealmeParts, rootKey);

        PreferenceCategory gestures = (PreferenceCategory) getPreferenceScreen()
                 .findPreference("gestures_category");
        mGesturesPref = findPreference("screen_gestures");
        mGesturesPref.setOnPreferenceClickListener(new Preference.OnPreferenceClickListener() {
            @Override
            public boolean onPreferenceClick(Preference preference) {
                Intent intent = new Intent(getContext(), TouchGesturesActivity.class);
                startActivity(intent);
                return true;
            }
        });
        if (!TouchGestures.isSupported()) {
            getPreferenceScreen().removePreference(gestures);
        }

        mDozePref = findPreference("doze");
        mDozePref.setOnPreferenceClickListener(new Preference.OnPreferenceClickListener() {
            @Override
            public boolean onPreferenceClick(Preference preference) {
                Intent intent = new Intent(getContext(), DozeSettingsActivity.class);
                startActivity(intent);
                return true;
            }
        });

        PreferenceCategory performance = (PreferenceCategory) getPreferenceScreen()
                 .findPreference("performance_category");
        mGpuBoost = (ListPreference) findPreference(GpuBoostSettings.KEY);
        if (GpuBoostSettings.isSupported()) {
            mGpuBoost.setValue(GpuBoostSettings.getValue(getContext()));
            // SimpleSummaryProvider shows the current entry as the summary and
            // updates itself on change. It also avoids the String.format crash
            // that the manual setSummary path hit on entries containing '%'.
            mGpuBoost.setSummaryProvider(ListPreference.SimpleSummaryProvider.getInstance());
            mGpuBoost.setOnPreferenceChangeListener(this);
        } else if (performance != null) {
            getPreferenceScreen().removePreference(performance);
        }

        PreferenceCategory battery = (PreferenceCategory) getPreferenceScreen()
                 .findPreference("battery_category");
        mChargeLimitEnable = (SwitchPreference) findPreference(ChargeLimitSettings.KEY_ENABLE);
        mChargeLimitLevel = (ListPreference) findPreference(ChargeLimitSettings.KEY_LEVEL);
        if (ChargeLimitSettings.isSupported()) {
            mChargeLimitEnable.setOnPreferenceChangeListener(this);
            mChargeLimitLevel.setValue(
                    String.valueOf(ChargeLimitSettings.getLevel(getContext())));
            // '%' in the entries ("80%") crashed the old manual-format summary;
            // SimpleSummaryProvider renders the entry verbatim and auto-updates.
            mChargeLimitLevel.setSummaryProvider(
                    ListPreference.SimpleSummaryProvider.getInstance());
            mChargeLimitLevel.setOnPreferenceChangeListener(this);
        } else if (battery != null) {
            getPreferenceScreen().removePreference(battery);
        }


/*        PreferenceCategory vib_strength = (PreferenceCategory) getPreferenceScreen()
                 .findPreference("vib_strength_category");
        mVibratorStrength = (VibratorStrengthPreference) findPreference(VibratorStrengthPreference.KEY_VIBSTRENGTH);
        if (!VibratorStrengthPreference.isSupported()) {
            getPreferenceScreen().removePreference(vib_strength);
        }
*/
    }

    @Override
    public boolean onPreferenceTreeClick(Preference preference) {
        return super.onPreferenceTreeClick(preference);
    }

    @Override
    public boolean onPreferenceChange(Preference preference, Object newValue) {
        final String key = preference.getKey();
        // ListPreference summaries refresh automatically via SimpleSummaryProvider
        // once the new value is applied, so no manual setSummary is needed here.
        if (GpuBoostSettings.KEY.equals(key)) {
            GpuBoostSettings.setValue((String) newValue);
        } else if (ChargeLimitSettings.KEY_ENABLE.equals(key)) {
            ChargeLimitSettings.onEnableChanged(getContext(), (Boolean) newValue);
        } else if (ChargeLimitSettings.KEY_LEVEL.equals(key)) {
            final String value = (String) newValue;
            // Persist now (the framework persists only after we return) so the
            // monitor re-evaluates against the new cap immediately.
            Utils.getSharedPreferences(getContext()).edit()
                    .putString(ChargeLimitSettings.KEY_LEVEL, value).apply();
            ChargeLimitService.start(getContext());
        }
        return true;
    }
}
