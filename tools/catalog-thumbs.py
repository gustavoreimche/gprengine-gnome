#!/usr/bin/python3
"""Copia as miniaturas que o renderer gerou para catalog/thumbs/, em JPEG.

    tools/catalog-thumbs.py [id ...]     sem ids, só as que faltam

O renderer só desenha a miniatura de um wallpaper que ainda não tem uma em
~/.cache/gprengine/thumbs; para refazer, apague o PNG de lá e recarregue.
"""
import os
import sys

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
sys.path.insert(0, REPO)

from engine import packages  # noqa: E402

out = os.path.join(REPO, 'catalog', 'thumbs')
os.makedirs(out, exist_ok=True)
wanted = set(sys.argv[1:])
for name in sorted(os.listdir(os.path.join(REPO, 'wallpapers'))):
    target = os.path.join(out, f'{name}.jpg')
    if wanted and name not in wanted or not wanted and os.path.isfile(target):
        continue
    source = os.path.join(packages.THUMB_DIR, f'{name}.png')
    if not os.path.isfile(source):
        print(f'{name}: sem miniatura em {packages.THUMB_DIR}', file=sys.stderr)
        continue
    Image.open(source).convert('RGB').save(target, 'JPEG', quality=88)
    print(name)
