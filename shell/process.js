import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

const MAX_RESTARTS = 3;
// Rodou esse tempo sem cair: a próxima queda volta a contar do zero.
const STABLE_SECONDS = 60;

// Sobe o renderer e o religa se ele cair, com intervalo crescente. Depois de
// MAX_RESTARTS quedas seguidas desiste: fica o fundo estático do GNOME.
export class RendererProcess {
    constructor(extensionPath, settings) {
        this._binary = GLib.build_filenamev(
            [extensionPath, 'bin', 'primoengine-renderer']);
        this._settings = settings;
        this._proc = null;
        this._restarts = 0;
        this._startedAt = 0;
        this._retryId = 0;
        this._destroyed = false;
        this.pid = 0;

        this._settings.connectObject('changed::gpu', () => this.restart(), this);
        this._spawn();
    }

    _spawn() {
        const launcher = new Gio.SubprocessLauncher(
            {flags: Gio.SubprocessFlags.NONE});
        launcher.setenv('GDK_BACKEND', 'wayland', true);
        if (this._settings.get_string('gpu') === 'discrete') {
            launcher.setenv('__NV_PRIME_RENDER_OFFLOAD', '1', true);
            launcher.setenv('__GLX_VENDOR_LIBRARY_NAME', 'nvidia', true);
            launcher.setenv('__VK_LAYER_NV_optimus', 'NVIDIA_only', true);
            launcher.setenv('DRI_PRIME', '1', true);
        }

        let proc;
        try {
            proc = launcher.spawnv([this._binary]);
        } catch (e) {
            console.error(`PrimoEngine: não consegui iniciar o renderer: ${e.message}`);
            return;
        }
        this._proc = proc;
        this.pid = Number(proc.get_identifier());
        this._startedAt = GLib.get_monotonic_time();
        proc.wait_async(null, () => this._onExit(proc));
    }

    _onExit(proc) {
        // Saída de um processo que já foi trocado por outro, ou pedida por nós.
        if (proc !== this._proc)
            return;
        this._proc = null;
        this.pid = 0;
        if (this._destroyed)
            return;

        const ran = (GLib.get_monotonic_time() - this._startedAt) / 1e6;
        if (ran >= STABLE_SECONDS)
            this._restarts = 0;
        if (this._restarts >= MAX_RESTARTS) {
            console.error('PrimoEngine: o renderer caiu vezes demais; desisti.');
            return;
        }
        this._restarts++;
        this._retryId = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT, 2 ** this._restarts, () => {
                this._retryId = 0;
                this._spawn();
                return GLib.SOURCE_REMOVE;
            });
    }

    _kill() {
        const proc = this._proc;
        this._proc = null;
        this.pid = 0;
        proc?.send_signal(15);
    }

    restart() {
        if (this._retryId) {
            GLib.source_remove(this._retryId);
            this._retryId = 0;
        }
        this._kill();
        this._restarts = 0;
        this._spawn();
    }

    destroy() {
        this._destroyed = true;
        this._settings.disconnectObject(this);
        if (this._retryId) {
            GLib.source_remove(this._retryId);
            this._retryId = 0;
        }
        this._kill();
    }
}
