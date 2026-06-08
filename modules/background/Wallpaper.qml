pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Caelestia.Config
import qs.components
import qs.components.filedialog
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    readonly property bool staticWallpaperEnabled: Config.background.wallpaperEnabled
    property string source: staticWallpaperEnabled ? Wallpapers.current : ""
    property CachingImage current
    property bool completed

    // --- Media wallpaper (album art backdrop + cover) -----------------------
    readonly property var mediaPlayer: Players.active
    readonly property string mediaArtUrl: Players.getArtUrl(mediaPlayer)
    readonly property bool mediaModeEnabled: Config.background.mediaWallpaper.enabled
    readonly property int mediaTrackDebounceMs: Math.max(0, Config.background.mediaWallpaper.trackDebounceMs)
    readonly property int mediaPauseRestoreDelayMs: Math.max(0, Config.background.mediaWallpaper.pauseRestoreDelayMs)
    readonly property bool mediaAllowed: {
        if (!mediaPlayer)
            return false;

        const allow = Config.background.mediaWallpaper.allowPlayers ?? [];
        const block = Config.background.mediaWallpaper.blockPlayers ?? [];
        const identity = Players.getIdentity(mediaPlayer);
        const rawIdentity = mediaPlayer.identity ?? "";

        const isBlocked = block.includes(identity) || block.includes(rawIdentity);
        if (isBlocked)
            return false;

        if (allow.length === 0)
            return true;

        return allow.includes(identity) || allow.includes(rawIdentity);
    }
    readonly property bool mediaCanDisplay: mediaModeEnabled && mediaAllowed && mediaArtUrl.length > 0 && !pauseTimedOut
    // Remote (http) art has no local file; resolve only local file:// or path urls.
    readonly property string debouncedMediaArtPath: debouncedMediaArtUrl.startsWith("http") ? "" : Paths.toLocalFile(debouncedMediaArtUrl)

    property string debouncedMediaArtUrl: ""
    property string pendingMediaArtUrl: ""
    property bool pauseTimedOut: false

    function syncDynamicColours(): void {
        if (root.mediaCanDisplay && root.debouncedMediaArtPath.length > 0)
            Colours.previewComposedExternal(root.debouncedMediaArtPath, "media-wallpaper", root.debouncedMediaArtPath);
        else if (root.mediaCanDisplay && root.debouncedMediaArtUrl.length > 0)
            Colours.previewExternalRemote(root.debouncedMediaArtUrl, "media-wallpaper");
        else
            Colours.clearExternalPreview("media-wallpaper");
    }

    onMediaArtUrlChanged: {
        if (!mediaCanDisplay || mediaArtUrl.length === 0) {
            pendingMediaArtUrl = "";
            if (!trackDebounce.running)
                debouncedMediaArtUrl = "";
            return;
        }

        if (debouncedMediaArtUrl.length === 0) {
            debouncedMediaArtUrl = mediaArtUrl;
            pendingMediaArtUrl = "";
            return;
        }

        pendingMediaArtUrl = mediaArtUrl;
        trackDebounce.restart();
    }

    onMediaCanDisplayChanged: {
        if (!mediaCanDisplay) {
            trackDebounce.stop();
            pendingMediaArtUrl = "";
            debouncedMediaArtUrl = "";
        } else if (debouncedMediaArtUrl.length === 0 && mediaArtUrl.length > 0) {
            debouncedMediaArtUrl = mediaArtUrl;
        }

        syncDynamicColours();
    }

    onDebouncedMediaArtUrlChanged: syncDynamicColours()

    onMediaPlayerChanged: {
        if (!mediaPlayer || !mediaAllowed || mediaArtUrl.length === 0) {
            pauseRestoreTimer.stop();
            pauseTimedOut = false;
            return;
        }

        pauseTimedOut = false;
        if (mediaPlayer.isPlaying)
            pauseRestoreTimer.stop();
        else
            pauseRestoreTimer.restart();
    }
    // ------------------------------------------------------------------------

    onSourceChanged: {
        if (!source)
            current = null;
        else
            current = imgComp.createObject(this, {
                path: source
            });
    }

    Component.onCompleted: {
        if (source)
            Qt.callLater(() => {
                current = imgComp.createObject(this, {
                    path: source
                });
                completed = true;
            });
        else
            completed = true;

        syncDynamicColours();
    }

    Connections {
        function onIsPlayingChanged(): void {
            if (root.mediaPlayer?.isPlaying ?? false) {
                root.pauseTimedOut = false;
                pauseRestoreTimer.stop();
            } else if (root.mediaAllowed && root.mediaArtUrl.length > 0) {
                root.pauseTimedOut = false;
                pauseRestoreTimer.restart();
            }
        }

        target: root.mediaPlayer
    }

    Timer {
        id: trackDebounce

        interval: root.mediaTrackDebounceMs
        onTriggered: {
            if (!root.mediaCanDisplay)
                return;

            if (root.pendingMediaArtUrl.length > 0)
                root.debouncedMediaArtUrl = root.pendingMediaArtUrl;
            root.pendingMediaArtUrl = "";
        }
    }

    Timer {
        id: pauseRestoreTimer

        interval: root.mediaPauseRestoreDelayMs
        onTriggered: root.pauseTimedOut = true
    }

    Loader {
        asynchronous: true
        anchors.fill: parent

        active: root.completed && root.staticWallpaperEnabled && !root.source

        sourceComponent: StyledRect {
            color: Colours.palette.m3surfaceContainer

            Row {
                anchors.centerIn: parent
                spacing: Tokens.spacing.largeIncreased

                MaterialIcon {
                    text: "sentiment_stressed"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(5).build()
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: qsTr("Wallpaper missing?")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.builders.large.size(28 * 2).weight(Font.Bold).build()
                    }

                    StyledRect {
                        implicitWidth: selectWallText.implicitWidth + Tokens.padding.extraLargeIncreased
                        implicitHeight: selectWallText.implicitHeight + Tokens.padding.small

                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        FileDialog {
                            id: dialog

                            title: qsTr("Select a wallpaper")
                            filterLabel: qsTr("Image files")
                            filters: Images.validImageExtensions
                            onAccepted: path => Wallpapers.setWallpaper(path)
                        }

                        StateLayer {
                            radius: parent.radius
                            color: Colours.palette.m3onPrimary
                            onClicked: dialog.open()
                        }

                        StyledText {
                            id: selectWallText

                            anchors.centerIn: parent

                            text: qsTr("Set it now!")
                            color: Colours.palette.m3onPrimary
                            font: Tokens.font.body.large
                        }
                    }
                }
            }
        }
    }

    Component {
        id: imgComp

        CachingImage {
            id: img

            anchors.fill: parent

            opacity: 0

            onStatusChanged: {
                if (status === Image.Ready)
                    anim.start();
            }

            Anim on opacity {
                id: anim

                type: Anim.SlowEffects
                running: false
                from: 0
                to: 1
            }

            Timer {
                running: root.current !== img && root.current?.status === Image.Ready
                interval: anim.duration
                onTriggered: img.destroy()
            }
        }
    }

    // --- Media wallpaper layers (sit on top of the static wallpaper) --------
    // Explicit z keeps these above the static wallpaper image, which upstream
    // creates dynamically (imgComp.createObject) *after* these declared layers
    // and would otherwise paint over them.
    Loader {
        id: mediaBackdropLoader

        z: 1
        anchors.fill: parent
        active: root.mediaCanDisplay && root.debouncedMediaArtUrl.length > 0
        asynchronous: true
        sourceComponent: root.debouncedMediaArtPath.length > 0 ? localMediaBackdrop : remoteMediaBackdrop
    }

    Rectangle {
        z: 2
        anchors.fill: parent
        visible: root.mediaCanDisplay
        color: Qt.alpha("black", 0.28)
    }

    Loader {
        id: coverArtLoader

        z: 3
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) * 0.5
        height: width
        active: root.mediaCanDisplay && root.debouncedMediaArtUrl.length > 0
        asynchronous: true
        sourceComponent: coverArt
    }

    // Rounded cover with a drop shadow: the image is clipped to a rounded rect,
    // and the shadow is taken from the rounded composite via the wrapper's layer.
    Component {
        id: coverArt

        Item {
            anchors.fill: parent

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.alpha(Colours.palette.m3shadow, 0.75)
                shadowBlur: 0.9
                shadowVerticalOffset: 6
                autoPaddingEnabled: true
            }

            StyledClippingRect {
                anchors.fill: parent
                radius: Tokens.rounding.large

                Loader {
                    anchors.fill: parent
                    sourceComponent: root.debouncedMediaArtPath.length > 0 ? localCoverArt : remoteCoverArt
                }
            }
        }
    }

    Component {
        id: localMediaBackdrop

        CachingImage {
            anchors.fill: parent
            path: root.debouncedMediaArtPath
            smooth: true

            layer.enabled: visible
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1
                blurMax: 64
                saturation: 0.75
                brightness: -0.08
                autoPaddingEnabled: false
            }
        }
    }

    Component {
        id: remoteMediaBackdrop

        Image {
            anchors.fill: parent
            source: root.debouncedMediaArtUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            mipmap: true
            smooth: true
            sourceSize: Qt.size(width, height)

            layer.enabled: visible
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1
                blurMax: 64
                saturation: 0.75
                brightness: -0.08
                autoPaddingEnabled: false
            }
        }
    }

    Component {
        id: localCoverArt

        CachingImage {
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            path: root.debouncedMediaArtPath
            smooth: true
        }
    }

    Component {
        id: remoteCoverArt

        Image {
            anchors.fill: parent
            source: root.debouncedMediaArtUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            mipmap: true
            smooth: true
            sourceSize: Qt.size(width, height)
        }
    }
}
