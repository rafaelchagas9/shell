pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.components.images
import qs.services

CachingImage {
    id: root

    required property string wallpaperSource
    required property var wallpaperRoot

    function update(): void {
        if (path === wallpaperSource)
            wallpaperRoot.current = root;
        else
            path = wallpaperSource;
    }

    anchors.fill: parent
    fillMode: Image.PreserveAspectCrop

    opacity: 0
    scale: Wallpapers.showPreview ? 1 : 0.8

    onStatusChanged: {
        if (status === Image.Ready)
            wallpaperRoot.current = root;
    }

    states: State {
        name: "visible"
        when: wallpaperRoot.current === root

        PropertyChanges {
            root.opacity: 1
            root.scale: 1
        }
    }

    transitions: Transition {
        Anim {
            target: root
            properties: "opacity,scale"
        }
    }
}
