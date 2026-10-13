"""Catálogo de wallpapers para baixar: índice JSON, miniaturas e pacotes
.tar.gz publicados junto com o repositório APT.

Nada aqui toca em GTK; a galeria chama estas funções fora da thread principal.
"""

import hashlib
import io
import json
import os
import shutil
import tarfile
import tempfile
import urllib.request

from . import packages

URL = os.environ.get('GPRENGINE_CATALOG_URL') or \
    'https://gustavoreimche.github.io/gprengine-gnome/catalog'
CACHE_DIR = os.path.join(os.path.dirname(packages.THUMB_DIR), 'catalog')
FORMAT = 1
TIMEOUT = 20
# Um wallpaper é um punhado de arquivos de texto; isto é folga, não meta.
MAX_ARCHIVE = 20 * 1024 * 1024
MAX_UNPACKED = 50 * 1024 * 1024
MAX_FILES = 200


class CatalogError(Exception):
    pass


def _fetch(name, limit):
    try:
        with urllib.request.urlopen(f'{URL}/{name}', timeout=TIMEOUT) as r:
            data = r.read(limit + 1)
    except (OSError, ValueError) as e:
        raise CatalogError(f'Não foi possível baixar {name}: {e}') from e
    if len(data) > limit:
        raise CatalogError(f'{name} é maior do que o permitido')
    return data


def fetch_index():
    """Lista de entradas do catálogo, só as que esta versão sabe usar."""
    try:
        index = json.loads(_fetch('index.json', 2 * 1024 * 1024))
    except ValueError as e:
        raise CatalogError('O índice do catálogo está corrompido') from e
    if not isinstance(index, dict) or index.get('format') != FORMAT:
        raise CatalogError('O catálogo é de uma versão mais nova do GprEngine')
    entries = []
    for entry in index.get('wallpapers', []):
        if not isinstance(entry, dict):
            continue
        pkg_id = entry.get('id')
        if not isinstance(pkg_id, str) or not packages.ID_RE.match(pkg_id):
            continue
        if entry.get('type') not in packages.SUPPORTED_TYPES:
            continue
        if not isinstance(entry.get('sha256'), str):
            continue
        entries.append({
            'id': pkg_id,
            'name': str(entry.get('name') or pkg_id),
            'author': str(entry.get('author') or ''),
            'type': entry['type'],
            'sha256': entry['sha256'],
            'size': int(entry.get('size') or 0),
            'thumbnail': bool(entry.get('thumbnail')),
        })
    return entries


def fetch_thumbnail(entry):
    """Caminho local da miniatura (baixa uma vez por versão do pacote)."""
    if not entry['thumbnail']:
        return ''
    path = os.path.join(CACHE_DIR, f'{entry["id"]}-{entry["sha256"][:12]}.jpg')
    if not os.path.isfile(path):
        data = _fetch(f'thumbs/{entry["id"]}.jpg', 2 * 1024 * 1024)
        os.makedirs(CACHE_DIR, exist_ok=True)
        with open(path, 'wb') as f:
            f.write(data)
    return path


def checked_members(archive, pkg_id):
    """Só arquivos e pastas comuns, todos dentro de `<id>/`."""
    members = archive.getmembers()
    if len(members) > MAX_FILES:
        raise CatalogError('O pacote tem arquivos demais')
    total = 0
    for member in members:
        parts = member.name.split('/')
        if (member.name.startswith('/') or '..' in parts or parts[0] != pkg_id
                or not (member.isfile() or member.isdir())):
            raise CatalogError(f'O pacote traz um item inesperado: {member.name}')
        total += member.size
        member.mode = 0o755 if member.isdir() else 0o644
        member.uid = member.gid = 0
    if total > MAX_UNPACKED:
        raise CatalogError('O pacote é grande demais')
    return members


def install(entry):
    """Baixa, confere e instala na pasta de wallpapers do usuário."""
    pkg_id = entry['id']
    data = _fetch(f'packages/{pkg_id}.tar.gz', MAX_ARCHIVE)
    if hashlib.sha256(data).hexdigest() != entry['sha256']:
        raise CatalogError('O arquivo baixado não confere com o catálogo')
    return install_bytes(data, pkg_id)


def install_bytes(data, pkg_id):
    """Instala um pacote .tar.gz já em memória; substitui o que houver na
    pasta do usuário com o mesmo id."""
    os.makedirs(packages.USER_DIR, exist_ok=True)
    staging = tempfile.mkdtemp(prefix='.baixando-', dir=packages.USER_DIR)
    try:
        try:
            with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
                archive.extractall(staging, members=checked_members(archive, pkg_id))
        except (tarfile.TarError, OSError) as e:
            raise CatalogError(f'O pacote não pôde ser aberto: {e}') from e
        pkg = packages.load(os.path.join(staging, pkg_id), False)
        if pkg.id != pkg_id or pkg.error or pkg.unsupported:
            raise CatalogError(pkg.error or 'O pacote não é um wallpaper válido')
        target = os.path.join(packages.USER_DIR, pkg_id)
        if os.path.isdir(target):
            shutil.rmtree(target)
        os.rename(os.path.join(staging, pkg_id), target)
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    return pkg_id


def installed_from_catalog(pkg_id):
    """Verdadeiro se o wallpaper está na pasta do usuário (pode ser removido)."""
    return os.path.isfile(os.path.join(packages.USER_DIR, pkg_id, 'manifest.json'))


def remove(pkg_id):
    if not packages.ID_RE.match(pkg_id):
        raise CatalogError('Id inválido')
    shutil.rmtree(os.path.join(packages.USER_DIR, pkg_id), ignore_errors=True)
