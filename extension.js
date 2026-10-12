import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import {PauseController} from './shell/pause.js';
import {RendererProcess} from './shell/process.js';
import {WallpaperManager} from './shell/wallpaper.js';

export default class GprEngineExtension extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._process = new RendererProcess(this.path, this._settings);
        this._wallpaper = new WallpaperManager(this._process, this._settings);
        this._pause = new PauseController(this._settings,
            window => this._wallpaper.isRenderer(window));
    }

    disable() {
        this._pause?.destroy();
        this._pause = null;
        this._wallpaper?.destroy();
        this._wallpaper = null;
        // Encerra o renderer também ao bloquear a tela: o fundo não aparece
        // lá, então não há por que desenhar.
        this._process?.destroy();
        this._process = null;
        this._settings = null;
    }
}
