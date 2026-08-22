pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.services
import qs.utils

ColumnLayout {
    id: root

    width: 300
    spacing: Tokens.spacing.small

    StyledText {
        Layout.topMargin: Tokens.padding.medium
        Layout.rightMargin: Tokens.padding.extraSmall
        text: qsTr("KDE Connect")
        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
    }

    StyledText {
        Layout.rightMargin: Tokens.padding.extraSmall
        text: {
            const count = KdeConnect.devices.length;
            if (count === 0)
                return KdeConnect.available ? qsTr("No paired devices") : qsTr("KDE Connect is unavailable");
            return count === 1 ? qsTr("%1 paired device").arg(count) : qsTr("%1 paired devices").arg(count);
        }
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    Repeater {
        model: KdeConnect.devices

        StyledRect {
            id: device

            required property KdeConnectDevice modelData

            Layout.fillWidth: true
            Layout.rightMargin: Tokens.padding.extraSmall
            implicitHeight: deviceRow.implicitHeight + Tokens.padding.medium * 2

            color: Colours.tPalette.m3surfaceContainer
            radius: Tokens.rounding.large

            RowLayout {
                id: deviceRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: Icons.getKdeConnectDeviceIcon(device.modelData.type)
                    color: device.modelData.reachable ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                    fill: device.modelData.reachable ? 1 : 0
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: device.modelData.name || qsTr("Unknown device")
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            if (!device.modelData.reachable)
                                return qsTr("Disconnected");
                            if (!device.modelData.batteryAvailable)
                                return qsTr("Battery unavailable");
                            return device.modelData.charging ? qsTr("Charging") : qsTr("Connected");
                        }
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                    }
                }

                MaterialIcon {
                    visible: device.modelData.reachable && device.modelData.batteryAvailable
                    text: Icons.getBatteryIcon(device.modelData.batteryPercentage / 100, device.modelData.charging)
                    color: device.modelData.batteryPercentage <= 20 && !device.modelData.charging ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    fill: 1
                }

                StyledText {
                    visible: device.modelData.reachable && device.modelData.batteryAvailable
                    text: qsTr("%1%").arg(device.modelData.batteryPercentage)
                    color: device.modelData.batteryPercentage <= 20 && !device.modelData.charging ? Colours.palette.m3error : Colours.palette.m3onSurface
                    font: Tokens.font.mono.medium
                }
            }
        }
    }
}
