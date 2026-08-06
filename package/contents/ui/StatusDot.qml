/*
 * SPDX-FileCopyrightText: 2026 leonik <leonik.eut@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: dot

    property color dotColor: Kirigami.Theme.disabledTextColor
    property bool pulsing: false

    implicitWidth: Kirigami.Units.iconSizes.small
    implicitHeight: Kirigami.Units.iconSizes.small

    readonly property real diameter: Math.min(width, height)

    // A translucent ring keeps the dot legible on both light and dark panels.
    Rectangle {
        id: ring
        anchors.centerIn: parent
        width: dot.diameter
        height: dot.diameter
        radius: width / 2
        color: "transparent"
        border.width: Math.max(1, Math.round(width * 0.09))
        border.color: Qt.rgba(dot.dotColor.r, dot.dotColor.g, dot.dotColor.b, 0.35)
    }

    Rectangle {
        id: core
        anchors.centerIn: parent
        width: ring.width * 0.62
        height: width
        radius: width / 2
        color: dot.dotColor

        SequentialAnimation on opacity {
            running: dot.pulsing
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
            onStopped: core.opacity = 1.0
        }
    }
}
