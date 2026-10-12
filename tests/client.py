#!/usr/bin/python3
"""Janela comum para os testes: tests/client.py TÍTULO [LARGURA ALTURA]"""
import sys

import gi

gi.require_version('Gtk', '4.0')
from gi.repository import Gtk  # noqa: E402

title = sys.argv[1]
width, height = (int(v) for v in sys.argv[2:4]) if len(sys.argv) > 3 else (500, 350)


def activate(app):
    window = Gtk.ApplicationWindow(application=app, title=title)
    window.set_default_size(width, height)
    window.set_child(Gtk.Label(label=title))
    window.present()


app = Gtk.Application(application_id=f'dev.gpr.GprEngine.Test.{title}')
app.connect('activate', activate)
app.run([])
