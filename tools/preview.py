#!/usr/bin/python3
"""Gera uma página com todos os wallpapers animando (WebGL 2).

    tools/preview.py [saida.html]

Os shaders são os mesmos arquivos; só o cabeçalho muda para GLSL ES. Um
wallpaper que não compilar no navegador mostra a miniatura parada.
"""
import html
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.realpath(__file__))))

from engine import packages  # noqa: E402

out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(packages.THUMB_DIR), 'preview.html')

items = []
for pkg in packages.discover():
    if not pkg.usable:
        continue
    thumb = pkg.thumbnail or os.path.join(packages.THUMB_DIR, f'{pkg.id}.png')
    items.append({
        'id': pkg.id, 'name': pkg.name, 'author': pkg.author,
        'source': pkg.source(),
        'thumb': 'file://' + thumb if os.path.isfile(thumb) else '',
    })

PAGE = """<!doctype html>
<html lang="pt-BR">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>GprEngine: wallpapers</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; background: #0d1014; color: #e6e9ee;
         font: 15px/1.4 system-ui, sans-serif; }
  header { padding: 28px 32px 8px; }
  h1 { margin: 0; font-size: 22px; font-weight: 650; }
  header p { margin: 6px 0 0; color: #8b93a1; }
  main { display: grid; gap: 20px; padding: 20px 32px 48px;
         grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); }
  figure { margin: 0; cursor: zoom-in; }
  canvas, figure img { display: block; width: 100%; aspect-ratio: 16 / 10;
           border-radius: 12px; background: #000; object-fit: cover; }
  figcaption { display: flex; justify-content: space-between; padding: 8px 2px 0; }
  figcaption small { color: #8b93a1; }
  .static small::after { content: " · parado"; color: #d9a441; }
  #full { position: fixed; inset: 0; background: #000; display: none; cursor: zoom-out; }
  #full canvas { width: 100%; height: 100%; border-radius: 0; aspect-ratio: auto; }
  #full span { position: absolute; left: 24px; bottom: 20px; font-size: 18px;
               text-shadow: 0 1px 6px #000; }
</style>
<header>
  <h1>GprEngine: wallpapers</h1>
  <p>__COUNT__ wallpapers, animando ao vivo. Clique para ver em tela cheia; clique de novo ou Esc para voltar.</p>
</header>
<main id="grid"></main>
<div id="full"><canvas></canvas><span></span></div>
<script>
const ITEMS = __ITEMS__;
const HEADER = `#version 300 es
precision highp float;
precision highp int;
uniform vec3 iResolution;
uniform float iTime;
uniform float iTimeDelta;
uniform int iFrame;
uniform vec4 iMouse;
uniform vec4 iDate;
out vec4 primo_FragColor;
#line 1
`;
const FOOTER = `
void main() {
    vec4 color = vec4(0.0, 0.0, 0.0, 1.0);
    mainImage(color, gl_FragCoord.xy);
    primo_FragColor = vec4(color.rgb, 1.0);
}`;
const VERTEX = `#version 300 es
void main() {
    vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}`;

// Um único contexto WebGL para tudo: os navegadores limitam quantos existem.
const work = document.createElement('canvas');
const gl = work.getContext('webgl2', {preserveDrawingBuffer: true});
window.previewErrors = {};

function compile(type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS))
        throw new Error(gl.getShaderInfoLog(shader));
    return shader;
}

function build(source) {
    const program = gl.createProgram();
    gl.attachShader(program, compile(gl.VERTEX_SHADER, VERTEX));
    gl.attachShader(program, compile(gl.FRAGMENT_SHADER, HEADER + source + FOOTER));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS))
        throw new Error(gl.getProgramInfoLog(program));
    const loc = {};
    for (const name of ['iResolution', 'iTime', 'iTimeDelta', 'iFrame', 'iDate'])
        loc[name] = gl.getUniformLocation(program, name);
    return {program, loc};
}

function draw(entry, target, time, frame) {
    const width = target.width, height = target.height;
    if (work.width !== width || work.height !== height) {
        work.width = width;
        work.height = height;
    }
    gl.viewport(0, 0, width, height);
    gl.useProgram(entry.program);
    gl.uniform3f(entry.loc.iResolution, width, height, 1);
    gl.uniform1f(entry.loc.iTime, time);
    gl.uniform1f(entry.loc.iTimeDelta, 1 / 30);
    gl.uniform1i(entry.loc.iFrame, frame);
    const now = new Date();
    gl.uniform4f(entry.loc.iDate, now.getFullYear(), now.getMonth(), now.getDate(),
        now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds());
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    target.getContext('2d').drawImage(work, 0, 0);
}

const grid = document.getElementById('grid');
const cards = [];
for (const item of ITEMS) {
    const figure = document.createElement('figure');
    const caption = document.createElement('figcaption');
    caption.innerHTML = `<span></span><small></small>`;
    caption.firstChild.textContent = item.name;
    caption.lastChild.textContent = item.author;
    let entry = null;
    try {
        if (!gl)
            throw new Error('WebGL 2 indisponível');
        entry = build(item.source);
    } catch (e) {
        window.previewErrors[item.id] = String(e.message);
    }
    let canvas = null;
    if (entry) {
        canvas = document.createElement('canvas');
        canvas.width = 480;
        canvas.height = 300;
        figure.append(canvas);
        figure.addEventListener('click', () => open(item, entry));
    } else {
        const img = document.createElement('img');
        img.src = item.thumb;
        figure.append(img);
        figure.classList.add('static');
        figure.title = window.previewErrors[item.id];
    }
    figure.append(caption);
    grid.append(figure);
    if (entry)
        cards.push({entry, canvas, visible: false});
}

// Só anima o que está na tela.
const observer = new IntersectionObserver(entries => {
    for (const e of entries)
        cards.find(c => c.canvas === e.target).visible = e.isIntersecting;
});
cards.forEach(c => observer.observe(c.canvas));

const full = document.getElementById('full');
const fullCanvas = full.querySelector('canvas');
let current = null;
function open(item, entry) {
    current = entry;
    full.querySelector('span').textContent = item.name;
    full.style.display = 'block';
}
function close() {
    current = null;
    full.style.display = 'none';
}
full.addEventListener('click', close);
addEventListener('keydown', e => e.key === 'Escape' && close());

let frame = 0, last = 0;
function tick(ms) {
    requestAnimationFrame(tick);
    if (ms - last < 1000 / 30 - 2)
        return;
    last = ms;
    frame++;
    const time = ms / 1000;
    if (current) {
        const scale = Math.min(devicePixelRatio, 2) * 0.75;
        fullCanvas.width = Math.round(innerWidth * scale);
        fullCanvas.height = Math.round(innerHeight * scale);
        draw(current, fullCanvas, time, frame);
        return;
    }
    for (const card of cards) {
        if (card.visible)
            draw(card.entry, card.canvas, time, frame);
    }
}
requestAnimationFrame(tick);
</script>
</html>
"""

page = PAGE.replace('__COUNT__', str(len(items))).replace(
    '__ITEMS__', json.dumps(items).replace('</', '<\\/'))
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, 'w', encoding='utf-8') as f:
    f.write(page)
print(out)
