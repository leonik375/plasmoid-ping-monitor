/*
 * SPDX-FileCopyrightText: 2026 leonik <leonik.eut@gmail.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

PlasmaExtras.Representation {
    id: full

    property string displayName: ""
    property string host: ""
    property string statusText: ""
    property color statusColor: Kirigami.Theme.disabledTextColor
    property int pingStatus: 0
    property int upValue: 1
    property string latencyText: ""
    property real packetLoss: -1
    property string detail: ""
    property double lastCheck: 0
    property bool busy: false
    property string backendName: ""
    property var history: null
    property int interval: 30
    property int historySize: 30

    signal refreshRequested()
    signal configureRequested()

    // Rescaled on every result so the sparkline always fills its box.
    property real maxLatency: 1
    onLastCheckChanged: recomputeMaxLatency()

    function recomputeMaxLatency() {
        let peak = 1
        if (history) {
            for (let i = 0; i < history.count; ++i) {
                const value = history.get(i).latency
                if (value > peak) {
                    peak = value
                }
            }
        }
        maxLatency = peak
    }

    Layout.minimumWidth: Kirigami.Units.gridUnit * 17
    Layout.minimumHeight: Kirigami.Units.gridUnit * 16
    Layout.preferredWidth: Layout.minimumWidth
    Layout.preferredHeight: Layout.minimumHeight

    collapseMarginsHint: true

    header: PlasmaExtras.PlasmoidHeading {
        RowLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            StatusDot {
                dotColor: full.statusColor
                pulsing: full.busy
                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                implicitHeight: Kirigami.Units.iconSizes.smallMedium
            }

            PlasmaExtras.Heading {
                level: 4
                text: full.displayName.length > 0 ? full.displayName : i18n("Ping Monitor")
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            PlasmaComponents.ToolButton {
                icon.name: "view-refresh"
                display: PlasmaComponents.AbstractButton.IconOnly
                text: i18n("Check now")
                enabled: !full.busy
                onClicked: full.refreshRequested()

                PlasmaComponents.ToolTip.text: text
                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

            PlasmaComponents.ToolButton {
                icon.name: "configure"
                display: PlasmaComponents.AbstractButton.IconOnly
                text: i18n("Configure…")
                onClicked: full.configureRequested()

                PlasmaComponents.ToolTip.text: text
                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        PlasmaExtras.Heading {
            level: 2
            text: full.statusText
            color: full.statusColor
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.topMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
        }

        GridLayout {
            columns: 2
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.smallSpacing
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                text: i18n("Host:")
                opacity: 0.75
                Layout.alignment: Qt.AlignRight | Qt.AlignTop
            }
            PlasmaComponents.Label {
                text: full.host.length > 0 ? full.host : i18n("not set")
                wrapMode: Text.WrapAnywhere
                Layout.fillWidth: true
            }

            PlasmaComponents.Label {
                visible: full.latencyText.length > 0
                text: i18n("Round trip:")
                opacity: 0.75
                Layout.alignment: Qt.AlignRight
            }
            PlasmaComponents.Label {
                visible: full.latencyText.length > 0
                text: full.latencyText
                Layout.fillWidth: true
            }

            PlasmaComponents.Label {
                visible: full.packetLoss >= 0
                text: i18n("Packet loss:")
                opacity: 0.75
                Layout.alignment: Qt.AlignRight
            }
            PlasmaComponents.Label {
                visible: full.packetLoss >= 0
                text: i18n("%1%", Math.round(full.packetLoss))
                Layout.fillWidth: true
            }

            PlasmaComponents.Label {
                visible: full.lastCheck > 0
                text: i18n("Last check:")
                opacity: 0.75
                Layout.alignment: Qt.AlignRight
            }
            PlasmaComponents.Label {
                visible: full.lastCheck > 0
                text: Qt.formatTime(new Date(full.lastCheck), "hh:mm:ss")
                Layout.fillWidth: true
            }

            PlasmaComponents.Label {
                visible: full.detail.length > 0
                text: i18n("Details:")
                opacity: 0.75
                Layout.alignment: Qt.AlignRight | Qt.AlignTop
            }
            PlasmaComponents.Label {
                visible: full.detail.length > 0
                text: full.detail
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            PlasmaComponents.Label {
                visible: full.backendName.length > 0
                text: i18n("Measured by:")
                opacity: 0.75
                Layout.alignment: Qt.AlignRight
            }
            PlasmaComponents.Label {
                visible: full.backendName.length > 0
                text: full.backendName
                opacity: 0.75
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        Item { Layout.fillHeight: true }

        PlasmaComponents.Label {
            text: i18np("History, one bar per check every second",
                        "History, one bar per check every %1 seconds", full.interval)
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
        }

        Item {
            id: sparkline
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing

            // A bar is sized for a full history rather than for what has been
            // collected so far, so it keeps its width from the very first check
            // instead of the strip being redrawn wider each time.
            readonly property int capacity: Math.max(1, full.historySize)
            readonly property real gap: (width / capacity) > 3 ? 1 : 0
            readonly property real barWidth: Math.max(1, width / capacity - gap)

            // The strip a full history would occupy, so a partly filled one
            // reads as room left to fill rather than as a gap.
            Rectangle {
                anchors.fill: parent
                radius: Kirigami.Units.cornerRadius
                color: Kirigami.Theme.textColor
                opacity: 0.07
            }

            PlasmaComponents.Label {
                anchors.centerIn: parent
                visible: !full.history || full.history.count === 0
                text: i18n("No checks recorded yet")
                font: Kirigami.Theme.smallFont
                opacity: 0.6
            }

            // Anchored right, so the newest check keeps the right hand edge and
            // history grows away to the left as it accumulates.
            Row {
                id: bars
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: sparkline.gap

                Repeater {
                    model: full.history

                    // Oldest on the left, newest on the right.
                    Rectangle {
                        width: sparkline.barWidth
                        // Clamped on both ends: a failed check is a full bar, a
                        // very fast one still has to be visible, and a stale
                        // peak can never scale a bar past the top.
                        height: bars.height * (model.ok
                            ? Math.max(0.12, Math.min(1.0,
                                  model.latency > 0 ? model.latency / full.maxLatency : 0.12))
                            : 1.0)
                        y: bars.height - height
                        radius: Math.min(width, height) / 4
                        color: model.ok ? Kirigami.Theme.positiveTextColor
                                        : Kirigami.Theme.negativeTextColor
                        opacity: model.ok ? 0.85 : 0.6
                    }
                }
            }
        }
    }
}
