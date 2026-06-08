# Re-port plan: Media-art wallpaper + lyrics overlay

**Status:** in progress — Phase 1 (config) + Phase 2 (lyrics driver) implemented
on branch `feat/media-wallpaper`; remaining phases pending.
**Author:** drafted with Claude (Opus 4.8), 2026-06-07.
**Goal:** Re-implement the fork's "show media art cover as the wallpaper, with a
synced lyrics overlay" feature on top of the new upstream architecture
(post `caelestia-dots/shell` merge, commit `25181f50`).

---

## 1. Background

The fork carried a custom feature: when a media player is active, the desktop
background switches from the static wallpaper to a **blurred album-art backdrop +
centered cover art + a synced lyrics overlay**, and the Material colour scheme is
re-derived from the album art.

Upstream then did two large rewrites that the feature was built on top of:

- **Lyrics:** the QML `services/LyricsService.qml` singleton was deleted and
  replaced by a C++ singleton `Caelestia.Services.Lyrics`
  (`plugin/src/Caelestia/Services/lyrics.{hpp,cpp}`).
- **Settings UI:** the old control center was removed and replaced by **nexus**
  (`modules/nexus/...`). The feature's toggle lived in a control-center
  `BackgroundSection.qml` that no longer exists.

During the upstream merge we **dropped the feature from active code** and reset
the affected files to upstream, to land a clean, building base. The complete old
implementation is preserved for reference on branch
**`backup/main-pre-upstream-merge`** (and in history at commit `92437fd0`).

This document maps the old implementation onto the new architecture and lays out
a phased port.

---

## 2. What the old feature did

Old files (all viewable via `git show backup/main-pre-upstream-merge:<path>`):

| File | Role |
|---|---|
| `plugin/src/Caelestia/Config/backgroundconfig.hpp` | Added `MediaWallpaperConfig` subobject: `enabled`, `showLyrics`, `trackDebounceMs` (450), `pauseRestoreDelayMs` (30000), `allowPlayers`, `blockPlayers`. |
| `modules/background/Wallpaper.qml` | Core logic: pick active player, debounce track changes, pause-restore timer, render blurred backdrop + cover art (local **and** remote art), trigger colour extraction. |
| `modules/background/WallpaperImage.qml` | Extracted static-wallpaper image component (so the media layers could sit alongside it). |
| `modules/background/Background.qml` | The lyrics overlay UI (5-line scrolling lyric stack with slide animation, blur/shadow effects). |
| `services/Colours.qml` | `previewComposedExternal` / `previewExternalRemote` / `previewExternal` / `clearExternalPreview` / `loadExternalPreview` + an `external` M3Palette. Generated a scheme from album art via the `caelestia wallpaper -p` CLI; downloaded remote art with `curl`; composed a backdrop with ImageMagick (`magick`). |
| `services/LyricsService.qml` | (fork modified) added a `positionSyncTimer` + `onPositionChanged` to keep the lyric index fresh while the overlay was visible. |
| `modules/controlcenter/appearance/sections/BackgroundSection.qml` + `AppearancePane.qml` | The settings toggles. |

### Key behaviours to preserve

1. **Activation gate** (`mediaCanDisplay`): media mode is on when
   `mediaWallpaper.enabled` **and** a player is active **and** the player passes
   the allow/block lists **and** album art exists **and** the pause-restore
   timeout has not fired.
2. **Track debounce:** rapid track changes are debounced (`trackDebounceMs`) so
   the backdrop/colours don't thrash.
3. **Pause-restore:** when playback pauses, after `pauseRestoreDelayMs` the
   static wallpaper is restored; resuming playback cancels that.
4. **Allow/Block players:** filter by player identity (using
   `Players.getIdentity`).
5. **Local vs remote art:** local `file://` art is used directly; remote
   (e.g. YouTube `https://`) art is downloaded and cached before use.
6. **Dynamic colours from art:** only when `scheme === "dynamic"`. Composes a
   blurred backdrop, runs `caelestia wallpaper -p <path>` to produce a scheme
   JSON, loads it into an `external` palette that overrides `current` while media
   mode is active.
7. **Lyrics overlay:** 5 visible lines (before-prev, prev, current, next,
   after-next), current line emphasised + slide animation as the index advances.

---

## 3. What changed upstream (the architecture we must target)

### 3.1 Lyrics: QML singleton → C++ singleton

New API — `import Caelestia.Services` then use `Lyrics`:

| Old (`LyricsService`) | New (`Lyrics`) |
|---|---|
| `LyricsService.model` (ListModel, `lyricLine` role) | `Lyrics.lyrics` — `QStringList` of lines |
| `LyricsService.currentIndex` (self-tracked) | `Lyrics.indexForTime(timeMs)` — **caller supplies the position** |
| internal player tracking | `Lyrics.setTrack(artist, title, album, durationMs)` / `Lyrics.clearTrack()` |
| `LyricsService.isManualSeeking` | **no equivalent** — must be dropped or re-derived |
| n/a | `Lyrics.hasLyrics`, `Lyrics.loading`, `Lyrics.offset`, `Lyrics.refresh()` |

**Consequence:** the new `Lyrics` service is *stateless about playback position*.
Whoever shows lyrics must (a) drive `setTrack` from the active player and
(b) poll the player position and call `indexForTime`.

Reference consumer: `modules/dashboard/media/LyricList.qml` shows the canonical
pattern:

```qml
// drive the track (side-effecting binding)
readonly property var _: {
    const p = Players.active;
    if (p) Lyrics.setTrack(p.trackArtist, p.trackTitle, p.trackAlbum, p.length);
    else   Lyrics.clearTrack();
}
// current line index
currentIndex = Lyrics.indexForTime(Players.active?.position ?? 0);
```

> ⚠️ `setTrack` mutates a **global** singleton. If both the dashboard and the
> wallpaper overlay call it, they must not fight. Plan: introduce a single small
> driver (see §5, Phase 0) that always keeps `Lyrics` synced to `Players.active`,
> and have both consumers be read-only.

### 3.2 Position polling

Quickshell's `MprisPlayer.position` only refreshes when nudged. The new code
forces it with a timer calling `positionChanged()`:

```qml
// modules/dashboard/dash/Media.qml:38
Timer { running: ...; repeat: true; onTriggered: Players.active?.positionChanged() }
```

The overlay needs the same: a repeating timer (only while media-lyrics is
visible) that calls `Players.active.positionChanged()` so `indexForTime` advances.

### 3.3 Players service — unchanged enough

`services/Players.qml` still provides everything the old feature used:
`Players.active`, `Players.getArtUrl(player)`, `Players.getIdentity(player)`.
Player props available in the new tree: `isPlaying`, `position`, `length`,
`trackArtist`, `trackTitle`, `trackAlbum`, `positionSupported`,
`positionChanged()`. ✅ No changes needed here.

### 3.4 Background / Wallpaper

New `modules/background/Wallpaper.qml` is simpler: it creates a `CachingImage`
via `imgComp.createObject(...)` and cross-fades. There is **no** `WallpaperImage.qml`
anymore. The media layers + overlay must be re-introduced here (or in a sibling
component loaded by `Background.qml`).

New `modules/background/Background.qml` no longer has the `hasBackgroundSurface`
media branch or the lyrics overlay — both must be re-added.

### 3.5 Colours service

`services/Colours.qml` still has the primitives the port needs:
`load(data, isPreview)`, `showPreview`, a `preview` palette, `ImageAnalyser`, and
the `caelestia scheme` / `caelestia wallpaper` CLIs. So the `external`-preview
extension can be re-applied almost as-is. (Note: the old fork also added a
`Hyprland.usingLua` branch to `reloadHyprRules` here; that was a *dispatcher/lua*
tweak unrelated to media and is currently NOT present — re-add separately if
wanted, it is out of scope for this feature.)

### 3.6 Settings UI: nexus

Toggles now live in `modules/nexus/pages/WallpaperAndStyle.qml`, built from
`modules/nexus/common/ToggleRow.qml` (a `StyledSwitch`). Adding options is a
matter of more `ToggleRow`s bound to `Config.background.mediaWallpaper.*` /
`GlobalConfig.background.mediaWallpaper.*`, optionally with a dedicated subpage
for the numeric/list settings (debounce, delays, allow/block lists). Subpages are
opened via `root.nState.openSubPage(n)` and registered in the nexus page
registry.

---

## 4. Gap analysis (old dependency → new target)

| Old dependency | New target | Effort |
|---|---|---|
| `MediaWallpaperConfig` in `backgroundconfig.hpp` | Re-add identical subobject; **C++ plugin rebuild required** | Low (copy) |
| `LyricsService.model` / `currentIndex` | `Lyrics.lyrics` + `Lyrics.indexForTime(position)` | **Medium** — rewrite overlay index logic |
| `LyricsService.isManualSeeking` | none | Low — drop the seek-aware animation shortcut |
| `LyricsService.positionSyncTimer` | overlay-local position timer → `positionChanged()` | Low |
| `Colours.previewComposedExternal` etc. + `external` palette | Re-apply to new `Colours.qml` | Medium (re-apply, re-test) |
| `Wallpaper.qml` media layers + `WallpaperImage.qml` | Re-introduce in new `Wallpaper.qml` | **Medium/High** — structure changed |
| Lyrics overlay (`Background.qml`) | Re-add as overlay; rewire to `Lyrics.lyrics`/`indexForTime` | **Medium** |
| control-center `BackgroundSection.qml` | nexus `WallpaperAndStyle.qml` toggles (+ optional subpage) | Medium |

---

## 5. Proposed port plan (phased)

Each phase should build & run before moving on. Do the work on a feature branch
off current `main` (e.g. `feat/media-wallpaper-report`), not on `main` directly.

### Phase 1 — Config (C++) ✅ done
- Re-added `MediaWallpaperConfig` to `backgroundconfig.hpp` (matches the backup
  branch: `enabled`, `showLyrics`, `trackDebounceMs`, `pauseRestoreDelayMs`,
  `allowPlayers`, `blockPlayers`).
- Build verified (`cmake --build build`). Needs `sudo cmake --install build` to
  deploy. README config block still to update (Phase 6).

### Phase 2 — Lyrics driver (foundation) ✅ done
- Added `modules/LyricsDriver.qml` — a root-scope driver (same pattern as
  `BatteryMonitor`/`ConfigToasts`), instantiated in `shell.qml`.
- It keeps `Lyrics.setTrack/clearTrack` synced to `Players.active`
  **independent of the dashboard**, so the wallpaper overlay has lyrics even
  when the dashboard was never opened.
- **Decision (was open question #1):** *gated* on
  `background.mediaWallpaper.enabled && .showLyrics` so we preserve upstream's
  lazy-lyrics intent (no lyric fetches when the overlay is off).
- **Decision (was open question on double-driving):** `Lyrics::setTrack` is
  idempotent (early-returns on unchanged track), so the driver and the
  dashboard's own `LyricList` driver can coexist. We therefore **leave
  upstream's `LyricList.qml` untouched** to minimise future merge friction.

### Phase 2 — Colour extraction
- Re-apply the `external`-preview functions + `external` palette to
  `services/Colours.qml`.
- Verify `ImageAnalyser.source` switch and the `caelestia wallpaper -p` /
  `curl` / `magick` external processes still behave (paths under
  `Paths.imagecache`).
- Gate strictly on `scheme === "dynamic"` as before.

### Phase 3 — Media wallpaper rendering
- Re-introduce the blurred backdrop + cover-art layers into the new
  `Wallpaper.qml` (local + remote variants), plus the debounce + pause-restore
  timers and the `mediaCanDisplay` gate.
- Decide: keep a re-created `WallpaperImage.qml`, or layer media on top of the
  new `imgComp` approach. (Lean: add media layers as siblings, keep upstream's
  static-wallpaper code path untouched.)

### Phase 4 — Lyrics overlay
- Re-add the overlay (from old `Background.qml`) but rewired:
  - lines from `Lyrics.lyrics[idx]` instead of `model.get(idx).lyricLine`.
  - current index from `Lyrics.indexForTime(Players.active.position)`.
  - add the position-poll `Timer` (only running while overlay visible).
  - drop `isManualSeeking`-based animation branch (or re-derive a "seek" as a
    large index jump).
- Gate on `Config.background.mediaWallpaper.showLyrics` + `Lyrics.hasLyrics`.

### Phase 5 — nexus settings UI
- Add `ToggleRow`s to `WallpaperAndStyle.qml`: "Media wallpaper",
  "Show lyrics on wallpaper".
- Optionally a subpage for debounce/delay/allow-block lists.

### Phase 6 — Docs & polish
- Update `README.md` `background` config block with the `mediaWallpaper` keys.
- Manual test matrix (below).

---

## 6. Open questions / decisions needed

1. **Double-driving `Lyrics.setTrack`** — confirm the Phase 0 driver approach is
   acceptable, or whether the overlay should just read and rely on the dashboard
   driving (means lyrics on wallpaper only work when the dashboard has been
   opened — probably undesirable).
2. **`isManualSeeking`** is gone — acceptable to lose the seek-aware instant
   animation, or re-derive it (detect index jumps > 1)?
3. **Scope of UI** — simple two toggles now, full subpage later? Or all at once?
4. **Lua/dispatcher `reloadHyprRules`** tweak that was bundled in the old
   `Colours.qml` — re-add it as part of the separate dispatcher customisation, or
   leave out? (Out of scope here, just flagging it was dropped.)
5. **Cover-art-as-wallpaper vs colours-only** — keep both sub-behaviours, or is
   one of them the priority?

---

## 7. Test matrix (manual, once ported)

- Play local-file media (e.g. mpv/local) → backdrop + cover + colours + lyrics.
- Play remote media (YouTube via browser MPRIS) → remote art download + render.
- Pause → after `pauseRestoreDelayMs`, static wallpaper returns; resume cancels.
- Rapid next/next/next → debounce prevents thrash.
- Allow/block lists → correct players included/excluded.
- `scheme` not `dynamic` → colours unchanged, art still shows.
- `showLyrics=false` → art shows, no overlay.
- No lyrics found → overlay hidden, no error spam.
- Multi-monitor → per-screen background still correct.

---

## 8. Reference pointers

- Old implementation: branch **`backup/main-pre-upstream-merge`**, e.g.
  `git show backup/main-pre-upstream-merge:modules/background/Wallpaper.qml`.
- New lyrics service: `plugin/src/Caelestia/Services/lyrics.hpp`.
- New lyrics consumer pattern: `modules/dashboard/media/LyricList.qml`.
- Position-poll pattern: `modules/dashboard/dash/Media.qml`.
- New settings page: `modules/nexus/pages/WallpaperAndStyle.qml`,
  `modules/nexus/common/ToggleRow.qml`.
- Merge commit that dropped the feature: `25181f50`.
