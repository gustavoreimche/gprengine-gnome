#!/bin/bash
# Liga o GprEngine. O wallpaper só aparece depois de sair e entrar na sessão
# (no Wayland o GNOME Shell não carrega extensão nova com a sessão aberta).
set -euo pipefail

UUID="gprengine@gpr"

if [ ! -e "${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$UUID/metadata.json" ]; then
    echo "Extensão não instalada. Rode ./install.sh antes." >&2
    exit 1
fi

current="$(gsettings get org.gnome.shell enabled-extensions)"
case "$current" in
    *"'$UUID'"*) ;;
    "@as []") gsettings set org.gnome.shell enabled-extensions "['$UUID']" ;;
    *) gsettings set org.gnome.shell enabled-extensions "${current%]}, '$UUID']" ;;
esac

echo "Pronto. Salve o que estiver aberto e saia e entre na sessão para o wallpaper aparecer."
echo "Para voltar ao que era: ./uninstall.sh"
