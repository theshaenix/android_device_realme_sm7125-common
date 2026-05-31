/*
 * Copyright (c) 2020 The AospExtended Project
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

import android.os.Bundle;

import com.android.settingslib.collapsingtoolbar.CollapsingToolbarBaseActivity;
import com.android.settingslib.collapsingtoolbar.R;

/**
 * Hosts the main RealmeParts screen inside a collapsing Material toolbar, the
 * same chrome the system Settings app uses on Android 12+. The toolbar, title
 * (from the activity label) and Up/back navigation are all handled by
 * {@link CollapsingToolbarBaseActivity}, so no ActionBar wiring is needed here.
 */
public class RealmePartsActivity extends CollapsingToolbarBaseActivity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        if (getSupportFragmentManager().findFragmentById(R.id.content_frame) == null) {
            getSupportFragmentManager().beginTransaction()
                    .replace(R.id.content_frame, new RealmeParts())
                    .commit();
        }
    }
}
