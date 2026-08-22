pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Services
import qs.components
import qs.services
import qs.utils

ColumnLayout {
    id: root

    required property color colour

    spacing: Tokens.spacing.medium / 2

    Repeater {
        model: KdeConnect.devices

        Item {
            id: device

            required property KdeConnectDevice modelData

            Layout.alignment: Qt.AlignHCenter
            implicitWidth: icon.implicitWidth
            implicitHeight: visible ? icon.implicitHeight : 0
            visible: modelData.reachable && modelData.batteryAvailable

            MaterialIcon {
                id: icon

                anchors.centerIn: parent

                animate: true
                text: Icons.getKdeConnectDeviceIcon(device.modelData.type)
                color: device.modelData.batteryPercentage <= 20 && !device.modelData.charging ? Colours.palette.m3error : root.colour
                fill: 1
            }
        }
    }
}
