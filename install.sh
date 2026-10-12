#!/bin/bash
# Instala a extensão (symlink + schema), os wallpapers embutidos e o atalho da
# galeria. Não muda nada na sessão em uso: para ligar, rode ./ativar.sh.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UUID="primoengine@gpr"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
APP="dev.gpr.PrimoEngine.Gallery"

link() {
    local source="$1" target="$2"
    mkdir -p "$(dirname "$target")"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        echo "Já existe algo em $target que não é um symlink; não vou sobrescrever." >&2
        exit 1
    fi
    ln -sfn "$source" "$target"
}

glib-compile-schemas --strict "$REPO/schemas"

link "$REPO" "$DATA/gnome-shell/extensions/$UUID"
link "$REPO/wallpapers" "$DATA/primoengine/wallpapers"
link "$REPO/data/$APP.svg" "$DATA/icons/hicolor/scalable/apps/$APP.svg"

mkdir -p "$DATA/applications"
sed "s#@REPO@#$REPO#" "$REPO/data/$APP.desktop.in" > "$DATA/applications/$APP.desktop"
update-desktop-database "$DATA/applications" 2>/dev/null || true

echo "Instalado em $DATA/gnome-shell/extensions/$UUID"
echo "Próximo passo: ./ativar.sh e depois sair e entrar na sessão."
