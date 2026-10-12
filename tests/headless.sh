#!/bin/bash
# GNOME Shell headless e isolado para testar sem tocar na sessão em uso:
# barramento, dconf, dados e socket Wayland próprios.
#
#   tests/headless.sh start [LARGURAxALTURA]
#   tests/headless.sh run <comando...>     roda algo dentro da sessão de teste
#   tests/headless.sh eval '<js>'          avalia JS dentro do shell
#   tests/headless.sh shot <arquivo.png>
#   tests/headless.sh stop
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${PRIMOENGINE_TEST_ROOT:-$REPO/.dev/headless}"
UUID="primoengine@gpr"

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
             "$ROOT/data/gnome-shell/extensions" "$ROOT/data/primoengine"
    chmod 700 "$ROOT/rt"
    ln -s "$REPO" "$ROOT/data/gnome-shell/extensions/$UUID"
    ln -s "$REPO/wallpapers" "$ROOT/data/primoengine/wallpapers"
    session_env
    unset DBUS_SESSION_BUS_ADDRESS
    setsid dbus-run-session -- bash -c '
        echo "$DBUS_SESSION_BUS_ADDRESS" > "$0/bus"
        exec gnome-shell --headless --wayland --no-x11 --unsafe-mode \
            --virtual-monitor "$1" --wayland-display "$WAYLAND_DISPLAY"
    ' "$ROOT" "$size" > "$ROOT/shell.log" 2>&1 &
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
stop)
    if [ -f "$ROOT/pid" ]; then
        # setsid fez do dbus-run-session o líder do grupo: mata tudo junto.
        kill -- "-$(cat "$ROOT/pid")" 2>/dev/null || true
        rm -f "$ROOT/pid"
    fi
    ;;
*)
    sed -n '2,10p' "$0" >&2
    exit 2
    ;;
esac
