/*
 * SPDX-FileCopyrightText: 2026 leonik <leonik.eut@gmail.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

MouseArea {
    id: compactRoot

    property int pingStatus: 0
    property color statusColor: Kirigami.Theme.disabledTextColor
    property bool busy: false
    property string latencyText: ""
    property string displayName: ""
    property bool showLatency: false
    property bool showLabel: false

    signal toggleExpanded()
    signal refreshRequested()

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool horizontal: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
    readonly property bool inPanel: vertical || horizontal

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    Layout.minimumWidth: vertical ? 0 : implicitWidth
    Layout.maximumWidth: vertical ? Number.POSITIVE_INFINITY : implicitWidth
    Layout.minimumHeight: horizontal ? 0 : implicitHeight
    Layout.maximumHeight: horizontal ? Number.POSITIVE_INFINITY : implicitHeight

    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    hoverEnabled: true

    onClicked: function (mouse) {
        if (mouse.button === Qt.MiddleButton) {
            compactRoot.refreshRequested()
        } else {
            compactRoot.toggleExpanded()
        }
    }

    GridLayout {
        id: content
        anchors.centerIn: parent

        // Side by side in a horizontal panel or on the desktop, stacked in a
        // vertical panel where there is no width to spare.
        flow: compactRoot.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columns: compactRoot.vertical ? 1 : 3
        rows: compactRoot.vertical ? 3 : 1
        rowSpacing: Kirigami.Units.smallSpacing
        columnSpacing: Kirigami.Units.smallSpacing

        StatusDot {
            dotColor: compactRoot.statusColor
            pulsing: compactRoot.busy

            readonly property real thickness: compactRoot.vertical
                ? compactRoot.width
                : (compactRoot.horizontal ? compactRoot.height
                                          : Math.min(compactRoot.width, compactRoot.height))

            // Leave a little breathing room against the panel edges.
            implicitWidth: Math.max(Kirigami.Units.iconSizes.small,
                                    Math.round(thickness * (compactRoot.inPanel ? 0.62 : 0.9)))
            implicitHeight: implicitWidth

            Layout.alignment: Qt.AlignCenter
        }

        PlasmaComponents.Label {
            visible: compactRoot.showLabel && compactRoot.displayName.length > 0
            text: compactRoot.displayName
            font: Kirigami.Theme.smallFont
            elide: Text.ElideRight
            maximumLineCount: 1
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignCenter
            Layout.maximumWidth: compactRoot.vertical ? compactRoot.width : implicitWidth
        }

        PlasmaComponents.Label {
            visible: compactRoot.showLatency && compactRoot.latencyText.length > 0
            text: compactRoot.latencyText
            font: Kirigami.Theme.smallFont
            elide: Text.ElideRight
            maximumLineCount: 1
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignCenter
            Layout.maximumWidth: compactRoot.vertical ? compactRoot.width : implicitWidth
        }
    }
}
