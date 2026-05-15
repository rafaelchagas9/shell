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

    readonly property var mediaPlayer: Players.active
    readonly property string mediaArtUrl: Players.getArtUrl(mediaPlayer)
    readonly property bool mediaModeEnabled: Config.background.mediaWallpaper.enabled
    readonly property bool staticWallpaperEnabled: Config.background.wallpaperEnabled
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
    readonly property string debouncedMediaArtPath: Paths.toLocalFile(debouncedMediaArtUrl)
    readonly property string wallpaperSource: staticWallpaperEnabled ? Wallpapers.current : ""

    property string debouncedMediaArtUrl: ""
    property string pendingMediaArtUrl: ""
    property bool pauseTimedOut: false
    property var current: one
    property bool completed

    function syncDynamicColours() {
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

    onDebouncedMediaArtUrlChanged: {
        syncDynamicColours();
    }

    onMediaPlayerChanged: {
        if (!mediaPlayer || !mediaAllowed || mediaArtUrl.length === 0) {
            pauseRestoreTimer.stop();
            pauseTimedOut = false;
            return;
        }

        if (mediaPlayer.isPlaying) {
            pauseTimedOut = false;
            pauseRestoreTimer.stop();
        } else {
            pauseTimedOut = false;
            pauseRestoreTimer.restart();
        }
    }

    onWallpaperSourceChanged: {
        if (!wallpaperSource)
            current = null;
        else if (current === one)
            two.update();
        else
            one.update();
    }

    Component.onCompleted: {
        if (wallpaperSource)
            Qt.callLater(() => {
                one.update();
                completed = true;
            });
        else
            completed = true;

        syncDynamicColours();
    }

    Connections {
        function onIsPlayingChanged() {
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
        repeat: false
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
        repeat: false
        triggeredOnStart: false
        onTriggered: root.pauseTimedOut = true
    }

    Loader {
        asynchronous: true
        anchors.fill: parent

        active: root.completed && root.staticWallpaperEnabled && !root.wallpaperSource

        sourceComponent: StyledRect {
            color: Colours.palette.m3surfaceContainer

            Row {
                anchors.centerIn: parent
                spacing: Tokens.spacing.large

                MaterialIcon {
                    text: "sentiment_stressed"
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Tokens.font.size.extraLarge * 5
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: qsTr("Wallpaper missing?")
                        color: Colours.palette.m3onSurfaceVariant
                        font.pointSize: Tokens.font.size.extraLarge * 2
                        font.bold: true
                    }

                    StyledRect {
                        implicitWidth: selectWallText.implicitWidth + Tokens.padding.large * 2
                        implicitHeight: selectWallText.implicitHeight + Tokens.padding.small * 2

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
                            font.pointSize: Tokens.font.size.large
                        }
                    }
                }
            }
        }
    }

    WallpaperImage {
        id: one

        wallpaperSource: root.wallpaperSource
        wallpaperRoot: root
    }

    WallpaperImage {
        id: two

        wallpaperSource: root.wallpaperSource
        wallpaperRoot: root
    }

    Loader {
        id: mediaBackdropLoader

        anchors.fill: parent
        active: root.mediaCanDisplay && root.debouncedMediaArtUrl.length > 0
        asynchronous: true
        sourceComponent: root.debouncedMediaArtPath.length > 0 ? localMediaBackdrop : remoteMediaBackdrop
    }

    Rectangle {
        anchors.fill: parent
        visible: root.mediaCanDisplay
        color: Qt.alpha("black", 0.28)
    }

    Loader {
        id: coverArtLoader

        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) * 0.5
        height: width
        active: root.mediaCanDisplay && root.debouncedMediaArtUrl.length > 0
        asynchronous: true
        sourceComponent: root.debouncedMediaArtPath.length > 0 ? localCoverArt : remoteCoverArt
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
            fillMode: Image.PreserveAspectFit
            path: root.debouncedMediaArtPath
            smooth: true

            layer.enabled: visible
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.alpha(Colours.palette.m3shadow, 0.75)
                shadowBlur: 0.9
                shadowVerticalOffset: 6
            }
        }
    }

    Component {
        id: remoteCoverArt

        Image {
            anchors.fill: parent
            source: root.debouncedMediaArtUrl
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            mipmap: true
            smooth: true
            sourceSize: Qt.size(width, height)

            layer.enabled: visible
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.alpha(Colours.palette.m3shadow, 0.75)
                shadowBlur: 0.9
                shadowVerticalOffset: 6
            }
        }
    }
}
