pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var cfg: Config.background.mediaWallpaper
    readonly property var gCfg: GlobalConfig.background.mediaWallpaper

    title: qsTr("Media wallpaper")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // General
        SectionHeader {
            first: true
            text: qsTr("General")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Enabled")
            subtext: qsTr("Show album art as wallpaper while media plays")
            checked: root.cfg.enabled
            onToggled: root.gCfg.enabled = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Lyrics")
            subtext: qsTr("Overlay synced lyrics on the media wallpaper")
            enabled: root.cfg.enabled
            checked: root.cfg.showLyrics
            onToggled: root.gCfg.showLyrics = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Track details")
            subtext: qsTr("Show title, artist and playback progress under the cover")
            enabled: root.cfg.enabled
            checked: root.cfg.showDetails
            onToggled: root.gCfg.showDetails = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Spin cover")
            subtext: qsTr("Slowly rotate the cover shape while playing")
            enabled: root.cfg.enabled
            checked: root.cfg.spinCover
            onToggled: root.gCfg.spinCover = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            last: true
            text: qsTr("Visualiser ring")
            subtext: qsTr("Audio visualiser around the cover")
            enabled: root.cfg.enabled
            checked: root.cfg.showVisualiser
            onToggled: root.gCfg.showVisualiser = checked
        }

        // Appearance
        SectionHeader {
            text: qsTr("Appearance")
        }

        SliderRow {
            Layout.fillWidth: true
            first: true
            icon: "fit_screen"
            label: qsTr("Cover size")
            valueLabel: qsTr("%1%").arg(Math.round(root.cfg.coverSize * 100))
            enabled: root.cfg.enabled
            value: root.cfg.coverSize
            onMoved: value => root.gCfg.coverSize = value
        }

        SliderRow {
            Layout.fillWidth: true
            last: true
            icon: "opacity"
            label: qsTr("Backdrop dimming")
            valueLabel: qsTr("%1%").arg(Math.round(root.cfg.scrimOpacity * 100))
            enabled: root.cfg.enabled
            value: root.cfg.scrimOpacity
            onMoved: value => root.gCfg.scrimOpacity = value
        }

        // Behaviour
        SectionHeader {
            text: qsTr("Behaviour")
        }

        StepperRow {
            Layout.fillWidth: true
            first: true
            label: qsTr("Track change debounce (ms)")
            subtext: qsTr("Wait before switching art on rapid track changes")
            from: 0
            to: 2000
            stepSize: 50
            value: root.cfg.trackDebounceMs
            onMoved: value => root.gCfg.trackDebounceMs = value
        }

        StepperRow {
            Layout.fillWidth: true
            last: true
            label: qsTr("Restore wallpaper after pause (s)")
            subtext: qsTr("Return to the static wallpaper when paused this long")
            from: 0
            to: 600
            stepSize: 5
            value: Math.round(root.cfg.pauseRestoreDelayMs / 1000)
            onMoved: value => root.gCfg.pauseRestoreDelayMs = value * 1000
        }
    }
}
