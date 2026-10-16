#!/bin/bash
# Põe um submenu "GprEngine" no menu do botão direito da área de trabalho.
#
#     tools/ding-menu.sh            instala (ou refaz, depois de atualizar o Ubuntu)
#     tools/ding-menu.sh --system   também no arquivo do sistema (sudo), na hora
#     tools/ding-menu.sh --remove   volta para o Desktop Icons original
#
# O menu é do Desktop Icons NG (ding@rastersoft.com), que roda num processo
# próprio e não aceita itens de outras extensões. O script copia a extensão do
# sistema para ~/.local/share/gnome-shell/extensions/, que tem prioridade sobre
# /usr/share, e acrescenta o submenu na cópia. Vale a partir da próxima entrada
# na sessão.
#
# Com --system, o mesmo submenu entra também no arquivo de /usr/share (o
# original fica em desktopManager.js.orig-gprengine) e o processo do Desktop
# Icons é reiniciado, para aparecer sem sair da sessão. Uma atualização do
# pacote gnome-shell-ubuntu-extensions desfaz essa parte.
set -euo pipefail

UUID="ding@rastersoft.com"
SYSTEM="/usr/share/gnome-shell/extensions/$UUID"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
TARGET="$DATA/gnome-shell/extensions/$UUID"
MARK="// GprEngine: submenu"

restart_ding() {
    local pid
    pid="$(ps -C gjs -o pid=,args= | awk '/ding@rastersoft.com\/app\/ding.js/ {print $1}')"
    # A extensão sobe o processo de novo sozinha, já com o arquivo novo.
    [ -n "$pid" ] && kill $pid || true
}

if [ "${1:-}" = "--remove" ]; then
    if [ -f "$SYSTEM/app/desktopManager.js.orig-gprengine" ]; then
        sudo mv "$SYSTEM/app/desktopManager.js.orig-gprengine" "$SYSTEM/app/desktopManager.js"
        restart_ding
    fi
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

if [ "${1:-}" = "--system" ]; then
    SYS_FILE="$SYSTEM/app/desktopManager.js"
    if ! grep -qF "$MARK" "$SYS_FILE"; then
        sudo cp "$SYS_FILE" "$SYS_FILE.orig-gprengine"
        sudo cp "$TARGET/app/desktopManager.js" "$SYS_FILE"
    fi
    restart_ding
    echo "Aplicado também em $SYSTEM; o submenu já aparece no botão direito."
    exit 0
fi
echo "Saia e entre na sessão para o submenu GprEngine aparecer no botão direito da área de trabalho."
