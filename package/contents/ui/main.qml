/*
 * SPDX-FileCopyrightText: 2026 leonik <leonik.eut@gmail.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
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
    // rejecting quotes here is what keeps the interpolation safe. A leading
    // dash is excluded as well, so a host can never be read as an option.
    readonly property bool hostValid: /^[A-Za-z0-9\[][A-Za-z0-9._:%\[\]-]*$/.test(host)

    // plasma-ping-helper speaks ICMP directly and answers in JSON. Three
    // candidates are tried in order, each falling through to the next when it
    // produces nothing usable: one the user built, which matches their system
    // exactly, then the copy shipped inside this package, which may be for
    // another architecture or need a newer C library, then /usr/bin/ping, which
    // is always there. The widget works whichever one answers.
    readonly property int backendUserHelper: 0
    readonly property int backendBundledHelper: 1
    readonly property int backendPing: 2
    property int backend: backendUserHelper

    readonly property string userHelperPath: "$HOME/.local/bin/plasma-ping-helper"
    // Resolved from this file's own location, so it follows the package
    // wherever it is installed. The architecture is left for the shell to fill
    // in, which picks the right file or none at all.
    readonly property string bundledHelperDir:
        Qt.resolvedUrl("../bin/").toString().replace(/^file:\/\//, "")

    readonly property string backendName: {
        switch (backend) {
        case backendUserHelper: return i18n("ICMP helper")
        case backendBundledHelper: return i18n("ICMP helper, bundled")
        default: return i18n("ping command")
        }
    }

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

    // Both backends bound their own runtime, but a wedged process would still
    // leave the widget stuck on "checking" forever, so cut it loose after a
    // grace period. The helper waits per packet, ping bounds the whole run.
    Timer {
        id: watchdog
        interval: {
            const timeout = Math.max(1, Plasmoid.configuration.timeout)
            const count = Math.max(1, Plasmoid.configuration.count)
            return (Math.max(timeout * count, timeout + count) + 5) * 1000
        }
        onTriggered: {
            executable.connectedSources = []
            root.busy = false
            root.applyResult(root.statusError, -1, -1, i18n("Timed out waiting for the check"))
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

        if (backend !== backendPing) {
            // $(uname -m) is left for the shell so one package serves any
            // architecture it was built for. The helper waits for each reply in
            // turn, so it needs no overall deadline.
            const helper = (backend === backendUserHelper)
                ? "\"" + userHelperPath + "\""
                : "\"" + bundledHelperDir + "plasma-ping-helper-$(uname -m)\""
            return helper + family
                 + " -c " + count
                 + " -w " + (timeout * 1000)
                 + " '" + host + "'"
        }

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

        if (backend !== backendPing) {
            const report = parseHelperOutput(stdout)
            if (report) {
                applyHelperResult(report)
                return
            }
            // Nothing usable came back, so this candidate is missing, built for
            // another architecture, or otherwise unrunnable. Move to the next
            // one for good and repeat the check straight away.
            backend = backend + 1
            checkNow()
            return
        }

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

    function parseHelperOutput(stdout) {
        const text = (stdout || "").trim()
        if (text.length === 0 || text.charAt(0) !== "{") {
            return null
        }
        try {
            const report = JSON.parse(text)
            return (report && typeof report.status === "string") ? report : null
        } catch (e) {
            return null
        }
    }

    function applyHelperResult(report) {
        const loss = typeof report.loss === "number" ? report.loss : -1
        const rtt = typeof report.rtt === "number" ? report.rtt : -1
        const from = typeof report.address === "string" ? report.address : ""

        switch (report.status) {
        case "success":
            applyResult(statusUp, rtt, loss,
                        loss > 0 ? i18n("%1% packet loss", Math.round(loss)) : "")
            break
        case "unsupported":
            // A reply arrived but its checksum did not add up.
            applyResult(statusUp, rtt, loss, i18n("Reply could not be verified"))
            break
        case "timeout":
            applyResult(statusDown, -1, loss >= 0 ? loss : 100, i18n("No reply from host"))
            break
        case "unreachable":
            applyResult(statusDown, -1, loss >= 0 ? loss : 100,
                        from.length > 0 ? i18n("Unreachable, reported by %1", from)
                                        : i18n("Host is unreachable"))
            break
        case "timeexceeded":
            applyResult(statusDown, -1, loss >= 0 ? loss : 100,
                        from.length > 0 ? i18n("TTL expired at %1", from)
                                        : i18n("TTL expired in transit"))
            break
        case "error":
            applyResult(statusError, -1, -1,
                        (typeof report.message === "string" && report.message.length > 0)
                            ? report.message : i18n("The ping helper reported an error"))
            break
        case "failure":
        default:
            applyResult(statusError, -1, -1, i18n("Could not send the request"))
            break
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

        historyModel.append({ ok: newStatus === statusUp, latency: newLatency, time: now })
        const limit = Math.max(5, Plasmoid.configuration.historySize)
        while (historyModel.count > limit) {
            historyModel.remove(0)
        }

        // Last, because the popup rescales its history strip when this changes
        // and the new entry has to be in the model by then.
        lastCheck = now

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
        backendName: root.backendName
        history: historyModel
        interval: Math.max(5, Plasmoid.configuration.interval)
        historySize: Math.max(5, Plasmoid.configuration.historySize)
        onRefreshRequested: root.checkNow()
        onConfigureRequested: Plasmoid.internalAction("configure").trigger()
    }
}
