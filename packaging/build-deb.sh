#!/bin/bash
# Monta o pacote .deb do GprEngine.
#
#   packaging/build-deb.sh [VERSÃO] [PASTA_DE_SAÍDA]
#
# Sem versão, usa a de packaging/VERSION. O pacote instala
# a extensão para todos os usuários, junto com o renderer, a galeria e os
# wallpapers de packaging/base-wallpapers.txt; cada usuário ainda precisa
# ativá-la.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-$(cat "$REPO/packaging/VERSION")}"
OUT="$(realpath -m "${2:-$REPO/dist}")"
UUID="gprengine@gpr"
APP="dev.gpr.GprEngine.Gallery"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
EXT="$STAGE/usr/share/gnome-shell/extensions/$UUID"

mkdir -p "$EXT" "$STAGE/DEBIAN" "$STAGE/usr/bin" "$STAGE/usr/share/applications" \
         "$STAGE/usr/share/icons/hicolor/scalable/apps" "$STAGE/usr/share/doc/gprengine"
cp -r "$REPO/metadata.json" "$REPO/extension.js" "$REPO/shell" "$REPO/engine" \
      "$REPO/bin" "$EXT/"
# Só o conjunto básico vai no pacote; o resto vem pelo catálogo da galeria.
mkdir "$EXT/wallpapers"
while read -r id; do
    [ -n "$id" ] && cp -r "$REPO/wallpapers/$id" "$EXT/wallpapers/"
done < "$REPO/packaging/base-wallpapers.txt"
mkdir "$EXT/schemas" "$EXT/docs"
# O guia é aberto pela galeria.
cp "$REPO/docs/wallpapers-personalizados.md" "$EXT/docs/"
cp "$REPO"/schemas/*.gschema.xml "$EXT/schemas/"
glib-compile-schemas --strict "$EXT/schemas"
find "$EXT" -name __pycache__ -prune -exec rm -rf {} +

ln -s "../share/gnome-shell/extensions/$UUID/bin/gprengine-gallery" "$STAGE/usr/bin/gprengine"
sed "s#@REPO@#/usr/share/gnome-shell/extensions/$UUID#" "$REPO/data/$APP.desktop.in" \
    > "$STAGE/usr/share/applications/$APP.desktop"
cp "$REPO/data/$APP.svg" "$STAGE/usr/share/icons/hicolor/scalable/apps/"

cat > "$STAGE/usr/share/doc/gprengine/copyright" <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: GprEngine
Source: https://github.com/gustavoreimche/gprengine-gnome

Files: *
Copyright: 2026 Gustavo Peters Reimche
License: GPL-3+
 On Debian systems, the full text of the GNU General Public License version 3
 can be found in /usr/share/common-licenses/GPL-3.
COPYRIGHT

find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE" -type f -exec chmod 644 {} +
chmod 755 "$EXT"/bin/*

cat > "$STAGE/DEBIAN/control" <<CONTROL
Package: gprengine
Version: $VERSION
Architecture: all
Maintainer: Gustavo Peters Reimche <gustavoprdev@gmail.com>
Installed-Size: $(du -sk "$STAGE/usr" | cut -f1)
Depends: gnome-shell (>= 50~), python3 (>= 3.10), python3-gi, python3-gi-cairo, gir1.2-gtk-4.0, gir1.2-adw-1, gir1.2-gdkpixbuf-2.0, libopengl0
Section: gnome
Priority: optional
Homepage: https://github.com/gustavoreimche/gprengine-gnome
Description: Wallpapers vivos para o GNOME Shell
 Shaders desenhados na GPU como fundo da área de trabalho, que param sozinhos
 quando ninguém está olhando (tela cheia, janelas cobrindo, tela desligada).
 .
 Traz a extensão do GNOME Shell, o renderer, a galeria para escolher e ajustar
 e um conjunto de wallpapers. Depois de instalar, saia e entre na sessão e
 ative a extensão "GprEngine GNOME".
CONTROL

mkdir -p "$OUT"
dpkg-deb --root-owner-group --build "$STAGE" "$OUT/gprengine_${VERSION}_all.deb" >/dev/null
echo "$OUT/gprengine_${VERSION}_all.deb"
