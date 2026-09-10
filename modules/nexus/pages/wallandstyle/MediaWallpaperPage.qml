pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var cfg: Config.background.mediaWallpaper
    readonly property var gCfg: GlobalConfig.background.mediaWallpaper

    title: Tr.tr("Media wallpaper")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // General
        SectionHeader {
            first: true
            text: Tr.tr("General")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: Tr.tr("Enabled")
            subtext: Tr.tr("Show album art as wallpaper while media plays")
            checked: root.cfg.enabled
            onToggled: root.gCfg.enabled = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: Tr.tr("Lyrics")
            subtext: Tr.tr("Overlay synced lyrics on the media wallpaper")
            enabled: root.cfg.enabled
            checked: root.cfg.showLyrics
            onToggled: root.gCfg.showLyrics = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: Tr.tr("Track details")
            subtext: Tr.tr("Show title, artist and playback progress under the cover")
            enabled: root.cfg.enabled
            checked: root.cfg.showDetails
            onToggled: root.gCfg.showDetails = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: Tr.tr("Playback controls")
            subtext: Tr.tr("Show shuffle, skip, play/pause and repeat buttons")
            enabled: root.cfg.enabled
            checked: root.cfg.showControls
            onToggled: root.gCfg.showControls = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: Tr.tr("Controls on hover")
            subtext: Tr.tr("Reveal the playback controls only while hovering")
            enabled: root.cfg.enabled && root.cfg.showControls
            checked: root.cfg.controlsOnHover
            onToggled: root.gCfg.controlsOnHover = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: Tr.tr("Spin cover")
            subtext: Tr.tr("Slowly rotate the cover shape while playing")
            enabled: root.cfg.enabled
            checked: root.cfg.spinCover
            onToggled: root.gCfg.spinCover = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            last: true
            text: Tr.tr("Visualiser ring")
            subtext: Tr.tr("Audio visualiser around the cover")
            enabled: root.cfg.enabled
            checked: root.cfg.showVisualiser
            onToggled: root.gCfg.showVisualiser = checked
        }

        // Appearance
        SectionHeader {
            text: Tr.tr("Appearance")
        }

        SliderRow {
            Layout.fillWidth: true
            first: true
            icon: "fit_screen"
            label: Tr.tr("Cover size")
            valueLabel: Tr.tr("%1%").arg(Math.round(root.cfg.coverSize * 100))
            enabled: root.cfg.enabled
            value: root.cfg.coverSize
            onMoved: value => root.gCfg.coverSize = value
        }

        SliderRow {
            Layout.fillWidth: true
            last: true
            icon: "opacity"
            label: Tr.tr("Backdrop dimming")
            valueLabel: Tr.tr("%1%").arg(Math.round(root.cfg.scrimOpacity * 100))
            enabled: root.cfg.enabled
            value: root.cfg.scrimOpacity
            onMoved: value => root.gCfg.scrimOpacity = value
        }

        // Behaviour
        SectionHeader {
            text: Tr.tr("Behaviour")
        }

        StepperRow {
            Layout.fillWidth: true
            first: true
            label: Tr.tr("Track change debounce (ms)")
            subtext: Tr.tr("Wait before switching art on rapid track changes")
            from: 0
            to: 2000
            stepSize: 50
            value: root.cfg.trackDebounceMs
            onMoved: value => root.gCfg.trackDebounceMs = value
        }

        StepperRow {
            Layout.fillWidth: true
            last: true
            label: Tr.tr("Restore wallpaper after pause (s)")
            subtext: Tr.tr("Return to the static wallpaper when paused this long")
            from: 0
            to: 600
            stepSize: 5
            value: Math.round(root.cfg.pauseRestoreDelayMs / 1000)
            onMoved: value => root.gCfg.pauseRestoreDelayMs = value * 1000
        }
    }
}
