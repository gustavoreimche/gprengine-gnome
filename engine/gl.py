"""OpenGL por ctypes, só o necessário para um shader de tela cheia.

O PyGObject não expõe OpenGL e o sistema não traz PyOpenGL. Com GLVND, a
libOpenGL despacha para o driver do contexto corrente, que é o do GtkGLArea.
"""

import ctypes
from ctypes import (POINTER, byref, c_char_p, c_float, c_int, c_uint,
                    c_void_p, create_string_buffer)

VERTEX_SHADER = 0x8B31
FRAGMENT_SHADER = 0x8B30
COMPILE_STATUS = 0x8B81
LINK_STATUS = 0x8B82
INFO_LOG_LENGTH = 0x8B84
TRIANGLES = 0x0004
TEXTURE_2D = 0x0DE1
RGBA = 0x1908
RGBA8 = 0x8058
UNSIGNED_BYTE = 0x1401
LINEAR = 0x2601
CLAMP_TO_EDGE = 0x812F
TEXTURE_MAG_FILTER = 0x2800
TEXTURE_MIN_FILTER = 0x2801
TEXTURE_WRAP_S = 0x2802
TEXTURE_WRAP_T = 0x2803
FRAMEBUFFER = 0x8D40
READ_FRAMEBUFFER = 0x8CA8
DRAW_FRAMEBUFFER = 0x8CA9
DRAW_FRAMEBUFFER_BINDING = 0x8CA6
COLOR_ATTACHMENT0 = 0x8CE0
FRAMEBUFFER_COMPLETE = 0x8CD5
COLOR_BUFFER_BIT = 0x4000
RENDERER = 0x1F01
VERSION = 0x1F02
PACK_ALIGNMENT = 0x0D05
BLEND = 0x0BE2
DEPTH_TEST = 0x0B71
SCISSOR_TEST = 0x0C11

_SIGNATURES = {
    'glCreateShader': (c_uint, [c_uint]),
    'glShaderSource': (None, [c_uint, c_int, POINTER(c_char_p), POINTER(c_int)]),
    'glCompileShader': (None, [c_uint]),
    'glGetShaderiv': (None, [c_uint, c_uint, POINTER(c_int)]),
    'glGetShaderInfoLog': (None, [c_uint, c_int, POINTER(c_int), c_char_p]),
    'glDeleteShader': (None, [c_uint]),
    'glCreateProgram': (c_uint, []),
    'glAttachShader': (None, [c_uint, c_uint]),
    'glLinkProgram': (None, [c_uint]),
    'glGetProgramiv': (None, [c_uint, c_uint, POINTER(c_int)]),
    'glGetProgramInfoLog': (None, [c_uint, c_int, POINTER(c_int), c_char_p]),
    'glDeleteProgram': (None, [c_uint]),
    'glUseProgram': (None, [c_uint]),
    'glGetUniformLocation': (c_int, [c_uint, c_char_p]),
    'glUniform1f': (None, [c_int, c_float]),
    'glUniform1i': (None, [c_int, c_int]),
    'glUniform3f': (None, [c_int, c_float, c_float, c_float]),
    'glUniform4f': (None, [c_int, c_float, c_float, c_float, c_float]),
    'glGenVertexArrays': (None, [c_int, POINTER(c_uint)]),
    'glBindVertexArray': (None, [c_uint]),
    'glDeleteVertexArrays': (None, [c_int, POINTER(c_uint)]),
    'glDrawArrays': (None, [c_uint, c_int, c_int]),
    'glGenFramebuffers': (None, [c_int, POINTER(c_uint)]),
    'glBindFramebuffer': (None, [c_uint, c_uint]),
    'glDeleteFramebuffers': (None, [c_int, POINTER(c_uint)]),
    'glFramebufferTexture2D': (None, [c_uint, c_uint, c_uint, c_uint, c_int]),
    'glCheckFramebufferStatus': (c_uint, [c_uint]),
    'glBlitFramebuffer': (None, [c_int] * 8 + [c_uint, c_uint]),
    'glGenTextures': (None, [c_int, POINTER(c_uint)]),
    'glBindTexture': (None, [c_uint, c_uint]),
    'glDeleteTextures': (None, [c_int, POINTER(c_uint)]),
    'glTexImage2D': (None, [c_uint, c_int, c_int, c_int, c_int, c_int,
                            c_uint, c_uint, c_void_p]),
    'glTexParameteri': (None, [c_uint, c_uint, c_int]),
    'glViewport': (None, [c_int, c_int, c_int, c_int]),
    'glGetIntegerv': (None, [c_uint, POINTER(c_int)]),
    'glGetString': (c_char_p, [c_uint]),
    'glReadPixels': (None, [c_int, c_int, c_int, c_int, c_uint, c_uint, c_void_p]),
    'glPixelStorei': (None, [c_uint, c_int]),
    'glDisable': (None, [c_uint]),
    'glFinish': (None, []),
    'glClearColor': (None, [c_float] * 4),
    'glClear': (None, [c_uint]),
}


def _load():
    last = None
    for name in ('libOpenGL.so.0', 'libGL.so.1'):
        try:
            return ctypes.CDLL(name)
        except OSError as e:
            last = e
    raise ImportError(f'libOpenGL não encontrada: {last}')


_lib = _load()
for _name, (_res, _args) in _SIGNATURES.items():
    _fn = getattr(_lib, _name)
    _fn.restype = _res
    _fn.argtypes = _args
    globals()[_name] = _fn

HEADER = """#version 330 core
uniform vec3 iResolution;
uniform float iTime;
uniform float iTimeDelta;
uniform int iFrame;
uniform vec4 iMouse;
uniform vec4 iDate;
uniform vec4 iWeather;
out vec4 primo_FragColor;
#line 1
"""

FOOTER = """
void main() {
    vec4 color = vec4(0.0, 0.0, 0.0, 1.0);
    mainImage(color, gl_FragCoord.xy);
    primo_FragColor = vec4(color.rgb, 1.0);
}
"""

# Triângulo único cobrindo a tela, gerado a partir do gl_VertexID.
VERTEX = """#version 330 core
void main() {
    vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
"""

UNIFORMS = ('iResolution', 'iTime', 'iTimeDelta', 'iFrame', 'iMouse', 'iDate',
            'iWeather')


class ShaderError(Exception):
    """Log do compilador. As linhas já são relativas ao arquivo do autor,
    porque o cabeçalho termina em `#line 1`."""


def _log(getiv, getlog, obj):
    length = c_int(0)
    getiv(obj, INFO_LOG_LENGTH, byref(length))
    if length.value <= 1:
        return ''
    buf = create_string_buffer(length.value)
    getlog(obj, length.value, None, buf)
    return buf.value.decode('utf-8', 'replace').strip()


def _compile(kind, source):
    shader = glCreateShader(kind)
    data = source.encode('utf-8')
    glShaderSource(shader, 1, byref(c_char_p(data)), None)
    glCompileShader(shader)
    ok = c_int(0)
    glGetShaderiv(shader, COMPILE_STATUS, byref(ok))
    if not ok.value:
        log = _log(glGetShaderiv, glGetShaderInfoLog, shader)
        glDeleteShader(shader)
        raise ShaderError(log or 'falha ao compilar o shader')
    return shader


def gl_string(name):
    value = glGetString(name)
    return value.decode('utf-8', 'replace') if value else ''


class Program:
    """Shader no contrato Shadertoy. Exige contexto GL corrente."""

    def __init__(self, source):
        vertex = _compile(VERTEX_SHADER, VERTEX)
        try:
            fragment = _compile(FRAGMENT_SHADER, HEADER + source + FOOTER)
        except ShaderError:
            glDeleteShader(vertex)
            raise
        self.id = glCreateProgram()
        glAttachShader(self.id, vertex)
        glAttachShader(self.id, fragment)
        glLinkProgram(self.id)
        glDeleteShader(vertex)
        glDeleteShader(fragment)
        ok = c_int(0)
        glGetProgramiv(self.id, LINK_STATUS, byref(ok))
        if not ok.value:
            log = _log(glGetProgramiv, glGetProgramInfoLog, self.id)
            glDeleteProgram(self.id)
            self.id = 0
            raise ShaderError(log or 'falha ao ligar o programa')
        self.loc = {name: glGetUniformLocation(self.id, name.encode())
                    for name in UNIFORMS}

    def draw(self, width, height, time, delta, frame, date, weather):
        glUseProgram(self.id)
        loc = self.loc
        glUniform3f(loc['iResolution'], width, height, 1.0)
        glUniform1f(loc['iTime'], time)
        glUniform1f(loc['iTimeDelta'], delta)
        glUniform1i(loc['iFrame'], frame)
        glUniform4f(loc['iMouse'], 0.0, 0.0, 0.0, 0.0)
        glUniform4f(loc['iDate'], *date)
        glUniform4f(loc['iWeather'], *weather)
        glDrawArrays(TRIANGLES, 0, 3)

    def destroy(self):
        if self.id:
            glDeleteProgram(self.id)
            self.id = 0


class Target:
    """Framebuffer com textura RGBA, para renderizar em escala reduzida."""

    def __init__(self):
        self.fbo = c_uint(0)
        self.tex = c_uint(0)
        self.width = self.height = 0

    def ensure(self, width, height):
        if (width, height) == (self.width, self.height) and self.fbo.value:
            return
        self.destroy()
        glGenTextures(1, byref(self.tex))
        glBindTexture(TEXTURE_2D, self.tex)
        glTexImage2D(TEXTURE_2D, 0, RGBA8, width, height, 0, RGBA,
                     UNSIGNED_BYTE, None)
        for param, value in ((TEXTURE_MIN_FILTER, LINEAR),
                             (TEXTURE_MAG_FILTER, LINEAR),
                             (TEXTURE_WRAP_S, CLAMP_TO_EDGE),
                             (TEXTURE_WRAP_T, CLAMP_TO_EDGE)):
            glTexParameteri(TEXTURE_2D, param, value)
        glBindTexture(TEXTURE_2D, 0)
        glGenFramebuffers(1, byref(self.fbo))
        glBindFramebuffer(FRAMEBUFFER, self.fbo)
        glFramebufferTexture2D(FRAMEBUFFER, COLOR_ATTACHMENT0, TEXTURE_2D,
                               self.tex, 0)
        status = glCheckFramebufferStatus(FRAMEBUFFER)
        if status != FRAMEBUFFER_COMPLETE:
            self.destroy()
            raise RuntimeError(f'framebuffer incompleto: 0x{status:x}')
        self.width, self.height = width, height

    def destroy(self):
        if self.fbo.value:
            glDeleteFramebuffers(1, byref(self.fbo))
            self.fbo = c_uint(0)
        if self.tex.value:
            glDeleteTextures(1, byref(self.tex))
            self.tex = c_uint(0)
        self.width = self.height = 0


def bound_draw_framebuffer():
    value = c_int(0)
    glGetIntegerv(DRAW_FRAMEBUFFER_BINDING, byref(value))
    return value.value


def read_rgba(width, height):
    """Pixels do framebuffer de leitura corrente, de baixo para cima."""
    buf = create_string_buffer(width * height * 4)
    glPixelStorei(PACK_ALIGNMENT, 1)
    glReadPixels(0, 0, width, height, RGBA, UNSIGNED_BYTE, buf)
    return buf.raw
