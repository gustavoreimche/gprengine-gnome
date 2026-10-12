"""Galeria: escolhe o wallpaper e ajusta o comportamento.

Só conversa com o renderer por D-Bus; os ajustes vão direto para o GSettings,
que a extensão e o renderer observam.
"""

import json
import os
import sys

import gi

gi.require_version('Gdk', '4.0')
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
gi.require_version('GdkPixbuf', '2.0')
from gi.repository import Adw, Gdk, GdkPixbuf, Gio, GLib, Gtk  # noqa: E402

from . import APP_ID, GALLERY_ID, OBJECT_PATH, packages  # noqa: E402
from .settings import load_settings  # noqa: E402

THUMB_WIDTH = 256
THUMB_HEIGHT = 160

CSS = """
.wallpaper-card { padding: 6px; border-radius: 16px; }
.wallpaper-card picture, .wallpaper-card .placeholder { border-radius: 10px; }
.wallpaper-card .placeholder { background: alpha(currentColor, 0.08); }
.wallpaper-card.current { background: alpha(@accent_bg_color, 0.25); }
.wallpaper-card.current .name { font-weight: bold; }
.wallpaper-card.unavailable picture { opacity: 0.45; }
.wallpaper-card .soon {
  background: rgba(0, 0, 0, 0.65); color: white; border-radius: 99px;
  padding: 2px 10px; font-size: smaller;
}
"""

# (valor gravado no GSettings, rótulo)
SCALES = [(50, '50 %'), (75, '75 %'), (100, '100 %')]
FPS = [(30, '30 FPS'), (60, '60 FPS')]
GPUS = [('integrated', 'Integrada'), ('discrete', 'Dedicada (NVIDIA)')]
BATTERY = [('continue', 'Continuar'), ('limit', 'Limitar a 15 FPS'),
           ('pause', 'Pausar')]


class Card(Gtk.FlowBoxChild):
    def __init__(self, pkg, current):
        super().__init__()
        self.pkg = pkg
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.add_css_class('wallpaper-card')

        overlay = Gtk.Overlay(halign=Gtk.Align.CENTER)
        picture = self._thumbnail(pkg['thumbnail'])
        picture.set_size_request(THUMB_WIDTH, THUMB_HEIGHT)
        overlay.set_child(picture)

        badge = None
        if pkg['error']:
            badge = Gtk.Image(icon_name='dialog-warning-symbolic')
            badge.add_css_class('warning')
            self.set_tooltip_text('Não foi possível carregar. Clique para ver o erro.')
        elif pkg['unsupported']:
            badge = Gtk.Label(label='Em breve')
            badge.add_css_class('soon')
            self.set_tooltip_text(f'Wallpapers do tipo "{pkg["type"]}" ainda não são suportados.')
        elif current:
            badge = Gtk.Image(icon_name='object-select-symbolic')
            badge.add_css_class('accent')
        if badge:
            badge.set_halign(Gtk.Align.END)
            badge.set_valign(Gtk.Align.START)
            badge.set_margin_top(8)
            badge.set_margin_end(8)
            overlay.add_overlay(badge)
        box.append(overlay)

        name = Gtk.Label(label=pkg['name'], xalign=0, ellipsize=3)
        name.add_css_class('name')
        box.append(name)
        if pkg['author']:
            author = Gtk.Label(label=pkg['author'], xalign=0, ellipsize=3)
            author.add_css_class('dim-label')
            author.add_css_class('caption')
            box.append(author)

        if current:
            box.add_css_class('current')
        if pkg['error'] or pkg['unsupported']:
            box.add_css_class('unavailable')
        self.set_halign(Gtk.Align.CENTER)
        self.set_valign(Gtk.Align.START)
        self.set_child(box)

    def _thumbnail(self, path):
        # Carrega já no tamanho do cartão (em pixels físicos): o tamanho
        # natural de um Gtk.Picture é o da imagem, e a grade se orienta por
        # ele para decidir quantas colunas cabem.
        scale = self.get_scale_factor()
        try:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                path, THUMB_WIDTH * scale, THUMB_HEIGHT * scale, False)
        except GLib.Error:
            image = Gtk.Image(icon_name='image-missing-symbolic', pixel_size=48)
            image.add_css_class('placeholder')
            return image
        picture = Gtk.Picture.new_for_paintable(
            Gdk.Texture.new_for_pixbuf(pixbuf))
        picture.set_can_shrink(True)
        picture.set_content_fit(Gtk.ContentFit.COVER)
        return picture


class GalleryWindow(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title='PrimoEngine',
                         default_width=920, default_height=640)
        self.settings = load_settings()
        self.proxy = None
        self._current = ''

        self.stack = Adw.ViewStack()
        self.stack.add_titled_with_icon(
            self._build_wallpapers(), 'wallpapers', 'Wallpapers',
            'preferences-desktop-wallpaper-symbolic')
        self.stack.add_titled_with_icon(
            self._build_settings(), 'settings', 'Ajustes',
            'preferences-system-symbolic')

        header = Adw.HeaderBar()
        header.set_title_widget(Adw.ViewSwitcher(
            stack=self.stack, policy=Adw.ViewSwitcherPolicy.WIDE))

        add = Gtk.Button(icon_name='list-add-symbolic',
                         tooltip_text='Abrir a pasta dos meus wallpapers')
        add.connect('clicked', self._on_open_folder)
        header.pack_start(add)
        reload_button = Gtk.Button(icon_name='view-refresh-symbolic',
                                   tooltip_text='Recarregar wallpapers')
        reload_button.connect('clicked', lambda *_: self._call('Reload'))
        header.pack_start(reload_button)

        self.pause = Gtk.ToggleButton(
            icon_name='media-playback-pause-symbolic',
            tooltip_text='Pausar o wallpaper')
        self._pause_handler = self.pause.connect('toggled', self._on_pause)
        header.pack_end(self.pause)

        view = Adw.ToolbarView()
        view.add_top_bar(header)
        self.toasts = Adw.ToastOverlay(child=self.stack)
        view.set_content(self.toasts)
        self.set_content(view)

        Gio.DBusProxy.new_for_bus(
            Gio.BusType.SESSION, Gio.DBusProxyFlags.DO_NOT_AUTO_START, None,
            APP_ID, OBJECT_PATH, APP_ID, None, self._on_proxy)

    # --- páginas ---

    def _build_wallpapers(self):
        self.flow = Gtk.FlowBox(
            selection_mode=Gtk.SelectionMode.NONE, homogeneous=True,
            column_spacing=6, row_spacing=6, max_children_per_line=8,
            valign=Gtk.Align.START, margin_top=18, margin_bottom=18,
            margin_start=18, margin_end=18, activate_on_single_click=True)
        self.flow.connect('child-activated', self._on_card)
        scrolled = Gtk.ScrolledWindow(child=self.flow,
                                      hscrollbar_policy=Gtk.PolicyType.NEVER)

        self.offline = Adw.StatusPage(
            icon_name='preferences-desktop-wallpaper-symbolic',
            title='O PrimoEngine não está rodando',
            description='Ative a extensão PrimoEngine GNOME e entre de novo '
                        'na sessão.')
        self.empty = Adw.StatusPage(
            icon_name='folder-symbolic', title='Nenhum wallpaper',
            description='Use o botão + para abrir a pasta e criar o seu.')

        self.pages = Gtk.Stack()
        self.pages.add_named(scrolled, 'grid')
        self.pages.add_named(self.offline, 'offline')
        self.pages.add_named(self.empty, 'empty')
        self.pages.set_visible_child_name('offline')
        return self.pages

    def _combo(self, title, subtitle, key, options):
        """Linha de escolha ligada a uma chave do GSettings."""
        row = Adw.ComboRow(title=title, subtitle=subtitle)
        row.set_model(Gtk.StringList.new([label for _value, label in options]))
        values = [value for value, _label in options]
        is_int = isinstance(values[0], int)

        def read():
            return (self.settings.get_int(key) if is_int
                    else self.settings.get_string(key))

        def sync(*_):
            value = read()
            if value in values and row.get_selected() != values.index(value):
                row.set_selected(values.index(value))

        def write(*_):
            value = values[row.get_selected()]
            if value == read():
                return
            if is_int:
                self.settings.set_int(key, value)
            else:
                self.settings.set_string(key, value)

        sync()
        row.connect('notify::selected', write)
        self.settings.connect(f'changed::{key}', sync)
        return row

    def _build_settings(self):
        page = Adw.PreferencesPage()

        pause = Adw.PreferencesGroup(
            title='Pausa automática',
            description='Em tela cheia e com a tela desligada o wallpaper '
                        'sempre para.')
        covered = Adw.SwitchRow(
            title='Pausar quando coberto',
            subtitle='Para de desenhar quando as janelas escondem a área de '
                     'trabalho')
        self.settings.bind('pause-when-covered', covered, 'active',
                           Gio.SettingsBindFlags.DEFAULT)
        pause.add(covered)
        pause.add(self._combo('Na bateria', '', 'battery-mode', BATTERY))
        page.add(pause)

        performance = Adw.PreferencesGroup(title='Desempenho')
        performance.add(self._combo(
            'Escala de renderização',
            'Abaixo de 100 % o shader desenha menos pixels e a imagem é '
            'ampliada', 'render-scale', SCALES))
        performance.add(self._combo('Limite de quadros', '', 'fps-limit', FPS))
        self.gpu_row = self._combo(
            'Placa de vídeo',
            'A integrada gasta menos; trocar reinicia o wallpaper', 'gpu',
            GPUS)
        performance.add(self.gpu_row)
        page.add(performance)
        return page

    # --- D-Bus ---

    def _on_proxy(self, _source, result):
        try:
            self.proxy = Gio.DBusProxy.new_for_bus_finish(result)
        except GLib.Error as e:
            self.toast(f'Sem acesso ao barramento de sessão: {e.message}')
            return
        self.proxy.connect('g-signal', self._on_signal)
        self.proxy.connect('notify::g-name-owner', lambda *_: self.refresh())
        self.refresh()

    def _on_signal(self, _proxy, _sender, signal, _params):
        if signal == 'Changed':
            self.refresh()

    def _call(self, method, params=None, on_done=None):
        if not self.proxy or not self.proxy.get_name_owner():
            return

        def done(proxy, result):
            try:
                value = proxy.call_finish(result)
            except GLib.Error as e:
                Gio.DBusError.strip_remote_error(e)
                self.toast(e.message)
                return
            if on_done:
                on_done(value)

        self.proxy.call(method, params, Gio.DBusCallFlags.NO_AUTO_START,
                        -1, None, done)

    def refresh(self):
        if not self.proxy or not self.proxy.get_name_owner():
            self.pages.set_visible_child_name('offline')
            self.pause.set_sensitive(False)
            return
        self.pause.set_sensitive(True)
        self._call('Stats', on_done=self._on_stats)

    def _on_stats(self, value):
        stats = json.loads(value.unpack()[0])
        self._current = stats['current']
        if stats['gl_renderer']:
            # O que o driver diz, não o que foi pedido: se a dedicada não
            # subir, a extensão volta sozinha para a integrada.
            self.gpu_row.set_subtitle(f'Em uso: {stats["gl_renderer"]}')
        manual = 'manual' in stats['reasons']
        if self.pause.get_active() != manual:
            self.pause.handler_block(self._pause_handler)
            self.pause.set_active(manual)
            self.pause.handler_unblock(self._pause_handler)
        self._call('List', on_done=self._on_list)

    def _on_list(self, value):
        pkgs = json.loads(value.unpack()[0])
        self.flow.remove_all()
        for pkg in pkgs:
            self.flow.append(Card(pkg, pkg['id'] == self._current))
        self.pages.set_visible_child_name('grid' if pkgs else 'empty')

    # --- ações ---

    def toast(self, message):
        self.toasts.add_toast(Adw.Toast(title=message, timeout=4))

    def _on_card(self, _flow, card):
        pkg = card.pkg
        if pkg['unsupported']:
            self.toast(f'Wallpapers do tipo "{pkg["type"]}" ainda não são suportados.')
        elif pkg['error']:
            dialog = Adw.AlertDialog(
                heading=f'{pkg["name"]} não pôde ser carregado',
                body=pkg['error'])
            dialog.add_response('close', 'Fechar')
            dialog.add_response('retry', 'Tentar de novo')
            dialog.connect('response', lambda _d, response: response == 'retry'
                           and self._apply(pkg['id']))
            dialog.present(self)
        else:
            self._apply(pkg['id'])

    def _apply(self, pkg_id):
        self._call('Apply', GLib.Variant('(s)', (pkg_id,)))

    def _on_pause(self, button):
        self._call('SetPaused',
                   GLib.Variant('(bs)', (button.get_active(), 'manual')))

    def _on_open_folder(self, _button):
        os.makedirs(packages.USER_DIR, exist_ok=True)
        Gio.AppInfo.launch_default_for_uri(
            GLib.filename_to_uri(packages.USER_DIR, None), None)


class Gallery(Adw.Application):
    def __init__(self):
        super().__init__(application_id=GALLERY_ID,
                         flags=Gio.ApplicationFlags.DEFAULT_FLAGS)

    def do_startup(self):
        Adw.Application.do_startup(self)
        provider = Gtk.CssProvider()
        provider.load_from_string(CSS)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    def do_activate(self):
        window = self.get_active_window() or GalleryWindow(self)
        window.present()


def main():
    return Gallery().run(sys.argv)
