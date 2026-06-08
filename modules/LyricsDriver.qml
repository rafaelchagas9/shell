pragma ComponentBehavior: Bound

import Quickshell
import Caelestia.Config
import Caelestia.Services
import qs.services

// Keeps the (C++) Lyrics service synced to the active player while the media
// wallpaper lyrics overlay is enabled. The dashboard otherwise drives Lyrics
// lazily (only while its media view is open), so without this the wallpaper
// overlay would have no lyrics unless the dashboard had been opened.
//
// Gated on the media wallpaper lyrics config to preserve upstream's lazy
// behaviour: when the overlay is disabled, no lyrics are fetched here.
// Lyrics.setTrack is idempotent, so coexisting with the dashboard's own
// driver (modules/dashboard/media/LyricList.qml) is harmless.
Scope {
    id: root

    readonly property bool driving: GlobalConfig.background.mediaWallpaper.enabled && GlobalConfig.background.mediaWallpaper.showLyrics

    // Side-effecting binding: re-runs whenever `driving`, the active player, or
    // the active player's track metadata changes (same idiom as LyricList).
    readonly property var _sync: {
        if (!driving)
            return;

        const player = Players.active;
        if (player)
            Lyrics.setTrack(player.trackArtist, player.trackTitle, player.trackAlbum, player.length);
        else
            Lyrics.clearTrack();
    }
}
