import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

const MAX_RESTARTS = 3;
// Rodou esse tempo sem cair: a próxima queda volta a contar do zero.
const STABLE_SECONDS = 60;
// Caiu antes disso com a GPU dedicada: a culpa é do offload, não do renderer.
const OFFLOAD_GRACE_SECONDS = 10;
const NVIDIA_EGL_VENDOR = '/usr/share/glvnd/egl_vendor.d/10_nvidia.json';

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
        // O que fazer quando o processo atual sair: 'crash' (religar com
        // espera), 'restart' (religar já) ou 'stop'.
        this._onExitDo = 'crash';
        this._offloadFailed = false;
        this.pid = 0;

        this._settings.connectObject('changed::gpu', () => {
            this._offloadFailed = false;
            this.restart();
        }, this);
        this._spawn();
    }

    get _offload() {
        return this._settings.get_string('gpu') === 'discrete' &&
            !this._offloadFailed;
    }

    _spawn() {
        const launcher = new Gio.SubprocessLauncher(
            {flags: Gio.SubprocessFlags.NONE});
        launcher.setenv('GDK_BACKEND', 'wayland', true);
        this._spawnedWithOffload = this._offload;
        if (this._spawnedWithOffload) {
            launcher.setenv('__NV_PRIME_RENDER_OFFLOAD', '1', true);
            launcher.setenv('__GLX_VENDOR_LIBRARY_NAME', 'nvidia', true);
            launcher.setenv('__VK_LAYER_NV_optimus', 'NVIDIA_only', true);
            // No Wayland o GTK usa EGL, e quem escolhe o driver ali é o GLVND.
            if (GLib.file_test(NVIDIA_EGL_VENDOR, GLib.FileTest.EXISTS)) {
                launcher.setenv('__EGL_VENDOR_LIBRARY_FILENAMES',
                    NVIDIA_EGL_VENDOR, true);
            }
        }

        let proc;
        try {
            proc = launcher.spawnv([this._binary]);
        } catch (e) {
            console.error(`PrimoEngine: não consegui iniciar o renderer: ${e.message}`);
            return;
        }
        this._proc = proc;
        this._onExitDo = 'crash';
        this.pid = Number(proc.get_identifier());
        this._startedAt = GLib.get_monotonic_time();
        proc.wait_async(null, () => this._onExit(proc));
    }

    _onExit(proc) {
        if (proc !== this._proc)
            return;
        const wanted = this._onExitDo;
        this._proc = null;
        this.pid = 0;
        if (this._destroyed || wanted === 'stop')
            return;
        if (wanted === 'restart') {
            this._spawn();
            return;
        }

        const ran = (GLib.get_monotonic_time() - this._startedAt) / 1e6;
        if (this._spawnedWithOffload && ran < OFFLOAD_GRACE_SECONDS) {
            console.warn('PrimoEngine: o renderer não subiu na GPU dedicada; ' +
                'voltando para a integrada.');
            this._offloadFailed = true;
            this._spawn();
            return;
        }
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

    _clearRetry() {
        if (this._retryId) {
            GLib.source_remove(this._retryId);
            this._retryId = 0;
        }
    }

    // O processo novo só sobe depois que o antigo sair: enquanto o antigo
    // segura o nome no D-Bus, um segundo renderer se dá por duplicado e sai.
    restart() {
        this._clearRetry();
        this._restarts = 0;
        if (this._proc) {
            this._onExitDo = 'restart';
            this._proc.send_signal(15);
        } else {
            this._spawn();
        }
    }

    destroy() {
        this._destroyed = true;
        this._settings.disconnectObject(this);
        this._clearRetry();
        this._proc?.send_signal(15);
        this._proc = null;
        this.pid = 0;
    }
}
