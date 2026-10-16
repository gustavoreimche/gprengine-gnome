#!/bin/bash
# Desliga e remove o GprEngine. Os seus wallpapers em
# ~/.config/gprengine/ e este repositório ficam como estão.
set -euo pipefail

UUID="gprengine@gpr"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
APP="dev.gpr.GprEngine.Gallery"

gnome-extensions disable "$UUID" 2>/dev/null || true
"$(dirname "${BASH_SOURCE[0]}")/tools/ding-menu.sh" --remove

for target in "$DATA/gnome-shell/extensions/$UUID" \
              "$DATA/gprengine/wallpapers" \
              "$DATA/icons/hicolor/scalable/apps/$APP.svg"; do
    [ -L "$target" ] && rm "$target"
done
rmdir "$DATA/gprengine" 2>/dev/null || true
rm -f "$DATA/applications/$APP.desktop"
update-desktop-database "$DATA/applications" 2>/dev/null || true

echo "Removido. O fundo estático do GNOME volta na hora."
