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
        self._check = None
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
        else:
            badge = Gtk.Image(icon_name='object-select-symbolic')
            badge.add_css_class('accent')
            self._check = badge
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

        self._box = box
        self.set_current(current)
        if pkg['error'] or pkg['unsupported']:
            box.add_css_class('unavailable')
        self.set_halign(Gtk.Align.CENTER)
        self.set_valign(Gtk.Align.START)
        self.set_child(box)

    def set_current(self, current):
        if self._check:
            self._check.set_visible(current)
        if current and self._check:
            self._box.add_css_class('current')
        else:
            self._box.remove_css_class('current')

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
        super().__init__(application=app, title='GprEngine',
                         default_width=920, default_height=640)
        self.settings = load_settings()
        self.proxy = None
        self._current = ''
        self._pkgs = None
        self._list_rows = {}
        self._list_pkgs = None

        self.stack = Adw.ViewStack()
        self.stack.add_titled_with_icon(
            self._build_wallpapers(), 'wallpapers', 'Wallpapers',
            'preferences-desktop-wallpaper-symbolic')
        self.stack.add_titled_with_icon(
            self._build_lists(), 'lists', 'Listas', 'view-list-symbolic')
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
        scrolled = self.scrolled = Gtk.ScrolledWindow(
            child=self.flow, hscrollbar_policy=Gtk.PolicyType.NEVER)

        self.offline = Adw.StatusPage(
            icon_name='preferences-desktop-wallpaper-symbolic',
            title='O GprEngine não está rodando',
            description='Ative a extensão GprEngine GNOME e entre de novo '
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

    def _build_speed(self):
        group = Adw.PreferencesGroup(title='Animação')
        row = Adw.ActionRow(
            title='Velocidade',
            subtitle='Vale para todos os wallpapers e muda na hora')

        adjustment = Gtk.Adjustment(lower=0.1, upper=3.0, step_increment=0.05,
                                    page_increment=0.25)
        self.settings.bind('speed', adjustment, 'value',
                           Gio.SettingsBindFlags.DEFAULT)
        scale = Gtk.Scale(adjustment=adjustment, draw_value=False,
                          hexpand=True, valign=Gtk.Align.CENTER)
        scale.set_size_request(260, -1)
        for mark in (0.5, 1.0, 2.0):
            scale.add_mark(mark, Gtk.PositionType.BOTTOM, None)

        value = Gtk.Label(width_chars=5, xalign=1)
        value.add_css_class('numeric')

        def show(*_):
            text = f'{adjustment.get_value():.2f}'.replace('.', ',')
            value.set_label(f'{text}×')

        adjustment.connect('value-changed', show)
        show()

        reset = Gtk.Button(icon_name='edit-undo-symbolic',
                           tooltip_text='Voltar à velocidade original',
                           valign=Gtk.Align.CENTER)
        reset.add_css_class('flat')
        reset.connect('clicked', lambda *_: adjustment.set_value(1.0))

        row.add_suffix(scale)
        row.add_suffix(value)
        row.add_suffix(reset)
        group.add(row)
        return group

    # --- listas ---

    def _lists(self):
        return self.settings.get_value('playlists').unpack()

    def _set_lists(self, lists):
        self.settings.set_value('playlists', GLib.Variant('a{sas}', lists))

    def _build_lists(self):
        page = Adw.PreferencesPage()

        auto = Adw.PreferencesGroup(
            title='Troca automática',
            description='Escolha uma lista para o wallpaper ir trocando '
                        'sozinho.')
        self.active_row = Adw.ComboRow(title='Lista em uso')
        self.active_row.connect('notify::selected', self._on_active_selected)
        auto.add(self.active_row)

        interval = Adw.SpinRow.new_with_range(1, 720, 1)
        interval.set_title('Trocar a cada')
        interval.set_subtitle('Minutos')
        interval.set_value(self.settings.get_int('playlist-interval') / 60)
        interval.connect('notify::value', lambda row, _p: self.settings.set_int(
            'playlist-interval', int(row.get_value()) * 60))
        auto.add(interval)

        shuffle = Adw.SwitchRow(title='Ordem aleatória')
        self.settings.bind('playlist-shuffle', shuffle, 'active',
                           Gio.SettingsBindFlags.DEFAULT)
        auto.add(shuffle)
        page.add(auto)

        self.lists_group = Adw.PreferencesGroup(
            title='Minhas listas',
            description='Abra uma lista e marque os wallpapers que fazem '
                        'parte dela.')
        self.new_list = Adw.EntryRow(title='Nova lista', show_apply_button=True)
        self.new_list.connect('apply', self._on_new_list)
        self.lists_group.add(self.new_list)
        page.add(self.lists_group)

        self.settings.connect('changed::playlists', lambda *_: self._sync_lists())
        self.settings.connect('changed::playlist-active',
                              lambda *_: self._sync_active())
        self._sync_lists()
        return page

    def _sync_active(self):
        names = [''] + list(self._lists())
        active = self.settings.get_string('playlist-active')
        index = names.index(active) if active in names else 0
        if self.active_row.get_selected() != index:
            self.active_row.set_selected(index)

    def _on_active_selected(self, row, _pspec):
        names = [''] + list(self._lists())
        index = row.get_selected()
        if index >= len(names):
            return
        if names[index] != self.settings.get_string('playlist-active'):
            self.settings.set_string('playlist-active', names[index])

    def _sync_lists(self):
        lists = self._lists()
        pkgs = [(p['id'], p['name']) for p in self._pkgs or []
                if not p['error'] and not p['unsupported']]
        if list(lists) != list(self._list_rows) or pkgs != self._list_pkgs:
            # Mudou o conjunto de listas ou de wallpapers: refaz as linhas.
            # Fora isso só os marcadores mudam, e a lista aberta fica aberta.
            for row, _checks in self._list_rows.values():
                self.lists_group.remove(row)
            self._list_rows = {}
            self._list_pkgs = pkgs
            for name in lists:
                self._list_rows[name] = self._build_list_row(name, pkgs)
                self.lists_group.add(self._list_rows[name][0])
            self.active_row.set_model(
                Gtk.StringList.new(['Nenhuma'] + list(lists)))
            self._sync_active()
        for name, (row, checks) in self._list_rows.items():
            ids = lists[name]
            known = [i for i in ids if i in checks]
            row.set_subtitle('Vazia' if not known else
                             '1 wallpaper' if len(known) == 1 else
                             f'{len(known)} wallpapers')
            for pkg_id, check in checks.items():
                if check.get_active() != (pkg_id in ids):
                    check.set_active(pkg_id in ids)

    def _build_list_row(self, name, pkgs):
        row = Adw.ExpanderRow(title=GLib.markup_escape_text(name))
        delete = Gtk.Button(icon_name='user-trash-symbolic',
                            tooltip_text='Apagar esta lista',
                            valign=Gtk.Align.CENTER)
        delete.add_css_class('flat')
        delete.connect('clicked', lambda *_: self._delete_list(name))
        row.add_suffix(delete)
        checks = {}
        for pkg_id, pkg_name in pkgs:
            check = Gtk.CheckButton(valign=Gtk.Align.CENTER)
            check.connect('toggled', self._on_list_check, name, pkg_id)
            item = Adw.ActionRow(title=GLib.markup_escape_text(pkg_name),
                                 activatable_widget=check)
            item.add_prefix(check)
            row.add_row(item)
            checks[pkg_id] = check
        return row, checks

    def _on_list_check(self, check, name, pkg_id):
        lists = self._lists()
        ids = lists.get(name)
        if ids is None or check.get_active() == (pkg_id in ids):
            return
        if check.get_active():
            ids.append(pkg_id)
        else:
            ids.remove(pkg_id)
        self._set_lists(lists)

    def _on_new_list(self, entry):
        name = entry.get_text().strip()
        lists = self._lists()
        if not name:
            return
        if name in lists:
            self.toast(f'Já existe uma lista chamada "{name}".')
            return
        lists[name] = []
        entry.set_text('')
        self._set_lists(lists)
        self._list_rows[name][0].set_expanded(True)

    def _delete_list(self, name):
        lists = self._lists()
        lists.pop(name, None)
        if self.settings.get_string('playlist-active') == name:
            self.settings.set_string('playlist-active', '')
        self._set_lists(lists)

    def _build_settings(self):
        page = Adw.PreferencesPage()
        page.add(self._build_speed())

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
        if pkgs == self._pkgs:
            # Só o wallpaper em uso mudou: marcar no lugar, sem refazer a
            # grade, para a rolagem não voltar ao topo.
            index = 0
            while (card := self.flow.get_child_at_index(index)) is not None:
                card.set_current(card.pkg['id'] == self._current)
                index += 1
        else:
            scroll = self.scrolled.get_vadjustment()
            position = scroll.get_value()
            self._pkgs = pkgs
            self.flow.remove_all()
            for pkg in pkgs:
                self.flow.append(Card(pkg, pkg['id'] == self._current))
            GLib.idle_add(lambda: scroll.set_value(position) and False)
            self._sync_lists()
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
