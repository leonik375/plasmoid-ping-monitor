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
git clone --recurse-submodules <this repo>
cd plasma-ping
./install.sh
systemctl --user restart plasma-plasmashell
```

Then right click the panel or desktop → *Add Widgets* → **Ping Monitor**.

`install.sh` puts the widget in `~/.local/share/plasma/plasmoids/` and the ICMP
helper in `~/.local/bin/`, both for the current user, and upgrades in place if
they are already installed. **No step needs root.** Plasma caches QML, so
restart plasmashell after every reinstall.

If you already cloned without `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

To remove it:

```bash
kpackagetool6 --type Plasma/Applet --remove io.github.leonik.pingmonitor
make uninstall
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

The widget is plain QML and cannot speak ICMP itself, so each check runs a short
lived process through the Plasma `executable` data engine. There are two
backends, and the popup shows which one is live under **Measured by**.

**`plasma-ping-helper`** (preferred) is a small C++ program built from
[cpp-icmplib](https://github.com/markondej/cpp-icmplib). It sends the echo
requests itself and prints one JSON object:

```json
{"status":"success","host":"1.1.1.1","sent":1,"received":1,"loss":0,
 "rtt":24.4,"rtt_min":24.4,"rtt_max":24.4,"address":"1.1.1.1","code":0,"ttl":0}
```

`status` is one of `success`, `timeout`, `unreachable`, `timeexceeded`,
`unsupported`, `failure` or `error`, which is more than `ping`'s exit code can
express — an unroutable host and an expired TTL become distinguishable.

**`/usr/bin/ping`** is the fallback, used automatically whenever the helper is
missing or unrunnable, so the widget works before you have built anything. It
parses the `rtt min/avg/max/mdev` line, falling back to `time=`, with `LC_ALL=C`
to keep the output stable regardless of your locale.

### No root, either way

`/usr/bin/ping` already carries `cap_net_raw`. The helper needs no privileges at
all: it uses Linux **ping sockets** (`SOCK_DGRAM`/`IPPROTO_ICMP`), which any user
in `net.ipv4.ping_group_range` may open.

```bash
$ cat /proc/sys/net/ipv4/ping_group_range
0	2147483647          # the default on most distributions: everyone
```

cpp-icmplib opens a raw socket, which needs `CAP_NET_RAW`, and falls back to a
ping socket when that is refused. That fallback is not upstream yet — it is
[markondej/cpp-icmplib#8](https://github.com/markondej/cpp-icmplib/pull/8) — so
the submodule tracks the fork carrying it and moves back to upstream once it
lands. Nothing is patched at build time.

One consequence of ping socket semantics: TTL lives in the IP header the kernel
does not pass on, so it is reported as `0`. Everything else, including
`unreachable` and `timeexceeded`, is reported normally.

### Host validation

The host is checked against `^[A-Za-z0-9\[][A-Za-z0-9._:%\[\]-]*$` before being
single quoted into the command. That excludes every shell metacharacter, and the
leading character rule stops a host from being read as a command line option.

Every check spawns a process; the poll interval is the practical floor on how
often that happens.

## Layout

```
├── Makefile                          builds and installs the helper
├── install.sh                        widget + helper, no root
├── src/
│   └── plasma-ping-helper.cpp        ICMP helper, prints JSON
├── third_party/
│   └── cpp-icmplib/                  submodule, never modified
└── package/
    ├── metadata.json                 plugin id, name, icon
    └── contents/
        ├── config/
        │   ├── main.xml              config keys and defaults
        │   └── config.qml            config page list
        └── ui/
            ├── main.qml              check logic, state, notifications
            ├── CompactRepresentation.qml the panel dot
            ├── FullRepresentation.qml    the popup
            ├── StatusDot.qml             the dot itself, reused in both
            └── configGeneral.qml         settings page
```

## Helper on its own

It is a normal command line tool, useful for checking the install:

```console
$ plasma-ping-helper 1.1.1.1 -c 3 -w 2000
{"status":"success","host":"1.1.1.1","sent":3,"received":3,"loss":0, ...}
$ echo $?     # 0 replied, 1 no reply, 2 usage or system error
0
```

`make check` runs it against a reachable host, an unroutable one and a bad name.

## Releasing

Two independent artifacts, neither derived from the other.

**store.kde.org** takes a `.plasmoid`, which is the QML package alone. The
submodule and the helper play no part in it, so none of the archive problem
below applies. Uploading is manual, through the web interface, once per release:

```bash
make plasmoid                   # -> plasmoid-ping-monitor-<version>.plasmoid
```

The package carries a helper built for the architecture it was made on, named
after it, so the widget picks the right file or none at all. Anyone on another
architecture, or with a C library too old to load it, falls back to
`/usr/bin/ping` and still gets a fully working widget.

The widget tries three things in order, each falling through when it returns
nothing usable: a helper in `~/.local/bin`, which matches the system it was
built on exactly; the copy inside the package; then `/usr/bin/ping`. The popup
names whichever answered.

Deliberately linked dynamically. A static build would resolve IP addresses but
fail on host names wherever the glibc differs, and that failure reports a
plausible looking error instead of falling through to `ping`.

**Source releases** are for people who want the helper as well.

Both artifacts take their version from the git tag, and both refuse to build if
it disagrees with `package/metadata.json`. That version is what Plasma compares
to decide an update exists, so a release that got it wrong would never reach
anyone already running the widget. To cut one, bump `metadata.json`, commit, then
tag `v<version>` to match.


GitHub builds its source archives with `git archive`, which leaves submodule
directories empty, so neither the download button nor the files it generates for
a release can be built from. Attach a complete tarball instead:

```bash
git submodule update --init --recursive
make dist                       # refuses if the submodule is missing
gh release create v1.0 plasmoid-ping-monitor-v1.0.tar.gz \
    --notes "Build from the attached tarball. The source archives GitHub
             generates are incomplete, as they omit the cpp-icmplib submodule."
```

The auto-generated archives still appear on the release page and cannot be
removed, so name the asset distinctly and say which one to use. Anyone cloning
with `--recurse-submodules` is unaffected, and a build from an incomplete
archive fails with instructions rather than silently.

## Licensing

The widget and the helper are GPL-2.0-or-later. cpp-icmplib is BSD 3-Clause,
Copyright (c) 2021 Marcin Kondej, and is included as a submodule.
