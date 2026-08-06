# Ping Monitor

A KDE Plasma 6 widget that pings a host on a schedule and shows whether it is
reachable as a coloured dot.

| Dot | Meaning |
| --- | --- |
| 🟢 green | host replied |
| 🔴 red | no reply (`ping` exit code 1) |
| 🟠 orange | ping could not run, e.g. name resolution failed (exit code 2+) |
| ⚪ grey | not checked yet |

The dot pulses while a check is in flight.

## Install

```bash
./install.sh
systemctl --user restart plasma-plasmashell
```

Then right click the panel or desktop → *Add Widgets* → **Ping Monitor**.

`install.sh` installs into `~/.local/share/plasma/plasmoids/` for the current
user only, and upgrades in place if the widget is already installed. Plasma
caches QML, so restart plasmashell after every reinstall.

To remove it:

```bash
kpackagetool6 --type Plasma/Applet --remove io.github.leonik.pingmonitor
```

## Usage

- **Click** the dot to open the details popup: status, round trip time, packet
  loss, time of the last check, and a history strip with one bar per check
  (bar height is the round trip time, red means the check failed).
- **Middle click** the dot to check immediately without opening the popup.
- **Hover** the dot for the same information as a tooltip.

## Settings

Right click the widget → *Configure Ping Monitor…*

| Setting | Default | Notes |
| --- | --- | --- |
| Host | `1.1.1.1` | Host name, IPv4 or IPv6 address |
| Display name | empty | Shown instead of the host |
| IP version | Automatic | Passes `-4` or `-6` to ping |
| Check every | 30 s | Minimum 5 s |
| Wait for reply | 2 s | Per packet (`-W`) |
| Packets per check | 1 | Host counts as up if any packet returns |
| Show the name / round trip time | off | Draws a label next to the dot |
| Highlight while unreachable | on | Keeps the widget visible in the system tray |
| Notify when availability changes | off | Only fires on up ↔ down transitions, never on the first result |
| History length | 30 | Bars kept in the strip |

## How it works

The widget runs `ping` through the Plasma `executable` data engine and reads the
exit code: 0 is up, 1 is down, anything else is an error. Round trip time is
taken from the `rtt min/avg/max/mdev` summary line, falling back to `time=`;
`LC_ALL=C` keeps that output parseable regardless of your locale.

No root privileges are needed — `/usr/bin/ping` carries `cap_net_raw`, so it
runs fine as your user.

The host is validated against `^[A-Za-z0-9._:%\[\]-]+$` before being
single quoted into the command, which is what keeps the shell interpolation
safe. Anything containing shell syntax is rejected as an invalid host.

Every check spawns a short lived `ping` process; the poll interval is the
practical floor on how often that happens.

## Layout

```
package/
├── metadata.json                     plugin id, name, icon
└── contents/
    ├── config/
    │   ├── main.xml                  config keys and defaults
    │   └── config.qml                config page list
    └── ui/
        ├── main.qml                  ping logic, state, notifications
        ├── CompactRepresentation.qml the panel dot
        ├── FullRepresentation.qml    the popup
        ├── StatusDot.qml             the dot itself, reused in both
        └── configGeneral.qml         settings page
```
