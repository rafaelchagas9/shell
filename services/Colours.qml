pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.services
import qs.utils

Singleton {
    id: root

    property bool showPreview
    property string scheme
    property string flavour
    readonly property bool light: showPreview ? previewLight : externalPreviewActive ? externalPreviewLight : currentLight
    property bool currentLight
    property bool previewLight
    readonly property M3Palette palette: showPreview ? preview : externalPreviewActive ? external : current
    readonly property M3TPalette tPalette: M3TPalette {}
    readonly property M3Palette current: M3Palette {}
    readonly property M3Palette external: M3Palette {}
    readonly property M3Palette preview: M3Palette {}
    readonly property Transparency transparency: Transparency {}
    readonly property alias wallLuminance: analyser.luminance

    property bool cooldownPending
    property real lastBaseTransparency

    // External (media-art) colour preview: when a media wallpaper is active and
    // the scheme is "dynamic", a scheme is extracted from the album art and
    // loaded into `external`, overriding `current` while `externalPreviewActive`.
    property bool externalPreviewReady
    property bool externalPreviewLight
    property string externalPreviewPath
    property string externalPreviewKey
    property string composedPreviewSource
    property string composedPreviewPath
    property string composedPreviewKey
    property string remotePreviewUrl
    property string remotePreviewPath
    property string remotePreviewKey
    readonly property bool externalPreviewActive: !showPreview && externalPreviewReady && externalPreviewKey.length > 0

    function getLuminance(c: color): real {
        if (c.r == 0 && c.g == 0 && c.b == 0)
            return 0;
        return Math.sqrt(0.299 * (c.r ** 2) + 0.587 * (c.g ** 2) + 0.114 * (c.b ** 2));
    }

    function alterColour(c: color, a: real, layer: int): color {
        const luminance = getLuminance(c);

        const offset = (!light || layer == 1 ? 1 : -layer / 2) * (light ? 0.2 : 0.3) * (1 - transparency.base) * (1 + wallLuminance * (light ? (layer == 1 ? 3 : 1) : 2.5));
        const scale = (luminance + offset) / luminance;
        const r = Math.max(0, Math.min(1, c.r * scale));
        const g = Math.max(0, Math.min(1, c.g * scale));
        const b = Math.max(0, Math.min(1, c.b * scale));

        return Qt.rgba(r, g, b, a);
    }

    function layer(c: color, layer: var): color {
        if (!transparency.enabled)
            return c;

        return layer === 0 ? Qt.alpha(c, transparency.base) : alterColour(c, transparency.layers, layer ?? 1);
    }

    function on(c: color): color {
        if (c.hslLightness < 0.5)
            return Qt.hsla(c.hslHue, c.hslSaturation, 0.9, 1);
        return Qt.hsla(c.hslHue, c.hslSaturation, 0.1, 1);
    }

    function load(data: string, isPreview: bool): void {
        const colours = isPreview ? preview : current;
        const scheme = JSON.parse(data);

        if (!isPreview) {
            root.scheme = scheme.name;
            flavour = scheme.flavour;
            currentLight = scheme.mode === "light";
        } else {
            previewLight = scheme.mode === "light";
        }

        for (const [name, colour] of Object.entries(scheme.colours)) {
            const propName = name.startsWith("term") ? name : `m3${name}`;
            if (colours.hasOwnProperty(propName))
                colours[propName] = `#${colour}`;
        }
    }

    function loadExternalPreview(data: string): void {
        const scheme = JSON.parse(data);

        externalPreviewLight = scheme.mode === "light";

        for (const [name, colour] of Object.entries(scheme.colours)) {
            const propName = name.startsWith("term") ? name : `m3${name}`;
            if (external.hasOwnProperty(propName))
                external[propName] = `#${colour}`;
        }

        externalPreviewReady = true;
    }

    function shellQuote(value: string): string {
        return `'${value.replace(/'/g, "'\\''")}'`;
    }

    function hashString(value: string): string {
        let h1 = 0xdeadbeef;
        let h2 = 0x41c6ce57;

        for (let i = 0; i < value.length; i++) {
            const ch = value.charCodeAt(i);
            h1 = Math.imul(h1 ^ ch, 2654435761);
            h2 = Math.imul(h2 ^ ch, 1597334677);
        }

        h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507);
        h1 ^= Math.imul(h2 ^ (h2 >>> 13), 3266489909);
        h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507);
        h2 ^= Math.imul(h1 ^ (h1 >>> 13), 3266489909);

        return (h2 >>> 0).toString(16).padStart(8, "0") + (h1 >>> 0).toString(16).padStart(8, "0");
    }

    function remoteCachePath(url: string): string {
        const cleanUrl = url.split("?")[0];
        const match = cleanUrl.match(/\.([A-Za-z0-9]{1,5})$/);
        const ext = match ? match[1].toLowerCase() : "img";
        return `${Paths.imagecache}/mediawallpaper/${hashString(url)}.${ext}`;
    }

    function composedCachePath(cacheKey: string): string {
        return `${Paths.imagecache}/mediawallpaper-composed/${hashString(`v1:${cacheKey}`)}.jpg`;
    }

    function previewComposedExternal(path: string, key: string, cacheKey: string): void {
        if (scheme !== "dynamic" || !path || !key || !cacheKey)
            return;

        const composedPath = composedCachePath(cacheKey);

        if (composedPreviewSource === path && composedPreviewKey === key && composedPreviewPath === composedPath && (composePreviewProc.running || (externalPreviewPath === composedPath && externalPreviewReady)))
            return;

        composedPreviewSource = path;
        composedPreviewPath = composedPath;
        composedPreviewKey = key;

        if (externalPreviewProc.running)
            externalPreviewProc.running = false;

        externalPreviewPath = composedPath;
        externalPreviewKey = key;
        externalPreviewReady = false;

        const quotedDir = shellQuote(`${Paths.imagecache}/mediawallpaper-composed`);
        const quotedSource = shellQuote(path);
        const quotedOut = shellQuote(composedPath);
        composePreviewProc.command = ["sh", "-c", `mkdir -p ${quotedDir} && magick \\( ${quotedSource} -resize 1920x1080^ -gravity center -extent 1920x1080 -blur 0x24 \\) \\( -size 1920x1080 xc:'rgba(0,0,0,0.28)' \\) -compose over -composite \\( ${quotedSource} -resize 720x720 \\) -gravity center -compose over -composite ${quotedOut}`];
        composePreviewProc.running = true;
    }

    function previewExternal(path: string, key: string): void {
        if (scheme !== "dynamic" || !path || !key)
            return;

        if (externalPreviewPath === path && externalPreviewKey === key && externalPreviewReady)
            return;

        externalPreviewPath = path;
        externalPreviewKey = key;
        externalPreviewReady = false;
        externalPreviewProc.command = ["caelestia", "wallpaper", "-p", path, ...(GlobalConfig.services.smartScheme ? [] : ["--no-smart"])];
        externalPreviewProc.running = true;
    }

    function previewExternalRemote(url: string, key: string): void {
        if (scheme !== "dynamic" || !url || !key)
            return;

        const cachePath = remoteCachePath(url);

        if (remotePreviewUrl === url && remotePreviewKey === key && (remoteDownloadProc.running || (externalPreviewPath === cachePath && externalPreviewReady)))
            return;

        remotePreviewUrl = url;
        remotePreviewKey = key;
        remotePreviewPath = cachePath;

        if (externalPreviewProc.running)
            externalPreviewProc.running = false;

        externalPreviewPath = cachePath;
        externalPreviewKey = key;
        externalPreviewReady = false;

        const quotedDir = shellQuote(`${Paths.imagecache}/mediawallpaper`);
        const quotedPath = shellQuote(cachePath);
        const quotedUrl = shellQuote(url);
        remoteDownloadProc.command = ["sh", "-c", `mkdir -p ${quotedDir} && curl -L --fail --silent --show-error ${quotedUrl} -o ${quotedPath}`];
        remoteDownloadProc.running = true;
    }

    function clearExternalPreview(key: string): void {
        if (key && externalPreviewKey !== key)
            return;

        remotePreviewUrl = "";
        remotePreviewPath = "";
        remotePreviewKey = "";
        composedPreviewSource = "";
        composedPreviewPath = "";
        composedPreviewKey = "";
        externalPreviewPath = "";
        externalPreviewKey = "";
        externalPreviewReady = false;
        if (composePreviewProc.running)
            composePreviewProc.running = false;
        if (externalPreviewProc.running)
            externalPreviewProc.running = false;
        if (remoteDownloadProc.running)
            remoteDownloadProc.running = false;
    }

    function setMode(mode: string): void {
        Quickshell.execDetached(["caelestia", "scheme", "set", "--notify", "-m", mode]);
    }

    function reloadHyprRules(): void {
        const str = "keyword layerrule %1 %2, match:namespace caelestia-drawers";
        Hypr.extras.batchMessage([str.arg("blur").arg(transparency.enabled ? 1 : 0), str.arg("ignore_alpha").arg(transparency.base - 0.03)]);
    }

    function requestReloadHyprRules(): void {
        if (cooldownTimer.running) {
            root.cooldownPending = true;
        } else {
            root.reloadHyprRules();
            cooldownTimer.restart();
        }
    }

    Component.onCompleted: root.requestReloadHyprRules()

    Connections {
        function onConfigReloaded(): void {
            root.reloadHyprRules();
        }

        target: Hypr
    }

    FileView {
        path: `${Paths.state}/scheme.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.load(text(), false)
    }

    ImageAnalyser {
        id: analyser

        source: root.showPreview ? Wallpapers.previewPath : root.externalPreviewActive ? root.externalPreviewPath : Wallpapers.current
    }

    Process {
        id: externalPreviewProc

        stdout: StdioCollector {
            onStreamFinished: {
                if (root.externalPreviewPath.length === 0)
                    return;

                root.loadExternalPreview(text);
            }
        }
    }

    Process {
        id: composePreviewProc

        onExited: exitCode => { // qmllint disable signal-handler-parameters
            if (exitCode !== 0)
                return;

            if (!root.composedPreviewPath || !root.composedPreviewKey)
                return;

            root.previewExternal(root.composedPreviewPath, root.composedPreviewKey);
        }
    }

    Process {
        id: remoteDownloadProc

        onExited: exitCode => { // qmllint disable signal-handler-parameters
            if (exitCode !== 0)
                return;

            if (!root.remotePreviewPath || !root.remotePreviewKey)
                return;

            root.previewComposedExternal(root.remotePreviewPath, root.remotePreviewKey, root.remotePreviewUrl);
        }
    }

    Timer {
        id: cooldownTimer

        interval: 30
        onTriggered: {
            if (root.cooldownPending) {
                root.cooldownPending = false;
                root.reloadHyprRules();
                restart();
            }
        }
    }

    Timer {
        id: cAnimCompleteTimer

        interval: Tokens.anim.durations.expressiveSlowEffects
        onTriggered: root.requestReloadHyprRules()
    }

    component Transparency: QtObject {
        readonly property bool enabled: Tokens.transparency.enabled
        readonly property real base: Math.max(0, Math.min(1, Tokens.transparency.base - (root.light ? 0.1 : 0)))
        readonly property real layers: Tokens.transparency.layers

        onEnabledChanged: {
            if (enabled)
                root.requestReloadHyprRules();
            else
                cAnimCompleteTimer.start();
        }
        onBaseChanged: {
            if (root.lastBaseTransparency > base)
                root.requestReloadHyprRules();
            else
                cAnimCompleteTimer.start();
            root.lastBaseTransparency = base;
        }
    }

    component M3TPalette: QtObject {
        readonly property color m3primary_paletteKeyColor: root.layer(root.palette.m3primary_paletteKeyColor)
        readonly property color m3secondary_paletteKeyColor: root.layer(root.palette.m3secondary_paletteKeyColor)
        readonly property color m3tertiary_paletteKeyColor: root.layer(root.palette.m3tertiary_paletteKeyColor)
        readonly property color m3neutral_paletteKeyColor: root.layer(root.palette.m3neutral_paletteKeyColor)
        readonly property color m3neutral_variant_paletteKeyColor: root.layer(root.palette.m3neutral_variant_paletteKeyColor)
        readonly property color m3background: root.layer(root.palette.m3background, 0)
        readonly property color m3onBackground: root.layer(root.palette.m3onBackground)
        readonly property color m3surface: root.layer(root.palette.m3surface, 0)
        readonly property color m3surfaceDim: root.layer(root.palette.m3surfaceDim, 0)
        readonly property color m3surfaceBright: root.layer(root.palette.m3surfaceBright, 0)
        readonly property color m3surfaceContainerLowest: root.layer(root.palette.m3surfaceContainerLowest)
        readonly property color m3surfaceContainerLow: root.layer(root.palette.m3surfaceContainerLow)
        readonly property color m3surfaceContainer: root.layer(root.palette.m3surfaceContainer)
        readonly property color m3surfaceContainerHigh: root.layer(root.palette.m3surfaceContainerHigh)
        readonly property color m3surfaceContainerHighest: root.layer(root.palette.m3surfaceContainerHighest)
        readonly property color m3onSurface: root.layer(root.palette.m3onSurface)
        readonly property color m3surfaceVariant: root.layer(root.palette.m3surfaceVariant, 0)
        readonly property color m3onSurfaceVariant: root.layer(root.palette.m3onSurfaceVariant)
        readonly property color m3inverseSurface: root.layer(root.palette.m3inverseSurface, 0)
        readonly property color m3inverseOnSurface: root.layer(root.palette.m3inverseOnSurface)
        readonly property color m3outline: root.layer(root.palette.m3outline)
        readonly property color m3outlineVariant: root.layer(root.palette.m3outlineVariant)
        readonly property color m3shadow: root.layer(root.palette.m3shadow)
        readonly property color m3scrim: root.layer(root.palette.m3scrim)
        readonly property color m3surfaceTint: root.layer(root.palette.m3surfaceTint)
        readonly property color m3primary: root.layer(root.palette.m3primary)
        readonly property color m3onPrimary: root.layer(root.palette.m3onPrimary)
        readonly property color m3primaryContainer: root.layer(root.palette.m3primaryContainer)
        readonly property color m3onPrimaryContainer: root.layer(root.palette.m3onPrimaryContainer)
        readonly property color m3inversePrimary: root.layer(root.palette.m3inversePrimary)
        readonly property color m3secondary: root.layer(root.palette.m3secondary)
        readonly property color m3onSecondary: root.layer(root.palette.m3onSecondary)
        readonly property color m3secondaryContainer: root.layer(root.palette.m3secondaryContainer)
        readonly property color m3onSecondaryContainer: root.layer(root.palette.m3onSecondaryContainer)
        readonly property color m3tertiary: root.layer(root.palette.m3tertiary)
        readonly property color m3onTertiary: root.layer(root.palette.m3onTertiary)
        readonly property color m3tertiaryContainer: root.layer(root.palette.m3tertiaryContainer)
        readonly property color m3onTertiaryContainer: root.layer(root.palette.m3onTertiaryContainer)
        readonly property color m3error: root.layer(root.palette.m3error)
        readonly property color m3onError: root.layer(root.palette.m3onError)
        readonly property color m3errorContainer: root.layer(root.palette.m3errorContainer)
        readonly property color m3onErrorContainer: root.layer(root.palette.m3onErrorContainer)
        readonly property color m3success: root.layer(root.palette.m3success)
        readonly property color m3onSuccess: root.layer(root.palette.m3onSuccess)
        readonly property color m3successContainer: root.layer(root.palette.m3successContainer)
        readonly property color m3onSuccessContainer: root.layer(root.palette.m3onSuccessContainer)
        readonly property color m3primaryFixed: root.layer(root.palette.m3primaryFixed)
        readonly property color m3primaryFixedDim: root.layer(root.palette.m3primaryFixedDim)
        readonly property color m3onPrimaryFixed: root.layer(root.palette.m3onPrimaryFixed)
        readonly property color m3onPrimaryFixedVariant: root.layer(root.palette.m3onPrimaryFixedVariant)
        readonly property color m3secondaryFixed: root.layer(root.palette.m3secondaryFixed)
        readonly property color m3secondaryFixedDim: root.layer(root.palette.m3secondaryFixedDim)
        readonly property color m3onSecondaryFixed: root.layer(root.palette.m3onSecondaryFixed)
        readonly property color m3onSecondaryFixedVariant: root.layer(root.palette.m3onSecondaryFixedVariant)
        readonly property color m3tertiaryFixed: root.layer(root.palette.m3tertiaryFixed)
        readonly property color m3tertiaryFixedDim: root.layer(root.palette.m3tertiaryFixedDim)
        readonly property color m3onTertiaryFixed: root.layer(root.palette.m3onTertiaryFixed)
        readonly property color m3onTertiaryFixedVariant: root.layer(root.palette.m3onTertiaryFixedVariant)
    }

    component M3Palette: QtObject {
        property color m3primary_paletteKeyColor: "#a8627b"
        property color m3secondary_paletteKeyColor: "#8e6f78"
        property color m3tertiary_paletteKeyColor: "#986e4c"
        property color m3neutral_paletteKeyColor: "#807477"
        property color m3neutral_variant_paletteKeyColor: "#837377"
        property color m3background: "#191114"
        property color m3onBackground: "#efdfe2"
        property color m3surface: "#191114"
        property color m3surfaceDim: "#191114"
        property color m3surfaceBright: "#403739"
        property color m3surfaceContainerLowest: "#130c0e"
        property color m3surfaceContainerLow: "#22191c"
        property color m3surfaceContainer: "#261d20"
        property color m3surfaceContainerHigh: "#31282a"
        property color m3surfaceContainerHighest: "#3c3235"
        property color m3onSurface: "#efdfe2"
        property color m3surfaceVariant: "#514347"
        property color m3onSurfaceVariant: "#d5c2c6"
        property color m3inverseSurface: "#efdfe2"
        property color m3inverseOnSurface: "#372e30"
        property color m3outline: "#9e8c91"
        property color m3outlineVariant: "#514347"
        property color m3shadow: "#000000"
        property color m3scrim: "#000000"
        property color m3surfaceTint: "#ffb0ca"
        property color m3primary: "#ffb0ca"
        property color m3onPrimary: "#541d34"
        property color m3primaryContainer: "#6f334a"
        property color m3onPrimaryContainer: "#ffd9e3"
        property color m3inversePrimary: "#8b4a62"
        property color m3secondary: "#e2bdc7"
        property color m3onSecondary: "#422932"
        property color m3secondaryContainer: "#5a3f48"
        property color m3onSecondaryContainer: "#ffd9e3"
        property color m3tertiary: "#f0bc95"
        property color m3onTertiary: "#48290c"
        property color m3tertiaryContainer: "#b58763"
        property color m3onTertiaryContainer: "#000000"
        property color m3error: "#ffb4ab"
        property color m3onError: "#690005"
        property color m3errorContainer: "#93000a"
        property color m3onErrorContainer: "#ffdad6"
        property color m3success: "#B5CCBA"
        property color m3onSuccess: "#213528"
        property color m3successContainer: "#374B3E"
        property color m3onSuccessContainer: "#D1E9D6"
        property color m3primaryFixed: "#ffd9e3"
        property color m3primaryFixedDim: "#ffb0ca"
        property color m3onPrimaryFixed: "#39071f"
        property color m3onPrimaryFixedVariant: "#6f334a"
        property color m3secondaryFixed: "#ffd9e3"
        property color m3secondaryFixedDim: "#e2bdc7"
        property color m3onSecondaryFixed: "#2b151d"
        property color m3onSecondaryFixedVariant: "#5a3f48"
        property color m3tertiaryFixed: "#ffdcc3"
        property color m3tertiaryFixedDim: "#f0bc95"
        property color m3onTertiaryFixed: "#2f1500"
        property color m3onTertiaryFixedVariant: "#623f21"
        property color term0: "#353434"
        property color term1: "#ff4c8a"
        property color term2: "#ffbbb7"
        property color term3: "#ffdedf"
        property color term4: "#b3a2d5"
        property color term5: "#e98fb0"
        property color term6: "#ffba93"
        property color term7: "#eed1d2"
        property color term8: "#b39e9e"
        property color term9: "#ff80a3"
        property color term10: "#ffd3d0"
        property color term11: "#fff1f0"
        property color term12: "#dcbc93"
        property color term13: "#f9a8c2"
        property color term14: "#ffd1c0"
        property color term15: "#ffffff"
    }
}
