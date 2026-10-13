"""Wallpapers feitos pelo usuário: criar a partir de um modelo, exportar para
compartilhar e instalar o de outra pessoa.

Um wallpaper personalizado é uma pasta em ~/.config/gprengine/wallpapers/. O
guia para quem escreve um está em docs/wallpapers-personalizados.md.
"""

import io
import json
import os
import re
import shutil
import tarfile
import unicodedata

from . import catalog, packages

ARCHIVE_SUFFIX = '.gprwallpaper'

TEMPLATE_SHADER = '''// @NAME@
//
// Escreva só mainImage: ela roda uma vez por pixel, a cada quadro.
//   fragCoord    posição do pixel, em pixels (origem no canto de baixo)
//   iResolution  tamanho da tela em pixels
//   iTime        segundos de animação (para quando o wallpaper pausa)
//
// Salve o arquivo: o wallpaper recarrega sozinho. O guia completo, com os
// outros valores disponíveis: docs/wallpapers-personalizados.md

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    // De 0 a 1 nos dois eixos.
    vec2 uv = fragCoord / iResolution.xy;

    // Faixas diagonais que andam devagar.
    float wave = 0.5 + 0.5 * sin((uv.x + uv.y) * 6.0 + iTime * 0.4);
    vec3 night = vec3(0.05, 0.07, 0.16);
    vec3 dawn = vec3(0.95, 0.45, 0.35);
    fragColor = vec4(mix(night, dawn, wave * uv.y), 1.0);
}
'''


def slug(name):
    """'Pôr do sol' -> 'por-do-sol'."""
    plain = unicodedata.normalize('NFD', name)
    plain = ''.join(c for c in plain if unicodedata.category(c) != 'Mn')
    return re.sub(r'[^a-z0-9]+', '-', plain.lower()).strip('-')[:48]


def is_custom(pkg_id):
    """Verdadeiro se o wallpaper está na pasta do usuário."""
    return bool(packages.ID_RE.match(pkg_id or '')) and os.path.isfile(
        os.path.join(packages.USER_DIR, pkg_id, 'manifest.json'))


def create_template(name, author=''):
    """Cria a pasta de um wallpaper novo, já funcionando; devolve
    (id, caminho do shader)."""
    pkg_id = slug(name)
    if not packages.ID_RE.match(pkg_id):
        raise ValueError('Dê um nome com letras ou números')
    path = os.path.join(packages.USER_DIR, pkg_id)
    if os.path.exists(path):
        raise ValueError(f'Já existe um wallpaper "{pkg_id}" na sua pasta')
    os.makedirs(os.path.join(path, 'content'))
    manifest = {'format': packages.FORMAT, 'id': pkg_id, 'name': name,
                'author': author, 'type': 'glsl',
                'entry': 'content/shader.glsl'}
    with open(os.path.join(path, 'manifest.json'), 'w', encoding='utf-8') as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write('\n')
    shader = os.path.join(path, 'content', 'shader.glsl')
    with open(shader, 'w', encoding='utf-8') as f:
        f.write(TEMPLATE_SHADER.replace('@NAME@', name))
    return pkg_id, shader


def export_package(pkg_path, pkg_id, target):
    """Empacota a pasta de um wallpaper num arquivo para compartilhar."""
    with tarfile.open(target, 'w:gz') as tar:
        for root, dirs, files in os.walk(pkg_path):
            dirs[:] = sorted(d for d in dirs if not d.startswith('.'))
            for name in sorted(files):
                if name.startswith('.'):
                    continue
                full = os.path.join(root, name)
                info = tarfile.TarInfo(
                    f'{pkg_id}/{os.path.relpath(full, pkg_path)}')
                info.size = os.path.getsize(full)
                info.mode = 0o644
                with open(full, 'rb') as f:
                    tar.addfile(info, f)


def _read(path):
    if os.path.getsize(path) > catalog.MAX_ARCHIVE:
        raise catalog.CatalogError('O arquivo é grande demais')
    with open(path, 'rb') as f:
        return f.read()


def inspect_archive(path):
    """Abre um pacote sem instalar e devolve o que ele traz."""
    try:
        with tarfile.open(fileobj=io.BytesIO(_read(path)), mode='r:gz') as tar:
            names = [m.name for m in tar.getmembers()]
            pkg_id = names[0].split('/')[0] if names else ''
            if not packages.ID_RE.match(pkg_id):
                raise catalog.CatalogError('O nome da pasta do pacote é inválido')
            members = catalog.checked_members(tar, pkg_id)
            manifest_file = tar.extractfile(f'{pkg_id}/manifest.json')
            manifest = json.load(manifest_file)
    except (tarfile.TarError, OSError, KeyError, ValueError) as e:
        if isinstance(e, catalog.CatalogError):
            raise
        raise catalog.CatalogError('O arquivo não é um wallpaper do GprEngine') from e
    if not isinstance(manifest, dict) or manifest.get('id') != pkg_id:
        raise catalog.CatalogError('O manifest.json do pacote não confere com a pasta')
    return {
        'id': pkg_id,
        'name': str(manifest.get('name') or pkg_id),
        'author': str(manifest.get('author') or ''),
        'files': [m.name.split('/', 1)[1] for m in members if m.isfile()],
        'replaces': is_custom(pkg_id),
    }


def install_archive(path):
    """Instala um pacote na pasta do usuário; devolve o id."""
    info = inspect_archive(path)
    return catalog.install_bytes(_read(path), info['id'])


def remove(pkg_id):
    if not is_custom(pkg_id):
        raise ValueError('Só dá para remover wallpapers da sua pasta')
    shutil.rmtree(os.path.join(packages.USER_DIR, pkg_id))
