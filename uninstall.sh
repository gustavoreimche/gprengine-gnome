#!/bin/bash
# Desliga e remove o PrimoEngine. Os seus wallpapers em
# ~/.config/primoengine/ e este repositório ficam como estão.
set -euo pipefail

UUID="primoengine@gpr"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
APP="dev.gpr.PrimoEngine.Gallery"

gnome-extensions disable "$UUID" 2>/dev/null || true

for target in "$DATA/gnome-shell/extensions/$UUID" \
              "$DATA/primoengine/wallpapers" \
              "$DATA/icons/hicolor/scalable/apps/$APP.svg"; do
    [ -L "$target" ] && rm "$target"
done
rmdir "$DATA/primoengine" 2>/dev/null || true
rm -f "$DATA/applications/$APP.desktop"
update-desktop-database "$DATA/applications" 2>/dev/null || true

echo "Removido. O fundo estático do GNOME volta na hora."
