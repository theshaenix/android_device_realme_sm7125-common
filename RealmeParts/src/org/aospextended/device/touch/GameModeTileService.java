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

import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/** Quick Settings tile that toggles {@link TouchModeSettings} game touch mode. */
public class GameModeTileService extends TileService {

    @Override
    public void onStartListening() {
        super.onStartListening();
        updateTile();
    }

    @Override
    public void onClick() {
        super.onClick();
        if (!TouchModeSettings.isGameModeSupported()) {
            return;
        }
        TouchModeSettings.setGameModeEnabled(this,
                !TouchModeSettings.isGameModeEnabled(this));
        updateTile();
    }

    private void updateTile() {
        final Tile tile = getQsTile();
        if (tile == null) {
            return;
        }
        if (!TouchModeSettings.isGameModeSupported()) {
            tile.setState(Tile.STATE_UNAVAILABLE);
        } else {
            tile.setState(TouchModeSettings.isGameModeEnabled(this)
                    ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        }
        tile.updateTile();
    }
}
