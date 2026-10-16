#!/bin/bash
# Põe um submenu "GprEngine" no menu do botão direito da área de trabalho.
#
#     tools/ding-menu.sh            instala (ou refaz, depois de atualizar o Ubuntu)
#     tools/ding-menu.sh --remove   volta para o Desktop Icons original
#
# O menu é do Desktop Icons NG (ding@rastersoft.com), que roda num processo
# próprio e não aceita itens de outras extensões. O script copia a extensão do
# sistema para ~/.local/share/gnome-shell/extensions/, que tem prioridade sobre
# /usr/share, e acrescenta o submenu na cópia. Nada do sistema é alterado.
# Vale a partir da próxima entrada na sessão.
set -euo pipefail

UUID="ding@rastersoft.com"
SYSTEM="/usr/share/gnome-shell/extensions/$UUID"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
TARGET="$DATA/gnome-shell/extensions/$UUID"
MARK="// GprEngine: submenu"

if [ "${1:-}" = "--remove" ]; then
    if [ -f "$TARGET/.gprengine" ]; then
        rm -rf "$TARGET"
        echo "Removido. O Desktop Icons do sistema volta na próxima entrada na sessão."
    else
        echo "Nada a remover em $TARGET."
    fi
    exit 0
fi

if [ ! -d "$SYSTEM" ]; then
    echo "Não achei o Desktop Icons em $SYSTEM." >&2
    exit 1
fi
if [ -e "$TARGET" ] && [ ! -f "$TARGET/.gprengine" ]; then
    echo "Já existe uma cópia do Desktop Icons em $TARGET que não é deste script; não vou sobrescrever." >&2
    exit 1
fi

rm -rf "$TARGET"
mkdir -p "$(dirname "$TARGET")"
cp -r "$SYSTEM" "$TARGET"
touch "$TARGET/.gprengine"

/usr/bin/python3 - "$TARGET/app/desktopManager.js" "$MARK" <<'EOF'
import sys

path, mark = sys.argv[1], sys.argv[2]
anchor = "        this._menu.add(this._changeBackgroundMenuItem);\n"
block = """
        """ + mark + """
        const gprCall = method => GLib.spawn_command_line_async(
            `gdbus call --session --dest dev.gpr.GprEngine --object-path /dev/gpr/GprEngine --method dev.gpr.GprEngine.${method}`);
        const gprMenu = new Gtk.Menu();
        const gprItems = [
            ['Abrir a galeria', () => {
                const app = GioUnix.DesktopAppInfo.new('dev.gpr.GprEngine.Gallery.desktop');
                if (app) {
                    const context = Gdk.Display.get_default().get_app_launch_context();
                    context.set_timestamp(Gtk.get_current_event_time());
                    app.launch([], context);
                }
            }],
            ['Próximo wallpaper', () => gprCall('Next')],
            ['Wallpaper anterior', () => gprCall('Previous')],
            ['Recarregar', () => gprCall('Reload')],
        ];
        for (const [label, action] of gprItems) {
            const item = new Gtk.MenuItem({label});
            item.connect('activate', action);
            gprMenu.add(item);
        }
        const gprEngineItem = new Gtk.MenuItem({label: 'GprEngine'});
        gprEngineItem.set_submenu(gprMenu);
        this._menu.add(gprEngineItem);
"""
src = open(path).read()
if mark in src:
    sys.exit(0)
if src.count(anchor) != 1:
    sys.exit(f'Não achei o ponto do menu em {path}: o Desktop Icons mudou.')
open(path, 'w').write(src.replace(anchor, anchor + block))
EOF

echo "Instalado em $TARGET."
echo "Saia e entre na sessão para o submenu GprEngine aparecer no botão direito da área de trabalho."
