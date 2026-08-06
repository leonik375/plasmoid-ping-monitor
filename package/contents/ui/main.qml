/*
 * SPDX-FileCopyrightText: 2026 leonik <leonik.eut@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami
import org.kde.notification

PlasmoidItem {
    id: root

    // Status values reported by the widget.
    readonly property int statusUnknown: 0
    readonly property int statusUp: 1
    readonly property int statusDown: 2
    readonly property int statusError: 3

    property int pingStatus: statusUnknown
    property real latency: -1       // milliseconds, -1 when not measured
    property real packetLoss: -1    // percent, -1 when not measured
    property string detail: ""      // human readable explanation, may be empty
    property double lastCheck: 0    // epoch ms, 0 means never checked
    property bool busy: false

    readonly property string host: (Plasmoid.configuration.host || "").trim()
    readonly property string displayName: Plasmoid.configuration.label.trim().length > 0
        ? Plasmoid.configuration.label.trim()
        : host

    // Everything a host name, IPv4 or IPv6 literal may contain, and nothing the
    // shell would treat as syntax. The command below single quotes the host, so
    // rejecting quotes here is what keeps the interpolation safe.
    readonly property bool hostValid: host.length > 0 && /^[A-Za-z0-9._:%\[\]-]+$/.test(host)

    readonly property color statusColor: {
        switch (pingStatus) {
        case statusUp: return Kirigami.Theme.positiveTextColor
        case statusDown: return Kirigami.Theme.negativeTextColor
        case statusError: return Kirigami.Theme.neutralTextColor
        default: return Kirigami.Theme.disabledTextColor
        }
    }

    readonly property string statusText: {
        if (!hostValid) {
            return host.length === 0 ? i18n("No host configured") : i18n("Invalid host")
        }
        switch (pingStatus) {
        case statusUp: return i18n("Available")
        case statusDown: return i18n("Unavailable")
        case statusError: return i18n("Error")
        default: return i18n("Not checked yet")
        }
    }

    readonly property string latencyText: latency >= 0
        ? (latency >= 100 ? Math.round(latency) + " ms" : latency.toFixed(1) + " ms")
        : ""

    Plasmoid.icon: "network-connect"
    Plasmoid.status: (pingStatus === statusDown || pingStatus === statusError)
                     && Plasmoid.configuration.attentionWhenDown
        ? PlasmaCore.Types.NeedsAttentionStatus
        : PlasmaCore.Types.ActiveStatus

    toolTipMainText: displayName.length > 0 ? displayName : i18n("Ping Monitor")
    toolTipSubText: {
        const lines = [statusText]
        if (latencyText.length > 0) {
            lines.push(i18n("Round trip time: %1", latencyText))
        }
        if (detail.length > 0) {
            lines.push(detail)
        }
        if (lastCheck > 0) {
            lines.push(i18n("Last check: %1", Qt.formatTime(new Date(lastCheck), "hh:mm:ss")))
        }
        return lines.join("\n")
    }

    preferredRepresentation: compactRepresentation

    // Newest entry last. Each row is { ok: bool, latency: real, time: double }.
    ListModel {
        id: historyModel
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            disconnectSource(source)
            root.handleResult(data["exit code"], data["stdout"] || "", data["stderr"] || "")
        }
    }

    Notification {
        id: statusNotification
        componentName: "plasma_workspace"
        eventId: "notification"
        urgency: Notification.NormalUrgency
    }

    Timer {
        id: pollTimer
        interval: Math.max(5, Plasmoid.configuration.interval) * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.checkNow()
    }

    // ping is given a hard deadline, but a wedged process would still leave the
    // widget stuck on "checking" forever, so cut it loose after a grace period.
    Timer {
        id: watchdog
        interval: (Math.max(1, Plasmoid.configuration.timeout)
                   + Math.max(1, Plasmoid.configuration.count) + 5) * 1000
        onTriggered: {
            executable.connectedSources = []
            root.busy = false
            root.applyResult(root.statusError, -1, -1, i18n("Timed out waiting for ping"))
        }
    }

    onHostChanged: resetAndCheck()

    function resetAndCheck() {
        historyModel.clear()
        pingStatus = statusUnknown
        latency = -1
        packetLoss = -1
        detail = ""
        lastCheck = 0
        pollTimer.restart()
    }

    function buildCommand() {
        const cfg = Plasmoid.configuration
        const count = Math.max(1, cfg.count)
        const timeout = Math.max(1, cfg.timeout)
        const family = cfg.addressFamily === 1 ? " -4" : (cfg.addressFamily === 2 ? " -6" : "")
        // -w bounds the whole run; ping paces packets one second apart.
        const deadline = timeout + count
        return "LC_ALL=C ping -n" + family
             + " -c " + count
             + " -W " + timeout
             + " -w " + deadline
             + " -- '" + host + "'"
    }

    function checkNow() {
        if (!hostValid) {
            applyResult(statusError, -1, -1,
                        host.length === 0
                            ? i18n("Set a host to ping in the widget settings")
                            : i18n("The host contains characters that are not allowed"))
            return
        }
        if (busy) {
            return
        }
        busy = true
        watchdog.restart()
        executable.connectSource(buildCommand())
    }

    function handleResult(exitCode, stdout, stderr) {
        watchdog.stop()
        busy = false

        const out = stdout + "\n" + stderr
        const summary = out.match(/=\s*([0-9.]+)\/([0-9.]+)\/([0-9.]+)\/([0-9.]+)\s*ms/)
        const single = out.match(/time[=<]\s*([0-9.]+)\s*ms/)
        const rtt = summary ? parseFloat(summary[2]) : (single ? parseFloat(single[1]) : -1)

        const lossMatch = out.match(/([0-9.]+)% packet loss/)
        const loss = lossMatch ? parseFloat(lossMatch[1]) : -1

        if (exitCode === 0) {
            // With more than one packet ping still succeeds on partial loss.
            const note = loss > 0 ? i18n("%1% packet loss", Math.round(loss)) : ""
            applyResult(statusUp, rtt, loss, note)
        } else if (exitCode === 1) {
            applyResult(statusDown, -1, loss >= 0 ? loss : 100, i18n("No reply from host"))
        } else {
            applyResult(statusError, -1, -1,
                        firstLine(stderr) || firstLine(stdout)
                        || i18n("ping exited with code %1", exitCode))
        }
    }

    function firstLine(text) {
        const lines = (text || "").split("\n")
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i].trim().replace(/^ping:\s*/i, "")
            if (line.length > 0) {
                return line
            }
        }
        return ""
    }

    function applyResult(newStatus, newLatency, newLoss, newDetail) {
        const previous = pingStatus
        const now = Date.now()

        pingStatus = newStatus
        latency = newLatency
        packetLoss = newLoss
        detail = newDetail
        lastCheck = now

        historyModel.append({ ok: newStatus === statusUp, latency: newLatency, time: now })
        const limit = Math.max(5, Plasmoid.configuration.historySize)
        while (historyModel.count > limit) {
            historyModel.remove(0)
        }

        maybeNotify(previous, newStatus)
    }

    function maybeNotify(previous, current) {
        if (!Plasmoid.configuration.notifyOnChange) {
            return
        }
        // Only announce real transitions, never the first result after startup.
        if (previous === statusUnknown || previous === current) {
            return
        }
        const wasReachable = previous === statusUp
        const isReachable = current === statusUp
        if (wasReachable === isReachable) {
            return
        }

        statusNotification.title = displayName
        statusNotification.iconName = isReachable ? "network-connect" : "network-disconnect"
        statusNotification.urgency = isReachable ? Notification.NormalUrgency
                                                 : Notification.HighUrgency
        statusNotification.text = isReachable
            ? (latencyText.length > 0 ? i18n("Host is available again (%1)", latencyText)
                                      : i18n("Host is available again"))
            : (detail.length > 0 ? i18n("Host is unavailable: %1", detail)
                                 : i18n("Host is unavailable"))
        statusNotification.sendEvent()
    }

    compactRepresentation: CompactRepresentation {
        pingStatus: root.pingStatus
        statusColor: root.statusColor
        busy: root.busy
        latencyText: root.latencyText
        displayName: root.displayName
        showLatency: Plasmoid.configuration.showLatency
        showLabel: Plasmoid.configuration.showLabel
        onToggleExpanded: root.expanded = !root.expanded
        onRefreshRequested: root.checkNow()
    }

    fullRepresentation: FullRepresentation {
        displayName: root.displayName
        host: root.host
        statusText: root.statusText
        statusColor: root.statusColor
        pingStatus: root.pingStatus
        upValue: root.statusUp
        latencyText: root.latencyText
        packetLoss: root.packetLoss
        detail: root.detail
        lastCheck: root.lastCheck
        busy: root.busy
        history: historyModel
        interval: Math.max(5, Plasmoid.configuration.interval)
        onRefreshRequested: root.checkNow()
        onConfigureRequested: Plasmoid.internalAction("configure").trigger()
    }
}
