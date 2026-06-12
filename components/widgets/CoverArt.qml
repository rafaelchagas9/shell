pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import M3Shapes
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.components.images
import qs.services

Item {
    id: root

    readonly property alias shape: maskShape
    readonly property real dpr: (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1
    readonly property size layerTextureSize: Qt.size(Math.max(1, Math.ceil(width * dpr)), Math.max(1, Math.ceil(height * dpr)))

    property bool hadPrevious
    property string source: Players.getArtUrl(Players.active)
    property bool spin: true
    property color fallbackColour: Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)
    property string imageSource
    property bool imageReady

    function syncImageReady(): void {
        const canCreate = width > 0 && height > 0 && layerTextureSize.width > 1 && layerTextureSize.height > 1;

        if (!canCreate) {
            readyGateTimer.stop();
            imageReady = false;
            return;
        }

        readyGateTimer.restart();
    }

    function applyImageReady(): void {
        const stillCanCreate = width > 0 && height > 0 && layerTextureSize.width > 1 && layerTextureSize.height > 1;
        if (imageReady === stillCanCreate)
            return;

        imageReady = stillCanCreate;
        if (imageReady)
            reloadImageSource();
    }

    function reloadImageSource(): void {
        imageSource = "";
        if (source.length > 0 && imageReady)
            imageSourceTimer.restart();
    }

    onSourceChanged: reloadImageSource()
    onWidthChanged: {
        syncImageReady();
    }
    onHeightChanged: {
        syncImageReady();
    }
    Component.onCompleted: syncImageReady()

    Timer {
        id: readyGateTimer

        interval: 0
        onTriggered: root.applyImageReady()
    }

    Timer {
        id: imageSourceTimer

        interval: 0
        onTriggered: {
            if (root.imageSource.length === 0)
                root.imageSource = root.source;
        }
    }

    // Slight glow to separate from bg
    layer.enabled: true
    layer.textureSize: layerTextureSize
    layer.effect: MultiEffect {
        shadowEnabled: true
        blurMax: 1
        shadowColor: Colours.palette.m3outline
        shadowOpacity: 0.3
    }

    Behavior on fallbackColour {
        CAnim {}
    }

    MaterialShape {
        id: fallbackShape

        anchors.fill: parent
        shape: maskShape.shape
        color: Qt.alpha(root.fallbackColour, 1)
        opacity: root.fallbackColour.a
        rotation: maskShape.rotation
    }

    Item {
        id: shapeWrapper

        anchors.fill: parent
        layer.enabled: root.imageReady
        layer.textureSize: root.layerTextureSize
        visible: false

        MaterialShape {
            id: maskShape

            width: parent.width
            height: parent.height
            implicitSize: Math.min(width, height)
            shape: MaterialShape.Cookie12Sided
            color: "white"

            Anim on rotation {
                running: true
                paused: !root.spin || !Players.active?.isPlaying
                from: 360
                to: 0
                duration: 23500
                easing.type: Easing.Linear
                loops: Animation.Infinite
            }
        }
    }

    MaterialIcon {
        anchors.centerIn: parent

        grade: 200
        text: image.status === Image.Error ? "broken_image" : "art_track"
        color: Colours.palette.m3onSurfaceVariant
        fontStyle: Tokens.font.icon.size((parent.width * 0.35) || 1).build()
        opacity: image.status === Image.Null || image.status === Image.Error ? 1 : 0
        animate: true

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        anchors.centerIn: parent
        asynchronous: true
        active: opacity > 0
        opacity: image.status === Image.Loading ? 1 : 0

        sourceComponent: LoadingIndicator {
            implicitSize: root.width * 0.3
            color: Colours.palette.m3primaryContainer
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    FadeImage {
        id: image

        anchors.fill: parent

        source: root.imageReady ? root.imageSource : ""

        layer.enabled: root.imageReady
        layer.textureSize: root.layerTextureSize
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: shapeWrapper
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
    }
}
