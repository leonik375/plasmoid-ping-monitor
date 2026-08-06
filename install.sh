#!/bin/bash
# Install or upgrade the Ping Monitor plasmoid, and the ICMP helper it prefers,
# for the current user. Neither step needs root.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

ID="io.github.leonik.pingmonitor"
PREFIX="${PREFIX:-$HOME/.local}"

if kpackagetool6 --type Plasma/Applet --show "$ID" >/dev/null 2>&1; then
    echo "Upgrading $ID…"
    kpackagetool6 --type Plasma/Applet --upgrade package
else
    echo "Installing $ID…"
    kpackagetool6 --type Plasma/Applet --install package
fi

# The widget falls back to /usr/bin/ping when the helper is missing, so a
# failure here is not fatal.
echo
if [ ! -e third_party/cpp-icmplib/icmplib.h ]; then
    echo "Skipping the ICMP helper: the cpp-icmplib submodule is not checked out."
    echo "Run 'git submodule update --init --recursive' then './install.sh' again."
elif make -s install PREFIX="$PREFIX"; then
    echo "The widget will use the helper and report 'ICMP helper' in its popup."
else
    echo "Could not build the ICMP helper; the widget will use /usr/bin/ping."
fi

echo
echo "Restart Plasma to pick up QML changes:"
echo "    systemctl --user restart plasma-plasmashell"
echo
echo "Then add it with: right click the panel or desktop -> Add Widgets -> Ping Monitor"
