#!/usr/bin/python3
"""Grava um quadro do monitor pelo ScreenCast do Mutter.

Ao contrário de `headless.sh shot`, que repinta o palco fora da tela, isto pega
o quadro que o compositor de fato montou para o monitor, com o recorte de
oclusão valendo.

    tests/headless.sh run tests/screencast.py saida.png [quadros a pular]
"""
import sys

import gi

gi.require_version('Gst', '1.0')
from gi.repository import Gio, GLib, Gst  # noqa: E402

out = sys.argv[1]
skip = int(sys.argv[2]) if len(sys.argv) > 2 else 20
Gst.init(None)
bus = Gio.bus_get_sync(Gio.BusType.SESSION)
NAME = 'org.gnome.Mutter.ScreenCast'


def call(path, iface, method, params, reply=None):
    return bus.call_sync(NAME, path, iface, method, params, reply,
                         Gio.DBusCallFlags.NONE, -1, None)


session = call('/org/gnome/Mutter/ScreenCast', NAME, 'CreateSession',
               GLib.Variant('(a{sv})', ({},))).unpack()[0]
stream = call(session, f'{NAME}.Session', 'RecordMonitor',
              GLib.Variant('(sa{sv})', ('', {
                  'cursor-mode': GLib.Variant('u', 0)}))).unpack()[0]
loop = GLib.MainLoop()
state = {'frames': 0}


def on_added(_c, _s, _p, _i, _sig, params):
    node = params.unpack()[0]
    pipeline = Gst.parse_launch(
        f'pipewiresrc path={node} ! videoconvert ! appsink name=sink '
        'emit-signals=true max-buffers=1 drop=true caps=video/x-raw,format=RGB')
    sink = pipeline.get_by_name('sink')

    def on_sample(sink):
        sample = sink.emit('pull-sample')
        state['frames'] += 1
        if state['frames'] <= skip:
            return Gst.FlowReturn.OK
        caps = sample.get_caps().get_structure(0)
        width, height = caps.get_value('width'), caps.get_value('height')
        buf = sample.get_buffer()
        data = buf.extract_dup(0, buf.get_size())
        gi.require_version('GdkPixbuf', '2.0')
        from gi.repository import GdkPixbuf
        stride = len(data) // height
        GdkPixbuf.Pixbuf.new_from_bytes(
            GLib.Bytes.new(data), GdkPixbuf.Colorspace.RGB, False, 8,
            width, height, stride).savev(out, 'png', [], [])
        GLib.idle_add(loop.quit)
        return Gst.FlowReturn.EOS

    sink.connect('new-sample', on_sample)
    pipeline.set_state(Gst.State.PLAYING)
    state['pipeline'] = pipeline


bus.signal_subscribe(NAME, f'{NAME}.Stream', 'PipeWireStreamAdded', stream,
                     None, Gio.DBusSignalFlags.NONE, on_added)
call(session, f'{NAME}.Session', 'Start', None)
GLib.timeout_add_seconds(15, lambda: (print('tempo esgotado', file=sys.stderr), loop.quit()))
loop.run()
if 'pipeline' in state:
    state['pipeline'].set_state(Gst.State.NULL)
call(session, f'{NAME}.Session', 'Stop', None)
print(f'{state["frames"]} quadros recebidos')
