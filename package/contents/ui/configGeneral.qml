/*
 * SPDX-FileCopyrightText: 2026 leonik <leonik.eut@gmail.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property alias cfg_host: hostField.text
    property alias cfg_label: labelField.text
    property alias cfg_interval: intervalBox.value
    property alias cfg_timeout: timeoutBox.value
    property alias cfg_count: countBox.value
    property int cfg_addressFamily
    property alias cfg_showLatency: showLatencyBox.checked
    property alias cfg_showLabel: showLabelBox.checked
    property alias cfg_notifyOnChange: notifyBox.checked
    property alias cfg_attentionWhenDown: attentionBox.checked
    property alias cfg_historySize: historyBox.value

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        QQC2.TextField {
            id: hostField
            Kirigami.FormData.label: i18n("Host:")
            placeholderText: i18n("Host name or IP address")
            // Mirrors the validation in main.qml, which single quotes the value
            // before handing it to the shell.
            validator: RegularExpressionValidator {
                regularExpression: /[A-Za-z0-9._:%\[\]-]*/
            }
        }

        QQC2.Label {
            text: i18n("For example 192.168.1.1, gateway.local or 2606:4700:4700::1111")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.Wrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        }

        QQC2.TextField {
            id: labelField
            Kirigami.FormData.label: i18n("Display name:")
            placeholderText: i18n("Optional, defaults to the host")
        }

        QQC2.ComboBox {
            id: familyBox
            Kirigami.FormData.label: i18n("IP version:")
            model: [i18n("Automatic"), i18n("IPv4 only"), i18n("IPv6 only")]
            currentIndex: page.cfg_addressFamily
            onActivated: page.cfg_addressFamily = currentIndex
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.SpinBox {
            id: intervalBox
            Kirigami.FormData.label: i18n("Check every:")
            from: 5
            to: 3600
            stepSize: 5
            textFromValue: (value) => i18np("%1 second", "%1 seconds", value)
            valueFromText: (text) => parseInt(text, 10) || from
        }

        QQC2.SpinBox {
            id: timeoutBox
            Kirigami.FormData.label: i18n("Wait for reply:")
            from: 1
            to: 60
            textFromValue: (value) => i18np("%1 second", "%1 seconds", value)
            valueFromText: (text) => parseInt(text, 10) || from
        }

        QQC2.SpinBox {
            id: countBox
            Kirigami.FormData.label: i18n("Packets per check:")
            from: 1
            to: 10
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: showLabelBox
            Kirigami.FormData.label: i18n("In the panel:")
            text: i18n("Show the name next to the dot")
        }

        QQC2.CheckBox {
            id: showLatencyBox
            text: i18n("Show the round trip time next to the dot")
        }

        QQC2.CheckBox {
            id: attentionBox
            text: i18n("Highlight the widget while the host is unreachable")
        }

        QQC2.CheckBox {
            id: notifyBox
            Kirigami.FormData.label: i18n("Notifications:")
            text: i18n("Notify when availability changes")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.SpinBox {
            id: historyBox
            Kirigami.FormData.label: i18n("History length:")
            from: 5
            to: 120
            stepSize: 5
            textFromValue: (value) => i18np("%1 check", "%1 checks", value)
            valueFromText: (text) => parseInt(text, 10) || from
        }
    }
}
