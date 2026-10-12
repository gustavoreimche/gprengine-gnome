import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import * as Background from 'resource:///org/gnome/shell/ui/background.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as Workspace from 'resource:///org/gnome/shell/ui/workspace.js';
import * as WorkspaceThumbnail from 'resource:///org/gnome/shell/ui/workspaceThumbnail.js';
import {InjectionManager} from 'resource:///org/gnome/shell/extensions/extension.js';

import {RoundedClipEffect} from './roundedClip.js';

const TITLE_PREFIX = 'primoengine:';
const FADE_MS = 400;

// Camada viva dentro de um Meta.BackgroundActor: um clone da janela do
// renderer. Cada fundo que o shell cria (área de trabalho, miniaturas da visão
// geral, troca de workspace) ganha a sua.
const LiveLayer = GObject.registerClass(
class LiveLayer extends Clutter.Actor {
    _init(backgroundActor) {
        // clip_to_allocation: sem ele o volume de pintura seria o da janela
        // de origem do clone, não o nosso, e o recorte arredondado erraria a
        // conta.
        super._init({opacity: 0, clip_to_allocation: true});
        this.monitorIndex = backgroundActor.monitor;
        this.add_constraint(new Clutter.BindConstraint({
            source: backgroundActor,
            coordinate: Clutter.BindCoordinate.SIZE,
        }));
        this._clone = new Clutter.Clone();
        this._clone.add_constraint(new Clutter.BindConstraint({
            source: this,
            coordinate: Clutter.BindCoordinate.SIZE,
        }));
        this.add_child(this._clone);
        backgroundActor.add_child(this);

        // Só a visão geral arredonda o fundo. Fora dela o efeito fica
        // desligado, porque ligado ele custa uma cópia da tela por quadro.
        this._content = backgroundActor.content;
        this._clip = new RoundedClipEffect({enabled: false});
        this.add_effect(this._clip);
        this._content.connectObject(
            'notify::rounded-clip-radius', () => this._syncClip(), this);
        this.connect('notify::size', () => this._syncClip());
        this.connect('destroy', () => this._content.disconnectObject(this));
        this._syncClip();
    }

    _syncClip() {
        const radius = this._content.rounded_clip_radius;
        this._clip.enabled = radius > 0;
        if (radius <= 0)
            return;
        // Mesmos limites que o shell dá ao fundo estático: a área útil, em
        // coordenadas do monitor, levada para o tamanho com que o fundo foi
        // alocado na visão geral.
        const monitor = Main.layoutManager.monitors[this.monitorIndex];
        if (!monitor || this.width <= 0 || this.height <= 0)
            return;
        const area = Main.layoutManager.getWorkAreaForMonitor(this.monitorIndex);
        const sx = this.width / monitor.width;
        const sy = this.height / monitor.height;
        const x = (area.x - monitor.x) * sx;
        const y = (area.y - monitor.y) * sy;
        this._clip.setClip(this.width, this.height,
            [x, y, x + area.width * sx, y + area.height * sy], radius);
    }

    setSource(windowActor) {
        if (this._clone.source === windowActor)
            return;
        this._clone.source = windowActor;
        this.remove_all_transitions();
        if (windowActor) {
            this.ease({
                opacity: 255,
                duration: FADE_MS,
                mode: Clutter.AnimationMode.EASE_OUT_QUAD,
            });
        } else {
            this.opacity = 0;
        }
    }
});

// Põe as janelas do renderer na camada de fundo e as esconde de tudo que
// lista janelas (Alt+Tab, visão geral, docks).
export class WallpaperManager {
    constructor(process) {
        this._process = process;
        this._windows = new Map();
        this._layers = new Set();
        this._injections = new InjectionManager();

        this._hideFromShell();
        this._injectBackgrounds();

        global.display.connectObject(
            'window-created', (_d, window) => this._onWindowCreated(window),
            'notify::focus-window', () => this._refuseFocus(),
            'workareas-changed', () => this._placeAll(),
            this);
        Main.layoutManager.connectObject(
            'monitors-changed', () => this._placeAll(), this);

        for (const actor of this._allWindowActors())
            this._onWindowCreated(actor.meta_window);
        Main.layoutManager._updateBackgrounds();
    }

    isRenderer(window) {
        return !!window && this._process.pid > 0 &&
            window.get_pid() === this._process.pid;
    }

    _allWindowActors() {
        return global.window_group.get_children()
            .filter(a => a instanceof Meta.WindowActor && a.meta_window);
    }

    // --- janelas do renderer ---

    _onWindowCreated(window) {
        if (!this.isRenderer(window) || this._windows.has(window))
            return;
        const actor = window.get_compositor_private();
        if (!actor)
            return;
        const entry = {actor, ready: false};
        this._windows.set(window, entry);

        // O que aparece é o clone no fundo; a janela de verdade fica invisível.
        actor.opacity = 0;
        window.stick();
        window.lower();

        window.connectObject(
            'notify::title', () => this._place(window),
            'notify::maximized-horizontally', () => this._place(window),
            'notify::maximized-vertically', () => this._place(window),
            'raised', () => window.lower(),
            'unmanaged', () => this._onWindowGone(window),
            this);
        actor.connectObject(
            'first-frame', () => {
                entry.ready = true;
                this._place(window);
                this._syncLayers();
            },
            // A animação de abertura do shell devolveria a opacidade.
            'notify::opacity', () => {
                if (actor.opacity !== 0)
                    actor.opacity = 0;
            }, this);
        this._place(window);
    }

    _onWindowGone(window) {
        const entry = this._windows.get(window);
        if (!entry)
            return;
        window.disconnectObject(this);
        entry.actor.disconnectObject(this);
        this._windows.delete(window);
        this._syncLayers();
    }

    _monitorOf(window) {
        const title = window.title ?? '';
        if (!title.startsWith(TITLE_PREFIX))
            return -1;
        const connector = title.slice(TITLE_PREFIX.length);
        return global.backend.get_monitor_manager()
            .get_monitor_for_connector(connector);
    }

    // O Mutter não deixa uma janela comum passar do tamanho da área útil, e
    // tela cheia esconderia o painel. Então a janela fica do maior tamanho que
    // cabe na área útil com a proporção do monitor, e o clone a amplia até a
    // tela inteira sem distorcer.
    _place(window) {
        const index = this._monitorOf(window);
        const monitor = Main.layoutManager.monitors[index];
        if (!monitor)
            return;
        if (window.is_maximized())
            window.unmaximize();
        const area = Main.layoutManager.getWorkAreaForMonitor(index);
        const scale = Math.min(
            area.width / monitor.width, area.height / monitor.height);
        const width = Math.floor(monitor.width * scale);
        const height = Math.floor(monitor.height * scale);
        const frame = window.get_frame_rect();
        if (frame.x !== area.x || frame.y !== area.y ||
            frame.width !== width || frame.height !== height)
            window.move_resize_frame(true, area.x, area.y, width, height);
    }

    _placeAll() {
        for (const window of this._windows.keys())
            this._place(window);
        this._syncLayers();
    }

    // A janela do renderer não aceita teclado; se o shell lhe der o foco,
    // devolve para a janela usada por último.
    _refuseFocus() {
        if (!this._windows.has(global.display.focus_window))
            return;
        const workspace = global.workspace_manager.get_active_workspace();
        const [next] = global.display.get_tab_list(Meta.TabList.NORMAL, workspace);
        if (next)
            next.focus(global.get_current_time());
        else
            global.display.unset_input_focus(global.get_current_time());
    }

    // --- camadas no fundo ---

    _injectBackgrounds() {
        const manager = this;
        this._injections.overrideMethod(
            Background.BackgroundManager.prototype, '_createBackgroundActor',
            original => function (...args) {
                const backgroundActor = original.apply(this, args);
                manager._addLayer(backgroundActor);
                return backgroundActor;
            });
    }

    _addLayer(backgroundActor) {
        const layer = new LiveLayer(backgroundActor);
        this._layers.add(layer);
        layer.connect('destroy', () => this._layers.delete(layer));
        layer.setSource(this._sourceFor(layer.monitorIndex));
    }

    _sourceFor(monitorIndex) {
        for (const [window, entry] of this._windows) {
            if (entry.ready && this._monitorOf(window) === monitorIndex)
                return entry.actor;
        }
        return null;
    }

    _syncLayers() {
        for (const layer of this._layers)
            layer.setSource(this._sourceFor(layer.monitorIndex));
    }

    // --- esconder das listas de janelas ---

    _hideFromShell() {
        const manager = this;
        const ours = window => manager._windows.has(window);
        const override = (prototype, name, wrap) =>
            this._injections.overrideMethod(prototype, name, wrap);

        override(Meta.Display.prototype, 'get_tab_list',
            original => function (...args) {
                return original.apply(this, args).filter(w => !ours(w));
            });
        override(Meta.Workspace.prototype, 'list_windows',
            original => function (...args) {
                return original.apply(this, args).filter(w => !ours(w));
            });
        override(Shell.Global.prototype, 'get_window_actors',
            original => function (...args) {
                return original.apply(this, args)
                    .filter(a => !ours(a.meta_window));
            });
        override(Shell.AppSystem.prototype, 'get_running',
            original => function (...args) {
                return original.apply(this, args)
                    .filter(app => !app.get_windows().some(ours));
            });
        override(Workspace.Workspace.prototype, '_isOverviewWindow',
            original => function (window) {
                return !ours(window) && original.call(this, window);
            });
        override(WorkspaceThumbnail.WorkspaceThumbnail.prototype, '_isOverviewWindow',
            original => function (actor) {
                return !ours(actor.get_meta_window()) &&
                    original.call(this, actor);
            });
    }

    destroy() {
        global.display.disconnectObject(this);
        Main.layoutManager.disconnectObject(this);
        this._injections.clear();
        for (const [window, entry] of this._windows) {
            window.disconnectObject(this);
            entry.actor.disconnectObject(this);
        }
        this._windows.clear();
        for (const layer of [...this._layers])
            layer.destroy();
        this._layers.clear();
    }
}
