"""GSettings do GprEngine, lido do schema que acompanha a extensão."""

import os

from gi.repository import Gio, GLib

from . import SCHEMA_ID, packages


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
