"""Renderer: uma janela por monitor desenhando o shader atual.

Não sabe nada sobre janelas de outros apps. Quem decide pausar é a extensão,
que chama SetPaused por D-Bus.
"""

import json
import os
import sys
import time

import cairo
import gi

gi.require_version('Gdk', '4.0')
gi.require_version('Gtk', '4.0')
gi.require_version('GdkPixbuf', '2.0')
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk  # noqa: E402

from . import APP_ID, OBJECT_PATH, SCHEMA_ID, gl, packages  # noqa: E402

INTERFACE_XML = f"""
<node>
  <interface name="{APP_ID}">
    <method name="Apply"><arg type="s" name="id" direction="in"/></method>
    <method name="Next"/>
    <method name="Previous"/>
    <method name="SetPaused">
      <arg type="b" name="paused" direction="in"/>
      <arg type="s" name="reason" direction="in"/>
    </method>
    <method name="SetPowerSaving">
      <arg type="b" name="enabled" direction="in"/>
    </method>
    <method name="Reload"/>
    <method name="List"><arg type="s" name="json" direction="out"/></method>
    <method name="Stats"><arg type="s" name="json" direction="out"/></method>
    <property name="Current" type="s" access="read"/>
    <property name="Paused" type="b" access="read"/>
    <signal name="Changed"/>
  </interface>
</node>
"""

POWER_SAVING_FPS = 15
THUMB_SIZE = (480, 300)
THUMB_TIME = 5.0
# Um salto maior que isso entre dois quadros é engasgo, não animação.
MAX_DELTA = 0.25


def load_settings():
    schema_dir = os.path.join(packages.REPO, 'schemas')
    try:
        source = Gio.SettingsSchemaSource.new_from_directory(
            schema_dir, Gio.SettingsSchemaSource.get_default(), False)
    except GLib.Error:
        source = Gio.SettingsSchemaSource.get_default()
    schema = source.lookup(SCHEMA_ID, True) if source else None
    if schema is None:
        raise SystemExit(
            f'Schema {SCHEMA_ID} não encontrado. Rode ./install.sh.')
    return Gio.Settings.new_full(schema, None, None)


class WallpaperWindow(Gtk.Window):
    def __init__(self, engine, monitor):
        super().__init__(application=engine, decorated=False,
                         title=f'primoengine:{monitor.get_connector()}')
        self.engine = engine
        self.monitor = monitor
        self.frames = 0
        self._program = None
        self._program_id = None
        self._target = gl.Target()
        self._vao = gl.c_uint(0)
        self._tick_id = 0
        self._next_render = None
        self._last_time = 0.0
        self.size = (0, 0)
        self.target_size = (0, 0)

        # Pequena de propósito: perto do tamanho da tela o Mutter a
        # maximizaria. Quem dá o tamanho final é a extensão.
        self.set_default_size(640, 400)
        self.set_focusable(False)
        # Alt+F4 ou "fechar" do shell não derrubam o wallpaper.
        self.connect('close-request', lambda *_: True)
        self.connect('realize', self._on_window_realize)

        self.area = Gtk.GLArea(auto_render=False, focusable=False)
        self.area.set_allowed_apis(Gdk.GLAPI.GL)
        self.area.set_required_version(3, 3)
        self.area.connect('realize', self._on_realize)
        self.area.connect('unrealize', self._on_unrealize)
        self.area.connect('render', self._on_render)
        self.area.connect('resize', self._on_resize)
        self.set_child(self.area)

    def _on_window_realize(self, _window):
        surface = self.get_surface()
        surface.connect('layout', lambda *_: self._pass_input_through())
        self._pass_input_through()

    def _pass_input_through(self):
        # Região de entrada vazia: cliques atravessam e chegam à área de
        # trabalho, como se a janela não existisse.
        self.get_surface().set_input_region(cairo.Region())

    # --- contexto GL ---

    def _on_realize(self, area):
        area.make_current()
        if area.get_error():
            self.engine.fail(f'OpenGL indisponível: {area.get_error().message}')
            return
        gl.glGenVertexArrays(1, gl.byref(self._vao))
        self.engine.on_window_realized(self)
        self.set_running(not self.engine.paused)

    def _on_unrealize(self, area):
        self.set_running(False)
        area.make_current()
        if area.get_error():
            return
        if self._program:
            self._program.destroy()
            self._program = None
        self._target.destroy()
        if self._vao.value:
            gl.glDeleteVertexArrays(1, gl.byref(self._vao))
            self._vao = gl.c_uint(0)

    def _on_resize(self, area, width, height):
        # Tamanho do framebuffer em pixels, já com a escala HiDPI.
        self.size = (width, height)
        area.queue_render()

    def make_current(self):
        if not self.area.get_realized():
            return False
        self.area.make_current()
        return self.area.get_error() is None

    # --- relógio de quadros ---

    def set_running(self, running):
        if running and not self._tick_id and self.area.get_realized():
            self._next_render = None
            self._tick_id = self.area.add_tick_callback(self._on_tick)
        elif not running and self._tick_id:
            self.area.remove_tick_callback(self._tick_id)
            self._tick_id = 0

    def _on_tick(self, area, clock):
        now = clock.get_frame_time()
        interval = 1_000_000 / self.engine.fps
        # Tolerância de 2 ms: o tick vem no ritmo do monitor, não no nosso.
        if self._next_render is None or now >= self._next_render - 2000:
            # Agenda a partir do horário previsto, não do real, para o atraso
            # de um quadro não se acumular nos seguintes.
            due = now if self._next_render is None else self._next_render
            self._next_render = max(due + interval, now)
            self.frames += 1
            self.engine.frames += 1
            area.queue_render()
        return GLib.SOURCE_CONTINUE

    # --- desenho ---

    def _sync_program(self):
        pkg = self.engine.current_package()
        wanted = pkg.id if pkg else None
        if wanted == self._program_id:
            return
        if self._program:
            self._program.destroy()
            self._program = None
        self._program_id = wanted
        if pkg:
            try:
                self._program = gl.Program(pkg.source())
            except (gl.ShaderError, OSError) as e:
                # Já foi validado em Apply; só chega aqui se o arquivo mudou.
                self.engine.report_error(pkg, str(e))

    def _on_render(self, area, _context):
        width, height = self.size
        # O GTK só ajusta o viewport ao redimensionar, e as miniaturas mexem
        # nele no mesmo contexto.
        gl.glViewport(0, 0, width, height)
        self._sync_program()
        if not self._program or width <= 0 or height <= 0:
            gl.glClearColor(0.0, 0.0, 0.0, 1.0)
            gl.glClear(gl.COLOR_BUFFER_BIT)
            return True

        now = self.engine.clock()
        delta = min(max(now - self._last_time, 0.0), MAX_DELTA)
        self._last_time = now
        scale = self.engine.render_scale / 100
        tw, th = max(1, round(width * scale)), max(1, round(height * scale))
        self.target_size = (tw, th)

        for cap in (gl.BLEND, gl.DEPTH_TEST, gl.SCISSOR_TEST):
            gl.glDisable(cap)
        gl.glBindVertexArray(self._vao)
        args = (now, delta, self.frames, self.engine.date())
        if (tw, th) == (width, height):
            self._program.draw(width, height, *args)
        else:
            screen = gl.bound_draw_framebuffer()
            self._target.ensure(tw, th)
            gl.glBindFramebuffer(gl.FRAMEBUFFER, self._target.fbo)
            gl.glViewport(0, 0, tw, th)
            self._program.draw(tw, th, *args)
            gl.glBindFramebuffer(gl.READ_FRAMEBUFFER, self._target.fbo)
            gl.glBindFramebuffer(gl.DRAW_FRAMEBUFFER, screen)
            gl.glViewport(0, 0, width, height)
            gl.glBlitFramebuffer(0, 0, tw, th, 0, 0, width, height,
                                 gl.COLOR_BUFFER_BIT, gl.LINEAR)
            gl.glBindFramebuffer(gl.FRAMEBUFFER, screen)
        gl.glBindVertexArray(0)
        gl.glUseProgram(0)
        return True

    def render_thumbnail(self, program, path):
        """Um quadro parado em THUMB_TIME, gravado como PNG."""
        width, height = THUMB_SIZE
        target = gl.Target()
        try:
            target.ensure(width, height)
            gl.glViewport(0, 0, width, height)
            gl.glBindVertexArray(self._vao)
            program.draw(width, height, THUMB_TIME, 1 / 30, 150,
                         self.engine.date())
            gl.glBindVertexArray(0)
            gl.glUseProgram(0)
            data = gl.read_rgba(width, height)
        finally:
            gl.glBindFramebuffer(gl.FRAMEBUFFER, 0)
            target.destroy()
        pixbuf = GdkPixbuf.Pixbuf.new_from_bytes(
            GLib.Bytes.new(data), GdkPixbuf.Colorspace.RGB, True, 8,
            width, height, width * 4)
        # O GL entrega de baixo para cima.
        pixbuf = pixbuf.flip(False)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = f'{path}.tmp'
        pixbuf.savev(tmp, 'png', [], [])
        os.replace(tmp, path)


class Engine(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID,
                         flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.packages = []
        self.current = ''
        self.reasons = set()
        self.power_saving = False
        self.frames = 0
        self.windows = {}
        self.gl_renderer = ''
        self.gl_version = ''
        self._elapsed = 0.0
        self._resumed_at = time.monotonic()
        self._validated = False
        self._registration = 0
        self._fps_window = (time.monotonic(), 0, 0.0)

    # --- ciclo de vida ---

    def do_startup(self):
        Gtk.Application.do_startup(self)
        self.settings = load_settings()
        self.settings.connect('changed::current', self._on_current_setting)
        self.settings.connect('changed::render-scale', self._on_draw_setting)
        self.settings.connect('changed::fps-limit', self._on_draw_setting)
        self.packages = packages.discover()
        self.current = self.settings.get_string('current')

        node = Gio.DBusNodeInfo.new_for_xml(INTERFACE_XML)
        self._registration = self.get_dbus_connection().register_object(
            OBJECT_PATH, node.interfaces[0], self._on_method_call,
            self._on_get_property, None)

        self.hold()
        monitors = Gdk.Display.get_default().get_monitors()
        monitors.connect('items-changed', lambda *_: self._sync_monitors())
        self._sync_monitors()

    def do_activate(self):
        pass

    def fail(self, message):
        print(f'primoengine: {message}', file=sys.stderr)
        self.quit()

    def _sync_monitors(self):
        monitors = Gdk.Display.get_default().get_monitors()
        present = {}
        for i in range(monitors.get_n_items()):
            monitor = monitors.get_item(i)
            if monitor.get_connector():
                present[monitor.get_connector()] = monitor
        for connector in list(self.windows):
            if connector not in present:
                self.windows.pop(connector).destroy()
        for connector, monitor in present.items():
            if connector not in self.windows:
                window = WallpaperWindow(self, monitor)
                self.windows[connector] = window
                window.present()

    # --- estado ---

    @property
    def paused(self):
        return bool(self.reasons)

    @property
    def fps(self):
        limit = self.settings.get_int('fps-limit')
        return min(limit, POWER_SAVING_FPS) if self.power_saving else limit

    @property
    def render_scale(self):
        return self.settings.get_int('render-scale')

    def clock(self):
        """Segundos de animação. Não anda enquanto pausado."""
        if self.paused:
            return self._elapsed
        return self._elapsed + time.monotonic() - self._resumed_at

    @staticmethod
    def date():
        t = time.localtime()
        return (float(t.tm_year), float(t.tm_mon - 1), float(t.tm_mday),
                t.tm_hour * 3600.0 + t.tm_min * 60.0 + t.tm_sec)

    def package(self, pkg_id):
        return next((p for p in self.packages if p.id == pkg_id), None)

    def current_package(self):
        pkg = self.package(self.current)
        return pkg if pkg and pkg.usable else None

    def usable(self):
        return [p for p in self.packages if p.usable]

    def set_paused(self, paused, reason):
        was = self.paused
        if paused:
            self.reasons.add(reason)
        else:
            self.reasons.discard(reason)
        if was == self.paused:
            return
        if self.paused:
            self._elapsed += time.monotonic() - self._resumed_at
        else:
            self._resumed_at = time.monotonic()
        for window in self.windows.values():
            window.set_running(not self.paused)
        self._emit_changed(['Paused'])

    def set_current(self, pkg_id):
        if pkg_id == self.current:
            return
        self.current = pkg_id
        if self.settings.get_string('current') != pkg_id:
            self.settings.set_string('current', pkg_id)
        self.redraw()
        self._emit_changed(['Current'])

    def redraw(self):
        for window in self.windows.values():
            window.area.queue_render()

    def report_error(self, pkg, message):
        pkg.error = message
        fallback = next((p for p in self.usable()), None)
        GLib.idle_add(self.set_current, fallback.id if fallback else '')

    def apply(self, pkg_id):
        pkg = self.package(pkg_id)
        if pkg is None:
            raise ValueError(f'wallpaper {pkg_id!r} não existe')
        if pkg.unsupported:
            raise ValueError(f'tipo {pkg.type!r} ainda não suportado')
        if pkg.error and pkg.type != 'glsl':
            raise ValueError(pkg.error)
        # Recompila sempre: o autor pode ter acabado de corrigir o arquivo.
        self._check(pkg)
        if pkg.error:
            self._emit_changed([])
            raise ValueError(pkg.error)
        for window in self.windows.values():
            window._program_id = None
        if pkg_id == self.current:
            self.redraw()
            self._emit_changed([])
        else:
            self.set_current(pkg_id)

    def step(self, offset):
        usable = self.usable()
        if not usable:
            return
        ids = [p.id for p in usable]
        index = ids.index(self.current) if self.current in ids else -offset
        self.set_current(ids[(index + offset) % len(ids)])

    def reload(self):
        self.packages = packages.discover()
        self._validated = False
        for window in self.windows.values():
            window._program_id = None
        self._validate()
        self.redraw()

    # --- validação e miniaturas ---

    def _primary(self):
        return next((w for w in self.windows.values()
                     if w.area.get_realized()), None)

    def _check(self, pkg, thumbnail=False):
        """Compila o pacote no contexto de uma janela e grava o resultado em
        pkg.error. Sem janela realizada ainda, não faz nada."""
        window = self._primary()
        if not window or not pkg.entry or not window.make_current():
            return
        try:
            program = gl.Program(pkg.source())
        except (gl.ShaderError, OSError) as e:
            pkg.error = str(e)
            return
        pkg.error = ''
        try:
            if thumbnail and not pkg.thumbnail:
                path = os.path.join(packages.THUMB_DIR, f'{pkg.id}.png')
                if (not os.path.exists(path) or
                        os.path.getmtime(path) < os.path.getmtime(pkg.entry)):
                    window.render_thumbnail(program, path)
                pkg.thumbnail = path
        except (GLib.Error, OSError, RuntimeError) as e:
            print(f'primoengine: miniatura de {pkg.id}: {e}', file=sys.stderr)
        finally:
            program.destroy()

    def on_window_realized(self, window):
        if not self.gl_renderer:
            self.gl_renderer = gl.gl_string(gl.RENDERER)
            self.gl_version = gl.gl_string(gl.VERSION)
        self._validate()

    def _validate(self):
        if self._validated or not self._primary():
            return
        self._validated = True
        for pkg in self.packages:
            if pkg.type == 'glsl' and pkg.entry:
                self._check(pkg, thumbnail=True)
        if not self.current_package():
            fallback = next(iter(self.usable()), None)
            self.current = fallback.id if fallback else ''
        self.redraw()
        self._emit_changed(['Current'])

    # --- GSettings ---

    def _on_current_setting(self, settings, _key):
        wanted = settings.get_string('current')
        if wanted == self.current:
            return
        try:
            self.apply(wanted)
        except ValueError as e:
            print(f'primoengine: {e}', file=sys.stderr)

    def _on_draw_setting(self, *_):
        self.redraw()

    # --- D-Bus ---

    def _emit_changed(self, properties):
        connection = self.get_dbus_connection()
        if not connection or not self._registration:
            return
        values = {'Current': GLib.Variant('s', self.current),
                  'Paused': GLib.Variant('b', self.paused)}
        changed = {name: values[name] for name in properties}
        if changed:
            connection.emit_signal(
                None, OBJECT_PATH, 'org.freedesktop.DBus.Properties',
                'PropertiesChanged',
                GLib.Variant('(sa{sv}as)', (APP_ID, changed, [])))
        connection.emit_signal(None, OBJECT_PATH, APP_ID, 'Changed', None)

    def _measured_fps(self):
        started, frames, last = self._fps_window
        now = time.monotonic()
        if now - started >= 1.0:
            last = (self.frames - frames) / (now - started)
            self._fps_window = (now, self.frames, last)
        return round(last, 1)

    def stats(self):
        return {
            'frames': self.frames,
            'time': round(self.clock(), 3),
            'fps': self._measured_fps(),
            'fps_limit': self.fps,
            'paused': self.paused,
            'reasons': sorted(self.reasons),
            'power_saving': self.power_saving,
            'current': self.current,
            'render_scale': self.render_scale,
            'gl_renderer': self.gl_renderer,
            'gl_version': self.gl_version,
            'windows': [{'title': w.get_title(), 'size': w.size,
                         'target': w.target_size, 'frames': w.frames}
                        for w in self.windows.values()],
        }

    def _on_method_call(self, _conn, _sender, _path, _iface, method, params,
                        invocation):
        try:
            result = None
            if method == 'Apply':
                self.apply(params.unpack()[0])
            elif method == 'Next':
                self.step(1)
            elif method == 'Previous':
                self.step(-1)
            elif method == 'SetPaused':
                self.set_paused(*params.unpack())
            elif method == 'SetPowerSaving':
                self.power_saving = params.unpack()[0]
            elif method == 'Reload':
                self.reload()
            elif method == 'List':
                result = json.dumps([p.to_dict() for p in self.packages])
            elif method == 'Stats':
                result = json.dumps(self.stats())
            invocation.return_value(
                GLib.Variant('(s)', (result,)) if result is not None else None)
        except ValueError as e:
            invocation.return_dbus_error(f'{APP_ID}.Error', str(e))

    def _on_get_property(self, _conn, _sender, _path, _iface, name):
        if name == 'Current':
            return GLib.Variant('s', self.current)
        if name == 'Paused':
            return GLib.Variant('b', self.paused)
        return None


def main():
    return Engine().run(sys.argv)
