import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import * as Background from 'resource:///org/gnome/shell/ui/background.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as Workspace from 'resource:///org/gnome/shell/ui/workspace.js';
import * as WorkspaceThumbnail from 'resource:///org/gnome/shell/ui/workspaceThumbnail.js';
import {InjectionManager} from 'resource:///org/gnome/shell/extensions/extension.js';

import {RoundedClipEffect} from './roundedClip.js';

const TITLE_PREFIX = 'gprengine:';
const FADE_MS = 400;

// Clone que nunca é descartado pelo recorte de repintura. O volume de pintura
// de um Clutter.Clone é o da origem, sem a ampliação; com ele o compositor
// pode concluir que o clone está fora da área a repintar e não desenhá-lo no
// monitor, embora ele apareça em capturas de tela (que repintam tudo).
const WholeClone = GObject.registerClass(
class GprEngineWholeClone extends Clutter.Clone {
    vfunc_get_paint_volume(_volume) {
        return false;
    }
});

// Camada viva dentro de um Meta.BackgroundActor: um clone da janela do
// renderer. Cada fundo que o shell cria (área de trabalho, miniaturas da visão
// geral, troca de workspace) ganha a sua.
const LiveLayer = GObject.registerClass(
class LiveLayer extends Clutter.Actor {
    _init(backgroundActor, settings) {
        this._settings = settings;
        // clip_to_allocation: sem ele o volume de pintura seria o da janela
        // de origem do clone, não o nosso, e o recorte arredondado erraria a
        // conta.
        super._init({opacity: 0, clip_to_allocation: true});
        this.monitorIndex = backgroundActor.monitor;
        this.add_constraint(new Clutter.BindConstraint({
            source: backgroundActor,
            coordinate: Clutter.BindCoordinate.SIZE,
        }));
        this._clone = new WholeClone();
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
        this._settings.connectObject(
            'changed::force-offscreen', () => this._syncClip(), this);
        this.connect('notify::size', () => this._syncClip());
        this.connect('destroy', () => {
            this._content.disconnectObject(this);
            this._settings.disconnectObject(this);
        });
        this._syncClip();
    }

    _syncClip() {
        const radius = this._content.rounded_clip_radius;
        const forced = this._settings.get_boolean('force-offscreen');
        this._clip.enabled = radius > 0 || forced;
        if (!this._clip.enabled)
            return;
        if (radius <= 0) {
            // Sem recorte: o efeito só está ligado para desenhar via textura.
            this._clip.setClip(this.width, this.height,
                [0, 0, this.width, this.height], 0);
            return;
        }
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

    // A origem ganhou um quadro novo: repinta, sem depender de o Clutter
    // repassar o dano de uma janela invisível aos clones dela.
    redraw() {
        this._clone.queue_redraw();
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

// O Mutter não desenha a parte de uma janela que está atrás de outra, e esse
// recorte valeria também para o clone no fundo: sobraria um buraco no
// wallpaper atrás de cada janela aberta. Atores com efeito ficam fora dessa
// otimização; este efeito não faz mais nada.
const KeepWholeEffect = GObject.registerClass(
class GprEngineKeepWholeEffect extends Clutter.Effect {});

// Põe as janelas do renderer na camada de fundo e as esconde de tudo que
// lista janelas (Alt+Tab, visão geral, docks).
export class WallpaperManager {
    constructor(process, settings) {
        this._process = process;
        this._settings = settings;
        this._windows = new Map();
        this._layers = new Set();
        this._refuseId = 0;
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
        actor.add_effect_with_name('gprengine-keep-whole', new KeepWholeEffect());
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
            },
            'damaged', () => {
                for (const layer of this._layers) {
                    if (layer.mapped)
                        layer.redraw();
                }
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

    // Índice do monitor -> conector, para cada janela do renderer.
    connectors() {
        const found = new Map();
        for (const window of this._windows.keys()) {
            const index = this._monitorOf(window);
            if (index >= 0)
                found.set(index, (window.title ?? '').slice(TITLE_PREFIX.length));
        }
        return found;
    }

    _monitorOf(window) {
        const title = window.title ?? '';
        if (!title.startsWith(TITLE_PREFIX))
            return -1;
        const connector = title.slice(TITLE_PREFIX.length);
        return global.backend.get_monitor_manager()
            .get_monitor_for_connector(connector);
    }

    // A janela tem exatamente o tamanho do monitor, para o shader ser
    // desenhado pixel a pixel: menor que isso, o clone teria de ampliar a
    // imagem e ela perderia definição. Tela cheia esconderia o painel, e o
    // Mutter não deixa uma janela comum cobrir o painel; então ela começa no
    // canto da área útil e a sobra fica para fora da tela. Não faz diferença:
    // a janela é invisível e o clone mostra a textura inteira.
    _place(window) {
        const index = this._monitorOf(window);
        const monitor = Main.layoutManager.monitors[index];
        if (!monitor)
            return;
        if (window.is_maximized())
            window.unmaximize();
        const area = Main.layoutManager.getWorkAreaForMonitor(index);
        const frame = window.get_frame_rect();
        if (frame.x !== area.x || frame.y !== area.y ||
            frame.width !== monitor.width || frame.height !== monitor.height) {
            window.move_resize_frame(
                true, area.x, area.y, monitor.width, monitor.height);
        }
    }

    _placeAll() {
        for (const window of this._windows.keys())
            this._place(window);
        this._syncLayers();
    }

    // A janela do renderer não aceita teclado; se o shell lhe der o foco,
    // devolve para a janela usada por último. Espera o shell ficar ocioso:
    // o foco costuma chegar no meio do fechamento de outra janela, que ainda
    // está na lista e não pode mais ser focada.
    _refuseFocus() {
        if (this._refuseId || !this._windows.has(global.display.focus_window))
            return;
        this._refuseId = GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
            this._refuseId = 0;
            if (!this._windows.has(global.display.focus_window))
                return GLib.SOURCE_REMOVE;
            const workspace = global.workspace_manager.get_active_workspace();
            const [next] = global.display.get_tab_list(
                Meta.TabList.NORMAL, workspace);
            if (next)
                next.focus(global.get_current_time());
            else
                global.display.unset_input_focus(global.get_current_time());
            return GLib.SOURCE_REMOVE;
        });
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
        const layer = new LiveLayer(backgroundActor, this._settings);
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
        if (this._refuseId) {
            GLib.source_remove(this._refuseId);
            this._refuseId = 0;
        }
        global.display.disconnectObject(this);
        Main.layoutManager.disconnectObject(this);
        this._injections.clear();
        for (const [window, entry] of this._windows) {
            window.disconnectObject(this);
            entry.actor.disconnectObject(this);
            entry.actor.remove_effect_by_name('gprengine-keep-whole');
        }
        this._windows.clear();
        for (const layer of [...this._layers])
            layer.destroy();
        this._layers.clear();
    }
}
