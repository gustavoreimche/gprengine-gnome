import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const BUS_NAME = 'dev.gpr.PrimoEngine';
const OBJECT_PATH = '/dev/gpr/PrimoEngine';

// A pausa entra depois desse tempo estável, para não piscar ao arrastar uma
// janela; a retomada é imediata.
const SETTLE_MS = 500;
// Fração da área útil que as janelas precisam cobrir para contar como coberto.
const COVERED_FRACTION = 0.95;

const UPOWER_STATE_DISCHARGING = 2;

// Área da união de retângulos, sem contar sobreposição duas vezes: corta em
// faixas verticais e soma, em cada uma, os intervalos de y já fundidos.
function unionArea(rects) {
    const xs = [...new Set(rects.flatMap(r => [r.x1, r.x2]))].sort((a, b) => a - b);
    let area = 0;
    for (let i = 0; i + 1 < xs.length; i++) {
        const spans = rects
            .filter(r => r.x1 <= xs[i] && r.x2 >= xs[i + 1])
            .map(r => [r.y1, r.y2])
            .sort((a, b) => a[0] - b[0]);
        let height = 0;
        let end = -Infinity;
        for (const [y1, y2] of spans) {
            if (y2 <= end)
                continue;
            height += y2 - Math.max(y1, end);
            end = y2;
        }
        area += height * (xs[i + 1] - xs[i]);
    }
    return area;
}

// Decide quando o renderer deve parar e avisa por D-Bus. Cada condição é um
// motivo independente; o renderer só volta quando todos saem.
export class PauseController {
    constructor(settings, isRenderer) {
        this._settings = settings;
        this._isRenderer = isRenderer;
        this._sent = new Map();
        this._powerSaving = null;
        this._onBattery = false;
        this._screenOff = false;
        this._settleId = 0;
        this._watched = new Set();

        this._watchId = Gio.bus_watch_name(
            Gio.BusType.SESSION, BUS_NAME, Gio.BusNameWatcherFlags.NONE,
            () => this._resend(), null);

        global.display.connectObject(
            'in-fullscreen-changed', () => this._evaluate(),
            'restacked', () => this._evaluate(),
            'window-created', (_d, window) => this._watch(window),
            this);
        global.window_manager.connectObject(
            'switch-workspace', () => this._evaluate(),
            'minimize', () => this._evaluate(),
            'unminimize', () => this._evaluate(),
            'size-change', () => this._evaluate(),
            'destroy', () => this._evaluate(),
            this);
        Main.overview.connectObject(
            'showing', () => this._evaluate(),
            'hidden', () => this._evaluate(),
            this);
        Main.layoutManager.connectObject(
            'monitors-changed', () => this._evaluate(), this);
        global.backend.get_monitor_manager().connectObject(
            'power-save-mode-changed', (_mm, mode) => {
                // O enum não é exposto ao GJS; 0 é "ligada".
                this._screenOff = mode !== 0;
                this._evaluate();
            }, this);
        this._settings.connectObject(
            'changed::pause-when-covered', () => this._evaluate(),
            'changed::battery-mode', () => this._evaluate(),
            this);

        for (const actor of global.get_window_actors())
            this._watch(actor.meta_window);

        this._initBattery();
        this._evaluate();
    }

    // --- bateria ---

    async _initBattery() {
        this._cancellable = new Gio.Cancellable();
        try {
            this._upower = await Gio.DBusProxy.new_for_bus(
                Gio.BusType.SYSTEM, Gio.DBusProxyFlags.NONE, null,
                'org.freedesktop.UPower',
                '/org/freedesktop/UPower/devices/DisplayDevice',
                'org.freedesktop.UPower.Device', this._cancellable);
        } catch {
            // Sem UPower não há motivo de bateria; o resto segue.
            return;
        }
        this._upower.connectObject(
            'g-properties-changed', () => this._syncBattery(), this);
        this._syncBattery();
    }

    _syncBattery() {
        const state = this._upower?.get_cached_property('State')?.unpack();
        this.setOnBattery(state === UPOWER_STATE_DISCHARGING);
    }

    setOnBattery(onBattery) {
        if (this._onBattery === onBattery)
            return;
        this._onBattery = onBattery;
        this._evaluate();
    }

    // --- janelas ---

    _watch(window) {
        if (!window || this._watched.has(window) || this._isRenderer(window))
            return;
        this._watched.add(window);
        window.connectObject(
            'position-changed', () => this._evaluate(),
            'size-changed', () => this._evaluate(),
            'unmanaged', () => {
                window.disconnectObject(this);
                this._watched.delete(window);
                this._evaluate();
            }, this);
    }

    _coveringWindows(monitorIndex) {
        const workspace = global.workspace_manager.get_active_workspace();
        return [...this._watched].filter(window =>
            !this._isRenderer(window) &&
            window.get_monitor() === monitorIndex &&
            window.located_on_workspace(workspace) &&
            window.showing_on_its_workspace() &&
            window.get_window_type() !== Meta.WindowType.DESKTOP &&
            // Os ícones da área de trabalho (DING) são uma janela do tamanho
            // da tela, mas transparente.
            window.get_gtk_application_id() !== 'com.rastersoft.ding');
    }

    _isCovered(monitorIndex) {
        const windows = this._coveringWindows(monitorIndex);
        if (windows.some(w => w.is_maximized()))
            return true;

        const area = Main.layoutManager.getWorkAreaForMonitor(monitorIndex);
        const rects = [];
        for (const window of windows) {
            const frame = window.get_frame_rect();
            const x1 = Math.max(frame.x, area.x);
            const y1 = Math.max(frame.y, area.y);
            const x2 = Math.min(frame.x + frame.width, area.x + area.width);
            const y2 = Math.min(frame.y + frame.height, area.y + area.height);
            if (x2 > x1 && y2 > y1)
                rects.push({x1, y1, x2, y2});
        }
        return unionArea(rects) >= COVERED_FRACTION * area.width * area.height;
    }

    // --- decisão ---

    _compute() {
        const monitors = Main.layoutManager.monitors.map((_m, i) => i);
        const overview = Main.overview.visible;
        // Na visão geral o fundo aparece mesmo com janela em tela cheia.
        const fullscreen = !overview && monitors.length > 0 &&
            monitors.every(i => global.display.get_monitor_in_fullscreen(i));
        const covered = !overview && !fullscreen && monitors.length > 0 &&
            this._settings.get_boolean('pause-when-covered') &&
            monitors.every(i => this._isCovered(i));
        const mode = this._settings.get_string('battery-mode');
        return {
            reasons: {
                fullscreen,
                covered,
                'screen-off': this._screenOff,
                battery: this._onBattery && mode === 'pause',
            },
            powerSaving: this._onBattery && mode === 'limit',
        };
    }

    _evaluate() {
        const {reasons, powerSaving} = this._compute();
        this._setPowerSaving(powerSaving);

        // Motivos que saem valem na hora.
        for (const [reason, active] of Object.entries(reasons)) {
            if (!active)
                this._setReason(reason, false);
        }
        const entering = Object.entries(reasons)
            .some(([reason, active]) => active && !this._sent.get(reason));
        if (!entering) {
            this._clearSettle();
        } else if (!this._settleId) {
            this._settleId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, SETTLE_MS, () => {
                this._settleId = 0;
                const settled = this._compute().reasons;
                for (const [reason, active] of Object.entries(settled))
                    this._setReason(reason, active);
                return GLib.SOURCE_REMOVE;
            });
        }
    }

    _clearSettle() {
        if (this._settleId) {
            GLib.source_remove(this._settleId);
            this._settleId = 0;
        }
    }

    // --- D-Bus ---

    _call(method, parameters) {
        Gio.DBus.session.call(
            BUS_NAME, OBJECT_PATH, BUS_NAME, method, parameters, null,
            Gio.DBusCallFlags.NO_AUTO_START, -1, null, (connection, result) => {
                try {
                    connection.call_finish(result);
                } catch {
                    // Renderer fora do ar: _resend repete tudo quando voltar.
                }
            });
    }

    _setReason(reason, active) {
        if (!!this._sent.get(reason) === active)
            return;
        this._sent.set(reason, active);
        this._call('SetPaused', new GLib.Variant('(bs)', [active, reason]));
    }

    _setPowerSaving(enabled) {
        if (this._powerSaving === enabled)
            return;
        this._powerSaving = enabled;
        this._call('SetPowerSaving', new GLib.Variant('(b)', [enabled]));
    }

    // Um renderer recém-iniciado não sabe de nada: repete o estado atual.
    _resend() {
        for (const [reason, active] of this._sent) {
            if (active)
                this._call('SetPaused', new GLib.Variant('(bs)', [true, reason]));
        }
        if (this._powerSaving)
            this._call('SetPowerSaving', new GLib.Variant('(b)', [true]));
    }

    get reasons() {
        return [...this._sent].filter(([, active]) => active).map(([r]) => r);
    }

    destroy() {
        this._clearSettle();
        this._cancellable?.cancel();
        this._upower?.disconnectObject(this);
        this._upower = null;
        Gio.bus_unwatch_name(this._watchId);
        global.display.disconnectObject(this);
        global.window_manager.disconnectObject(this);
        Main.overview.disconnectObject(this);
        Main.layoutManager.disconnectObject(this);
        global.backend.get_monitor_manager().disconnectObject(this);
        this._settings.disconnectObject(this);
        for (const window of this._watched)
            window.disconnectObject(this);
        this._watched.clear();
    }
}
