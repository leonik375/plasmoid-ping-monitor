#!/bin/bash
# Install or upgrade the Ping Monitor plasmoid for the current user.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

ID="io.github.leonik.pingmonitor"

if kpackagetool6 --type Plasma/Applet --show "$ID" >/dev/null 2>&1; then
    echo "Upgrading $ID…"
    kpackagetool6 --type Plasma/Applet --upgrade package
else
    echo "Installing $ID…"
    kpackagetool6 --type Plasma/Applet --install package
fi

echo
echo "Done. Restart Plasma to pick up QML changes:"
echo "    systemctl --user restart plasma-plasmashell"
echo
echo "Then add it with: right click the panel or desktop -> Add Widgets -> Ping Monitor"
