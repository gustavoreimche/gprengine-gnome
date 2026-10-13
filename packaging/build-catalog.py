#!/usr/bin/python3
"""Monta o catálogo de wallpapers para o GitHub Pages.

    packaging/build-catalog.py PASTA_DE_SAÍDA

Gera index.json, packages/<id>.tar.gz e thumbs/<id>.jpg a partir de
wallpapers/ e catalog/thumbs/. Os .tar.gz são reprodutíveis: o mesmo conteúdo
dá sempre o mesmo sha256, que é o que a galeria usa para saber se mudou.
"""
import gzip
import hashlib
import io
import json
import os
import shutil
import sys
import tarfile

REPO = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
sys.path.insert(0, REPO)

from engine import packages  # noqa: E402

out = sys.argv[1]
os.makedirs(os.path.join(out, 'packages'), exist_ok=True)
os.makedirs(os.path.join(out, 'thumbs'), exist_ok=True)


def archive(pkg):
    buffer = io.BytesIO()
    with gzip.GzipFile(fileobj=buffer, mode='wb', mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode='w') as tar:
            for root, dirs, files in os.walk(pkg.path):
                dirs.sort()
                for name in sorted(files):
                    full = os.path.join(root, name)
                    info = tarfile.TarInfo(
                        f'{pkg.id}/{os.path.relpath(full, pkg.path)}')
                    info.size = os.path.getsize(full)
                    info.mode = 0o644
                    with open(full, 'rb') as f:
                        tar.addfile(info, f)
    return buffer.getvalue()


entries = []
root = os.path.join(REPO, 'wallpapers')
for name in sorted(os.listdir(root)):
    path = os.path.join(root, name)
    if not os.path.isdir(path):
        continue
    pkg = packages.load(path, True)
    if not pkg.usable or pkg.id != name:
        sys.exit(f'{name}: {pkg.error or "pacote inválido"}')
    data = archive(pkg)
    with open(os.path.join(out, 'packages', f'{pkg.id}.tar.gz'), 'wb') as f:
        f.write(data)
    thumb = os.path.join(REPO, 'catalog', 'thumbs', f'{pkg.id}.jpg')
    if os.path.isfile(thumb):
        shutil.copy(thumb, os.path.join(out, 'thumbs', f'{pkg.id}.jpg'))
    entries.append({
        'id': pkg.id, 'name': pkg.name, 'author': pkg.author, 'type': pkg.type,
        'size': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
        'thumbnail': os.path.isfile(thumb),
    })

with open(os.path.join(out, 'index.json'), 'w', encoding='utf-8') as f:
    json.dump({'format': 1, 'wallpapers': entries}, f, ensure_ascii=False, indent=1)
print(f'{len(entries)} wallpapers em {out}')
