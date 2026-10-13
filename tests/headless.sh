#!/bin/bash
# GNOME Shell headless e isolado para testar sem tocar na sessão em uso:
# barramento, dconf, dados e socket Wayland próprios.
#
#   tests/headless.sh start [LARGURAxALTURA]
#   tests/headless.sh run <comando...>     roda algo dentro da sessão de teste
#   tests/headless.sh eval '<js>'          avalia JS dentro do shell
#   tests/headless.sh shot <arquivo.png>
#   tests/headless.sh alive               sai com 0 se o shell está de pé
#   tests/headless.sh stop
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${GPRENGINE_TEST_ROOT:-$REPO/.dev/headless}"
UUID="gprengine@gpr"

session_env() {
    export XDG_RUNTIME_DIR="$ROOT/rt"
    export XDG_CONFIG_HOME="$ROOT/config"
    export XDG_DATA_HOME="$ROOT/data"
    export XDG_CACHE_HOME="$ROOT/cache"
    export WAYLAND_DISPLAY="primo-test"
    export GDK_BACKEND=wayland
    unset DISPLAY
    if [ -f "$ROOT/bus" ]; then
        DBUS_SESSION_BUS_ADDRESS="$(cat "$ROOT/bus")"
        export DBUS_SESSION_BUS_ADDRESS
    fi
}

case "${1:-}" in
start)
    size="${2:-1600x900}"
    [ -f "$ROOT/pid" ] && kill -0 "$(cat "$ROOT/pid")" 2>/dev/null && {
        echo "já está rodando" >&2; exit 1; }
    rm -rf "$ROOT"
    mkdir -p "$ROOT/rt" "$ROOT/config" "$ROOT/cache" \
             "$ROOT/data/gnome-shell/extensions" "$ROOT/data/gprengine"
    chmod 700 "$ROOT/rt"
    ln -s "$REPO" "$ROOT/data/gnome-shell/extensions/$UUID"
    ln -s "$REPO/wallpapers" "$ROOT/data/gprengine/wallpapers"
    mkdir -p "$ROOT/data/applications"
    sed "s#@REPO@#$REPO#" "$REPO/data/dev.gpr.GprEngine.Gallery.desktop.in" \
        > "$ROOT/data/applications/dev.gpr.GprEngine.Gallery.desktop"
    enabled="['$UUID']"
    # GPRDOCK=<pasta do gprdock>: carrega o dock junto, com o tile
    # do GprEngine, para testar a integração.
    if [ -n "${GPRDOCK:-}" ]; then
        ln -s "$GPRDOCK" "$ROOT/data/gnome-shell/extensions/gprdock@gpr"
        enabled="['$UUID', 'gprdock@gpr']"
    fi
    session_env
    unset DBUS_SESSION_BUS_ADDRESS
    setsid dbus-run-session -- bash -c '
        echo "$DBUS_SESSION_BUS_ADDRESS" > "$0/bus"
        echo $$ > "$0/shell.pid"
        # PipeWire próprio, para tests/screencast.py.
        pipewire & wireplumber &
        sleep 1
        gsettings set org.gnome.shell disable-user-extensions false
        gsettings set org.gnome.shell enabled-extensions "$2"
        gsettings set org.gnome.shell welcome-dialog-last-shown-version 999
        if [ -n "${GPRDOCK:-}" ]; then
            gsettings --schemadir "$GPRDOCK/schemas" set \
                org.gnome.shell.extensions.gprdock widgets "[\"engine\", \"battery\"]"
        fi
        exec gnome-shell --headless --wayland --no-x11 --unsafe-mode \
            --virtual-monitor "$1" --wayland-display "$WAYLAND_DISPLAY"
    ' "$ROOT" "$size" "$enabled" > "$ROOT/shell.log" 2>&1 &
    echo $! > "$ROOT/pid"
    for _ in $(seq 50); do
        [ -S "$ROOT/rt/primo-test" ] && [ -s "$ROOT/bus" ] && { echo "pronto"; exit 0; }
        sleep 0.2
    done
    echo "o shell não subiu; veja $ROOT/shell.log" >&2
    exit 1
    ;;
run)
    shift
    session_env
    exec "$@"
    ;;
eval)
    session_env
    gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell \
        --method org.gnome.Shell.Eval "$2"
    ;;
shot)
    session_env
    gdbus call --session --dest org.gnome.Shell.Screenshot \
        --object-path /org/gnome/Shell/Screenshot \
        --method org.gnome.Shell.Screenshot.Screenshot false false "$(realpath -m "$2")"
    ;;
alive)
    kill -0 "$(cat "$ROOT/shell.pid" 2>/dev/null)" 2>/dev/null
    ;;
stop)
    if [ -f "$ROOT/pid" ]; then
        # setsid fez do dbus-run-session o líder do grupo: mata tudo junto.
        daemons="$(pgrep -P "$(cat "$ROOT/pid")" -x dbus-daemon || true)"
        kill -- "-$(cat "$ROOT/pid")" 2>/dev/null || true
        [ -n "$daemons" ] && kill $daemons 2>/dev/null || true
        rm -f "$ROOT/pid"
    fi
    # Os serviços ativados no barramento de teste (gvfsd, portal, o próprio
    # dbus-daemon...) saem do grupo e sobrevivem; cada sessão órfã segura
    # instâncias de inotify até faltar para a sessão real.
    if [ -s "$ROOT/bus" ]; then
        bus="DBUS_SESSION_BUS_ADDRESS=$(cat "$ROOT/bus")"
        for env in /proc/[0-9]*/environ; do
            pid="${env#/proc/}"; pid="${pid%/environ}"
            [ "$pid" = "$$" ] && continue
            if [ -r "$env" ] && cat "$env" 2>/dev/null | tr '\0' '\n' | grep -qxF "$bus"; then
                kill "$pid" 2>/dev/null || true
            fi
        done
        rm -f "$ROOT/bus"
    fi
    ;;
*)
    sed -n '2,10p' "$0" >&2
    exit 2
    ;;
esac
