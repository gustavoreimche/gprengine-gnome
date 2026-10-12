"""Descoberta e validação dos pacotes de wallpaper (pasta + manifest.json)."""

import json
import os
import re
from dataclasses import dataclass, field

FORMAT = 1
SUPPORTED_TYPES = {'glsl'}
RESERVED_TYPES = {'web', 'video'}
ID_RE = re.compile(r'^[a-z0-9][a-z0-9_-]{0,63}$')

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _xdg(var, default):
    return os.environ.get(var) or os.path.expanduser(default)


USER_DIR = os.path.join(_xdg('XDG_CONFIG_HOME', '~/.config'),
                        'gprengine', 'wallpapers')
BUILTIN_DIR = os.path.join(_xdg('XDG_DATA_HOME', '~/.local/share'),
                           'gprengine', 'wallpapers')
THUMB_DIR = os.path.join(_xdg('XDG_CACHE_HOME', '~/.cache'),
                         'gprengine', 'thumbs')


@dataclass
class Package:
    id: str
    name: str
    author: str
    type: str
    path: str
    entry: str = ''
    thumbnail: str = ''
    builtin: bool = False
    # Preenchido quando o pacote não pode ser aplicado; a galeria mostra.
    error: str = ''
    unsupported: bool = False
    extra: dict = field(default_factory=dict)

    @property
    def usable(self):
        return not self.error and not self.unsupported

    def source(self):
        with open(self.entry, encoding='utf-8') as f:
            return f.read()

    def to_dict(self):
        return {
            'id': self.id, 'name': self.name, 'author': self.author,
            'type': self.type, 'path': self.path, 'thumbnail': self.thumbnail,
            'builtin': self.builtin, 'error': self.error,
            'unsupported': self.unsupported,
        }


def _inside(root, relative):
    """Caminho absoluto de `relative` dentro de `root`, ou None se escapar."""
    full = os.path.realpath(os.path.join(root, relative))
    root = os.path.realpath(root)
    return full if full.startswith(root + os.sep) else None


def load(path, builtin=False):
    """Lê um pacote. Nunca levanta: problema vira `error` no Package."""
    folder = os.path.basename(os.path.normpath(path))
    pkg = Package(id=folder, name=folder, author='', type='', path=path,
                  builtin=builtin)
    try:
        with open(os.path.join(path, 'manifest.json'), encoding='utf-8') as f:
            manifest = json.load(f)
    except FileNotFoundError:
        pkg.error = 'manifest.json não encontrado'
        return pkg
    except (OSError, ValueError) as e:
        pkg.error = f'manifest.json inválido: {e}'
        return pkg
    if not isinstance(manifest, dict):
        pkg.error = 'manifest.json precisa ser um objeto'
        return pkg

    pkg_id = manifest.get('id', folder)
    if not isinstance(pkg_id, str) or not ID_RE.match(pkg_id):
        pkg.error = 'id inválido: use minúsculas, dígitos, "-" e "_"'
        return pkg
    pkg.id = pkg_id
    pkg.name = str(manifest.get('name') or pkg_id)
    pkg.author = str(manifest.get('author') or '')
    pkg.type = str(manifest.get('type') or '')

    thumb = manifest.get('thumbnail')
    if isinstance(thumb, str):
        thumb = _inside(path, thumb)
        if thumb and os.path.isfile(thumb):
            pkg.thumbnail = thumb

    if manifest.get('format') != FORMAT:
        pkg.error = f'format {manifest.get("format")!r} não suportado (esperado {FORMAT})'
        return pkg
    if pkg.type in RESERVED_TYPES:
        pkg.unsupported = True
        return pkg
    if pkg.type not in SUPPORTED_TYPES:
        pkg.error = f'type {pkg.type!r} desconhecido'
        return pkg

    entry = manifest.get('entry')
    entry = _inside(path, entry) if isinstance(entry, str) else None
    if not entry or not os.path.isfile(entry):
        pkg.error = 'entry ausente ou fora da pasta do pacote'
        return pkg
    pkg.entry = entry
    return pkg


def search_dirs():
    """Do mais prioritário para o menos: usuário, instalado, repositório."""
    dirs = [(USER_DIR, False), (BUILTIN_DIR, True)]
    repo = os.path.join(REPO, 'wallpapers')
    if os.path.realpath(repo) != os.path.realpath(BUILTIN_DIR):
        dirs.append((repo, True))
    return dirs


def discover():
    """Todos os pacotes, ordenados por nome. Com ids repetidos vale o primeiro
    diretório de `search_dirs`."""
    found = {}
    for directory, builtin in search_dirs():
        try:
            names = sorted(os.listdir(directory))
        except OSError:
            continue
        for name in names:
            path = os.path.join(directory, name)
            if name.startswith('.') or not os.path.isdir(path):
                continue
            pkg = load(path, builtin)
            found.setdefault(pkg.id, pkg)
    return sorted(found.values(), key=lambda p: p.name.lower())
