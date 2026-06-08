pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.containers
import qs.services

Variants {
    model: Screens.screens.filter(s => GlobalConfig.forScreen(s.name).background.enabled)

    StyledWindow {
        id: win

        required property ShellScreen modelData
        readonly property bool hasBackgroundSurface: contentItem.Config.background.wallpaperEnabled || contentItem.Config.background.mediaWallpaper.enabled

        screen: modelData
        name: "background"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: hasBackgroundSurface ? WlrLayer.Background : WlrLayer.Bottom
        color: contentItem.Config.background.wallpaperEnabled ? "black" : "transparent"
        surfaceFormat.opaque: false

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        Item {
            id: behindClock

            anchors.fill: parent

            Loader {
                id: wallpaper

                asynchronous: true

                anchors.fill: parent
                active: win.hasBackgroundSurface

                sourceComponent: Wallpaper {}
            }

            Visualiser {
                anchors.fill: parent
                screen: win.modelData
                wallpaper: wallpaper
            }

            Item {
                id: mediaLyricsOverlay

                readonly property int lyricCount: Lyrics.lyrics.length
                readonly property int lyricIndex: Lyrics.indexForTime(Players.active?.position ?? 0)
                readonly property int displayLyricIndex: lyricIndex < 0 ? -1 : findNonEmptyIndex(lyricIndex, -1)
                readonly property int previousLyricIndex: previousNonEmptyIndex(displayedLyricIndex)
                readonly property int nextLyricIndex: nextNonEmptyIndex(displayedLyricIndex)
                readonly property int beforePreviousLyricIndex: previousNonEmptyIndex(previousLyricIndex)
                readonly property int afterNextLyricIndex: nextNonEmptyIndex(nextLyricIndex)
                readonly property string beforePreviousLyricLine: lyricLineAt(beforePreviousLyricIndex)
                readonly property string previousLyricLine: lyricLineAt(previousLyricIndex)
                readonly property string currentLyricLine: lyricLineAt(displayedLyricIndex)
                readonly property string nextLyricLine: lyricLineAt(nextLyricIndex)
                readonly property string afterNextLyricLine: lyricLineAt(afterNextLyricIndex)
                readonly property bool mediaModeActive: wallpaper.item?.mediaCanDisplay ?? false // qmllint disable missing-property
                readonly property bool hasLyric: {
                    // Read every dependency unconditionally: a short-circuited `&&`
                    // would stop QML from tracking the lyric-line props as deps,
                    // leaving this binding stale once Lyrics.hasLyrics flips true.
                    const svcHasLyrics = Lyrics.hasLyrics;
                    const hasCurrent = currentLyricLine.trim().length > 0;
                    const hasPrevious = previousLyricLine.trim().length > 0;
                    const hasNext = nextLyricLine.trim().length > 0;
                    return svcHasLyrics && (hasCurrent || hasPrevious || hasNext);
                }
                readonly property real lineSlotHeight: Math.max(previousLyricText.implicitHeight, currentLyricText.implicitHeight * 1.15, nextLyricText.implicitHeight) + Tokens.spacing.small

                property int displayedLyricIndex: -1
                property int pendingLyricIndex: -1
                property real stackOffset: -lineSlotHeight

                function lyricLineAt(idx: int): string {
                    if (idx < 0 || idx >= lyricCount)
                        return "";

                    return String(Lyrics.lyrics[idx] ?? "").trim();
                }

                function findNonEmptyIndex(startIndex: int, step: int): int {
                    if (step === 0 || lyricCount === 0)
                        return -1;

                    let idx = startIndex;

                    while (idx >= 0 && idx < lyricCount) {
                        if (lyricLineAt(idx).length > 0)
                            return idx;
                        idx += step;
                    }

                    return -1;
                }

                function previousNonEmptyIndex(idx: int): int {
                    return findNonEmptyIndex(idx - 1, -1);
                }

                function nextNonEmptyIndex(idx: int): int {
                    return findNonEmptyIndex(idx + 1, 1);
                }

                function syncDisplayedLyricIndex(): void {
                    if (displayLyricIndex < 0) {
                        displayedLyricIndex = -1;
                        pendingLyricIndex = -1;
                        stackOffset = -lineSlotHeight;
                        slideAnimation.stop();
                        return;
                    }

                    if (displayedLyricIndex < 0) {
                        displayedLyricIndex = displayLyricIndex;
                        stackOffset = -lineSlotHeight;
                        return;
                    }

                    if (slideAnimation.running) {
                        pendingLyricIndex = displayLyricIndex;
                        return;
                    }

                    if (displayLyricIndex === displayedLyricIndex)
                        return;

                    const animatedNextIndex = nextNonEmptyIndex(displayedLyricIndex);
                    const animatedPreviousIndex = previousNonEmptyIndex(displayedLyricIndex);

                    if (displayLyricIndex === animatedNextIndex) {
                        displayedLyricIndex = displayLyricIndex;
                        stackOffset = 0;
                        slideAnimation.to = -lineSlotHeight;
                        slideAnimation.restart();
                        return;
                    }

                    if (displayLyricIndex === animatedPreviousIndex) {
                        displayedLyricIndex = displayLyricIndex;
                        stackOffset = -lineSlotHeight * 2;
                        slideAnimation.to = -lineSlotHeight;
                        slideAnimation.restart();
                        return;
                    }

                    displayedLyricIndex = displayLyricIndex;
                    stackOffset = -lineSlotHeight;
                }

                onDisplayLyricIndexChanged: syncDisplayedLyricIndex()

                onLineSlotHeightChanged: {
                    if (!slideAnimation.running)
                        stackOffset = -lineSlotHeight;
                }

                Component.onCompleted: syncDisplayedLyricIndex()

                anchors.fill: parent
                visible: mediaModeActive && Config.background.mediaWallpaper.showLyrics && hasLyric

                // Forces MprisPlayer.position to refresh so indexForTime advances.
                // Must NOT be gated on `visible`: the overlay only becomes visible
                // once a non-empty lyric line is reached, which itself needs the
                // position to advance — gating on visible would deadlock on intros.
                Timer {
                    running: mediaLyricsOverlay.mediaModeActive && Config.background.mediaWallpaper.showLyrics && (Players.active?.isPlaying ?? false)
                    interval: GlobalConfig.dashboard.mediaUpdateInterval
                    repeat: true
                    onTriggered: Players.active?.positionChanged()
                }

                Item {
                    id: lyricPlate

                    readonly property real plateRadius: Tokens.rounding.large

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Math.max(Tokens.padding.large * 2, parent.height * 0.06)
                    width: Math.min(parent.width * 0.82, 1200)
                    height: lyricViewport.height + Tokens.padding.large * 2

                    // Material elevation: a rounded surface behind the frosted
                    // glass, layered so MultiEffect casts a soft drop shadow.
                    Rectangle {
                        anchors.fill: parent
                        radius: lyricPlate.plateRadius
                        color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.5)

                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: Qt.alpha(Colours.palette.m3shadow, 0.5)
                            shadowBlur: 1
                            shadowVerticalOffset: 4
                        }
                    }

                    // Frosted glass: capture the wallpaper region behind the plate,
                    // blur it, then lay a translucent Material surfaceContainer over
                    // it so text contrast stays consistent over any album art.
                    StyledClippingRect {
                        anchors.fill: parent
                        radius: lyricPlate.plateRadius
                        color: "transparent"

                        ShaderEffectSource {
                            id: plateFrostSource

                            anchors.fill: parent
                            sourceItem: wallpaper
                            sourceRect: Qt.rect(lyricPlate.x, lyricPlate.y, lyricPlate.width, lyricPlate.height)
                            live: true
                            recursive: false
                            hideSource: false
                            // Left visible (not culled) so its FBO keeps updating;
                            // the opaque blurred MultiEffect + scrim cover it fully.
                        }

                        MultiEffect {
                            anchors.fill: parent
                            source: plateFrostSource
                            blurEnabled: true
                            blur: 1
                            blurMax: 48
                            saturation: -0.1
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.58)
                        }
                    }

                    // Subtle Material hairline outline.
                    Rectangle {
                        anchors.fill: parent
                        radius: lyricPlate.plateRadius
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.3)
                    }

                    Item {
                        id: lyricViewport

                        anchors.centerIn: parent
                        width: parent.width - Tokens.padding.large * 2
                        height: mediaLyricsOverlay.lineSlotHeight * 3
                        clip: true

                        Item {
                            id: lyricStack

                            x: 0
                            y: mediaLyricsOverlay.stackOffset
                            width: parent.width
                            height: mediaLyricsOverlay.lineSlotHeight * 5

                            StyledText {
                                id: beforePreviousLyricText

                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 0 + (mediaLyricsOverlay.lineSlotHeight - implicitHeight) / 2
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                text: mediaLyricsOverlay.beforePreviousLyricLine.replace(/\u00A0/g, " ")
                                color: Colours.palette.m3onSurface
                                font: Tokens.font.body.large
                                opacity: 0.56
                            }

                            StyledText {
                                id: previousLyricText

                                anchors.horizontalCenter: parent.horizontalCenter
                                y: mediaLyricsOverlay.lineSlotHeight + (mediaLyricsOverlay.lineSlotHeight - implicitHeight) / 2
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                text: mediaLyricsOverlay.previousLyricLine.replace(/\u00A0/g, " ")
                                color: Colours.palette.m3onSurface
                                font: Tokens.font.body.large
                                opacity: 0.72
                            }

                            StyledText {
                                id: currentLyricText

                                anchors.horizontalCenter: parent.horizontalCenter
                                y: mediaLyricsOverlay.lineSlotHeight * 2 + (mediaLyricsOverlay.lineSlotHeight - implicitHeight) / 2
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                text: mediaLyricsOverlay.currentLyricLine.replace(/\u00A0/g, " ")
                                color: Colours.palette.m3primary
                                font: Tokens.font.body.builders.large.weight(Font.Bold).build()
                                scale: mediaLyricsOverlay.currentLyricLine.length > 0 ? 1.15 : 1.0

                                Behavior on scale {
                                    Anim {
                                        type: Anim.StandardSmall
                                    }
                                }
                            }

                            StyledText {
                                id: nextLyricText

                                anchors.horizontalCenter: parent.horizontalCenter
                                y: mediaLyricsOverlay.lineSlotHeight * 3 + (mediaLyricsOverlay.lineSlotHeight - implicitHeight) / 2
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                text: mediaLyricsOverlay.nextLyricLine.replace(/\u00A0/g, " ")
                                color: Colours.palette.m3onSurface
                                font: Tokens.font.body.large
                                opacity: 0.72
                            }

                            StyledText {
                                id: afterNextLyricText

                                anchors.horizontalCenter: parent.horizontalCenter
                                y: mediaLyricsOverlay.lineSlotHeight * 4 + (mediaLyricsOverlay.lineSlotHeight - implicitHeight) / 2
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                text: mediaLyricsOverlay.afterNextLyricLine.replace(/\u00A0/g, " ")
                                color: Colours.palette.m3onSurface
                                font: Tokens.font.body.large
                                opacity: 0.56
                            }
                        }

                        Item {
                            id: currentLyricEffectProxy

                            x: lyricStack.x + currentLyricText.x
                            y: lyricStack.y + currentLyricText.y
                            width: currentLyricText.width
                            height: currentLyricText.height
                        }
                    }

                    Loader {
                        id: currentLyricEffectLoader

                        anchors.fill: currentLyricEffectProxy
                        active: mediaLyricsOverlay.visible && mediaLyricsOverlay.currentLyricLine.length > 0
                        asynchronous: true

                        sourceComponent: MultiEffect {
                            source: currentLyricText
                            scale: currentLyricText.scale

                            blurEnabled: true
                            blur: 0.4

                            shadowEnabled: true
                            shadowColor: Colours.palette.m3primary
                            shadowOpacity: 0.45
                            shadowBlur: 0.6
                            shadowHorizontalOffset: 0
                            shadowVerticalOffset: 0

                            autoPaddingEnabled: true
                        }
                    }

                    NumberAnimation {
                        id: slideAnimation

                        target: mediaLyricsOverlay
                        property: "stackOffset"
                        duration: Tokens.anim.durations.normal
                        easing.type: Easing.OutCubic

                        onFinished: {
                            mediaLyricsOverlay.stackOffset = -mediaLyricsOverlay.lineSlotHeight;

                            if (mediaLyricsOverlay.pendingLyricIndex >= 0 && mediaLyricsOverlay.pendingLyricIndex !== mediaLyricsOverlay.displayedLyricIndex) {
                                mediaLyricsOverlay.pendingLyricIndex = -1;
                                Qt.callLater(() => mediaLyricsOverlay.syncDisplayedLyricIndex());
                            } else {
                                mediaLyricsOverlay.pendingLyricIndex = -1;
                            }
                        }
                    }
                }
            }
        }

        Loader {
            id: clockLoader

            asynchronous: true
            active: Config.background.desktopClock.enabled

            anchors.margins: Tokens.padding.extraLargeIncreased
            anchors.leftMargin: Tokens.padding.extraLargeIncreased + Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness)

            state: Config.background.desktopClock.position
            states: [
                State {
                    name: "top-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "top-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "top-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "middle-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "middle-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "middle-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "bottom-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "bottom-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "bottom-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                    }
                }
            ]

            transitions: Transition {
                AnchorAnim {}
            }

            sourceComponent: DesktopClock {
                wallpaper: behindClock
                absX: clockLoader.x
                absY: clockLoader.y
            }
        }
    }
}
