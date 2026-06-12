pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.images
import qs.components.widgets
import qs.services

// The media wallpaper "now playing" scene: blurred album-art backdrop, tonal
// scrim, expressive-shape cover and optional track details + visualiser ring.
Item {
    id: root

    required property string artUrl

    readonly property var mediaConfig: Config.background.mediaWallpaper
    readonly property bool playing: Players.active?.isPlaying ?? false
    readonly property real coverSpan: Math.min(width, height) * Math.max(0.1, Math.min(0.9, mediaConfig.coverSize))
    readonly property real ringHeadroom: mediaConfig.showVisualiser ? coverSpan * 0.18 : 0

    function lengthStr(length: int): string {
        if (length < 0)
            return "-1:-1";

        const hours = Math.floor(length / 3600);
        const mins = Math.floor((length % 3600) / 60);
        const secs = Math.floor(length % 60).toString().padStart(2, "0");

        if (hours > 0)
            return `${hours}:${mins.toString().padStart(2, "0")}:${secs}`;
        return `${mins}:${secs}`;
    }

    FadeImage {
        anchors.fill: parent
        source: root.artUrl

        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1
            blurMax: 64
            saturation: 0.75
            brightness: -0.08
            autoPaddingEnabled: false
        }
    }

    StyledRect {
        anchors.fill: parent
        color: Qt.alpha(Colours.palette.m3scrim, Math.max(0, Math.min(1, root.mediaConfig.scrimOpacity)))
    }

    Item {
        id: coverBlock

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        // Keep the cover + details group optically centered
        anchors.verticalCenterOffset: detailsLoader.active ? -(detailsLoader.height + Tokens.spacing.large) / 2 : 0
        width: root.coverSpan + root.ringHeadroom * 2
        height: width

        Behavior on anchors.verticalCenterOffset {
            Anim {
                type: Anim.DefaultSpatial
            }
        }

        Loader {
            anchors.fill: parent
            active: root.mediaConfig.showVisualiser
            asynchronous: true

            sourceComponent: CoverRing {
                cover: cover
            }
        }

        CoverArt {
            id: cover

            anchors.centerIn: parent
            width: root.coverSpan
            height: root.coverSpan
            source: root.artUrl
            spin: root.mediaConfig.spinCover
        }
    }

    Loader {
        id: detailsLoader

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: coverBlock.bottom
        anchors.topMargin: Tokens.spacing.large
        active: root.mediaConfig.showDetails
        asynchronous: true

        sourceComponent: Column {
            spacing: Tokens.spacing.small

            Timer {
                running: root.playing
                interval: GlobalConfig.dashboard.mediaUpdateInterval
                triggeredOnStart: true
                repeat: true
                onTriggered: Players.active?.positionChanged()
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(root.width * 0.8, root.coverSpan * 1.6)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                animate: true
                text: Players.active?.trackTitle ?? ""
                color: Colours.palette.m3onSurface
                font: Tokens.font.title.builders.large.scale(1.5).weight(Font.Bold).build()
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(root.width * 0.8, root.coverSpan * 1.6)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                animate: true
                visible: text.length > 0
                text: Players.active?.trackArtist ?? ""
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.title.builders.medium.scale(1.2).build()
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Tokens.spacing.small

                TextMetrics {
                    id: timeMetrics

                    text: Players.active ? root.lengthStr(Math.max(Players.active.position, Players.active.length)).replace(/[1-9]/g, "0") : "00:00"
                    font: Tokens.font.label.large
                }

                StyledText {
                    id: positionLabel

                    anchors.verticalCenter: parent.verticalCenter
                    width: timeMetrics.width
                    text: root.lengthStr(Players.active?.position ?? -1)
                    color: Colours.palette.m3onSurfaceVariant
                    font: timeMetrics.font
                    horizontalAlignment: Text.AlignHCenter
                }

                StyledSlider {
                    id: positionSlider

                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: root.coverSpan * 0.7
                    implicitHeight: 16
                    value: Players.active ? Players.active.position / (Players.active.length || 1) : 0
                    enabled: Players.active?.canSeek ?? false
                    wavy: true
                    animateWave: root.playing
                    waveFrequency: 5
                    waveDuration: 2000
                    interactionOnMove: false
                    onInteraction: value => {
                        const active = Players.active;
                        if (active?.canSeek && active?.positionSupported)
                            active.position = value * active.length;
                    }

                    Binding {
                        target: positionLabel
                        property: "text"
                        value: root.lengthStr(positionSlider.pos * (Players.active?.length ?? 0))
                        when: positionSlider.dragging
                    }
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: timeMetrics.width
                    text: root.lengthStr(Players.active?.length ?? -1)
                    color: Colours.palette.m3onSurfaceVariant
                    font: timeMetrics.font
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}
