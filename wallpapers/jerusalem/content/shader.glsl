// Jerusalém ao entardecer, em ilustração chapada: casario de pedra, cúpulas,
// muralha com ameias e ciprestes em primeiro plano.

float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float hash2(vec2 v) { return fract(sin(dot(v, vec2(127.1, 311.7))) * 43758.5453); }

float box(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Janela em arco: retângulo com meio círculo em cima.
float archShape(vec2 q, vec2 b) {
    return min(box(q, b), length(q - vec2(0.0, b.y)) - b.x);
}

// Uma fileira de casas: cada célula é um prédio de altura própria, alguns com
// cúpula. Devolve a cor por cima de `col`.
vec3 houses(vec3 col, vec2 p, float base, float w, float seed,
            vec3 light, vec3 dark, float px) {
    float id = floor(p.x / w);
    float fx = (fract(p.x / w) - 0.5) * w;
    float r = hash(id + seed);
    float r2 = hash(id + seed + 17.0);
    float top = base + 0.035 + r * 0.075;

    float d = p.y - top;
    if (r2 > 0.62)
        d = min(d, length(vec2(fx, p.y - top)) - w * (0.24 + r * 0.12));
    if (r2 < 0.16)
        d = min(d, box(vec2(fx + w * 0.2, p.y - top - 0.02), vec2(w * 0.16, 0.035)));

    vec3 wallCol = mix(light, dark, r2 * 0.55);
    // Face em sombra do lado oposto ao sol.
    wallCol = mix(wallCol, wallCol * 0.80, step(fx, -w * 0.18));
    // Faixa do telhado.
    wallCol = mix(wallCol, wallCol * 0.88, step(top - 0.006, p.y) * step(p.y, top));

    // Janelas em arco numa grade; algumas acesas.
    vec2 g = vec2(w / 3.0, 0.030);
    vec2 wc = floor(vec2(fx + w * 0.5, p.y - base) / g);
    vec2 wq = fract(vec2(fx + w * 0.5, p.y - base) / g) * g - g * 0.5;
    float wr = hash2(wc + vec2(id * 3.7, seed));
    float win = archShape(wq + vec2(0.0, 0.003), vec2(0.0042, 0.0050));
    float show = step(0.45, wr) * step(p.y, top - 0.016) * step(base + 0.004, p.y);
    float lit = step(0.80, wr) * (0.75 + 0.25 * sin(iTime * (0.4 + wr) + wr * 50.0));
    vec3 winCol = mix(dark * 0.42, vec3(1.00, 0.84, 0.48), lit);
    wallCol = mix(wallCol, winCol, smoothstep(px, -px, win) * show);

    return mix(col, wallCol, smoothstep(px, -px, d));
}

float cypress(vec2 p, vec2 pos, float h, float t) {
    vec2 q = p - pos;
    q.x -= sin(t * 0.8 + pos.x * 9.0) * 0.006 * clamp(q.y / h, 0.0, 1.0) * clamp(q.y / h, 0.0, 1.0);
    float wd = h * 0.13;
    float e = (length(vec2(q.x / wd, (q.y - h * 0.5) / (h * 0.5))) - 1.0) * wd;
    return min(e, box(q - vec2(0.0, -0.004), vec2(0.0025, 0.012)));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;
    vec2 p = vec2(uv.x * aspect, uv.y);
    float px = 1.5 / iResolution.y;
    float t = iTime;

    // Céu em faixas chapadas, do creme no horizonte ao azul-petróleo no alto.
    vec3 col = vec3(0.99, 0.90, 0.70);
    col = mix(col, vec3(0.99, 0.78, 0.52), smoothstep(-px, px, uv.y - 0.60 - sin(p.x * 1.3) * 0.010));
    col = mix(col, vec3(0.96, 0.60, 0.42), smoothstep(-px, px, uv.y - 0.71 - sin(p.x * 1.7 + 2.0) * 0.012));
    col = mix(col, vec3(0.78, 0.44, 0.44), smoothstep(-px, px, uv.y - 0.82 - sin(p.x * 1.1 + 4.0) * 0.012));
    col = mix(col, vec3(0.36, 0.38, 0.50), smoothstep(-px, px, uv.y - 0.92 - sin(p.x * 1.5 + 1.0) * 0.010));

    // Sol com dois halos.
    vec2 sun = vec2(aspect * 0.74, 0.64);
    float ds = length(p - sun);
    col = mix(col, vec3(1.00, 0.90, 0.64), smoothstep(px, -px, ds - 0.19) * 0.40);
    col = mix(col, vec3(1.00, 0.93, 0.72), smoothstep(px, -px, ds - 0.14) * 0.60);
    col = mix(col, vec3(1.00, 0.97, 0.88), smoothstep(px, -px, ds - 0.09));

    // Nuvens: cápsulas empilhadas que atravessam o céu devagar.
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float span = aspect + 0.8;
        float cx = mod(hash(fi + 2.0) * span + t * (0.006 + hash(fi + 9.0) * 0.006), span) - 0.4;
        float cy = 0.66 + hash(fi + 5.0) * 0.24;
        float len = 0.07 + hash(fi + 11.0) * 0.08;
        vec2 q = p - vec2(cx, cy);
        float c = box(q, vec2(len, 0.0)) - 0.013;
        c = min(c, box(q - vec2(len * 0.25, 0.020), vec2(len * 0.55, 0.0)) - 0.011);
        c = min(c, box(q - vec2(-len * 0.30, -0.019), vec2(len * 0.50, 0.0)) - 0.009);
        col = mix(col, vec3(1.00, 0.93, 0.82), smoothstep(px, -px, c) * 0.85);
    }

    // Pássaros.
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float span = aspect + 0.4;
        vec2 bp = vec2(mod(t * 0.022 + fi * 0.11 + hash(fi) * 0.3, span) - 0.2,
                       0.78 - fi * 0.022 + sin(t * 0.5 + fi * 2.0) * 0.008);
        vec2 q = p - bp;
        float flap = 0.45 + 0.35 * sin(t * 5.0 + fi * 1.7);
        float b = max(abs(q.y - abs(q.x) * flap) - 0.0016, abs(q.x) - 0.011);
        col = mix(col, vec3(0.30, 0.22, 0.28), smoothstep(px, -px, b));
    }

    // Montes ao fundo.
    float h1 = 0.53 + sin(p.x * 1.6 + 0.4) * 0.040 + sin(p.x * 3.9 + 1.0) * 0.012;
    col = mix(col, vec3(0.93, 0.58, 0.48), smoothstep(px, -px, uv.y - h1));
    float h2 = 0.49 + sin(p.x * 2.3 + 3.0) * 0.035 + sin(p.x * 5.3) * 0.010;
    col = mix(col, vec3(0.80, 0.42, 0.38), smoothstep(px, -px, uv.y - h2));
    // Monte das Oliveiras, com as copas pontilhadas.
    float h3 = 0.45 + sin(p.x * 1.4 + 5.2) * 0.045 + sin(p.x * 4.4 + 2.0) * 0.008;
    vec3 olive = vec3(0.30, 0.50, 0.44);
    vec2 og = vec2(p.x, uv.y - h3) * vec2(38.0, 52.0);
    vec2 oc = floor(og);
    float dot1 = length(fract(og) - 0.5 - (vec2(hash2(oc), hash2(oc + 4.0)) - 0.5) * 0.4);
    olive = mix(olive, vec3(0.20, 0.40, 0.38), smoothstep(0.30, 0.26, dot1) * step(0.5, hash2(oc + 9.0)));
    col = mix(col, olive, smoothstep(px, -px, uv.y - h3));

    // Casario em três fileiras, da mais distante (clara) à mais próxima.
    col = houses(col, p, 0.355, 0.062, 3.0, vec3(0.97, 0.80, 0.62), vec3(0.90, 0.62, 0.48), px);

    // Cúpula dourada sobre o tambor azul.
    {
        vec2 q = p - vec2(aspect * 0.33, 0.445);
        float body = box(q - vec2(0.0, 0.012), vec2(0.056, 0.022));
        float drum = box(q - vec2(0.0, 0.046), vec2(0.032, 0.012));
        float dome = max(length(q - vec2(0.0, 0.056)) - 0.036, 0.056 - q.y);
        float spire = box(q - vec2(0.0, 0.100), vec2(0.0018, 0.012));
        vec3 bodyCol = mix(vec3(0.22, 0.50, 0.58), vec3(0.16, 0.38, 0.48), step(q.x, -0.016));
        bodyCol = mix(bodyCol, vec3(0.95, 0.84, 0.62), step(abs(q.y - 0.030), 0.003));
        float arch = archShape(vec2(mod(q.x + 0.014, 0.028) - 0.014, q.y - 0.006), vec2(0.0055, 0.008));
        bodyCol = mix(bodyCol, vec3(0.10, 0.22, 0.30), smoothstep(px, -px, arch));
        col = mix(col, bodyCol, smoothstep(px, -px, body));
        col = mix(col, mix(vec3(0.28, 0.56, 0.62), vec3(0.20, 0.42, 0.52), step(q.x, -0.010)),
                  smoothstep(px, -px, drum));
        vec3 gold = mix(vec3(0.98, 0.74, 0.24), vec3(0.86, 0.54, 0.16), step(q.x, -0.010));
        gold = mix(gold, vec3(1.00, 0.90, 0.56), smoothstep(px, -px, length(q - vec2(0.014, 0.076)) - 0.007));
        col = mix(col, gold, smoothstep(px, -px, min(dome, spire)));
    }

    col = houses(col, p, 0.315, 0.074, 31.0, vec3(0.96, 0.74, 0.54), vec3(0.84, 0.52, 0.40), px);

    // Igreja: torre, cúpula cinza-azulada e cruz.
    {
        vec2 q = p - vec2(aspect * 0.60, 0.40);
        float tower = box(q - vec2(0.0, 0.03), vec2(0.026, 0.060));
        float dome = max(length(q - vec2(0.0, 0.090)) - 0.026, 0.090 - q.y);
        float crossShape = min(box(q - vec2(0.0, 0.134), vec2(0.0020, 0.018)),
                               box(q - vec2(0.0, 0.139), vec2(0.0090, 0.0020)));
        vec3 tc = mix(vec3(0.98, 0.84, 0.66), vec3(0.84, 0.66, 0.52), step(q.x, -0.008));
        float arch = archShape(q - vec2(0.0, 0.058), vec2(0.007, 0.012));
        tc = mix(tc, vec3(0.34, 0.22, 0.24), smoothstep(px, -px, arch));
        col = mix(col, tc, smoothstep(px, -px, tower));
        col = mix(col, mix(vec3(0.50, 0.60, 0.68), vec3(0.38, 0.46, 0.56), step(q.x, -0.008)),
                  smoothstep(px, -px, dome));
        col = mix(col, vec3(0.30, 0.20, 0.22), smoothstep(px, -px, crossShape));
    }

    col = houses(col, p, 0.275, 0.090, 57.0, vec3(0.93, 0.66, 0.46), vec3(0.76, 0.44, 0.34), px);

    // Muralha com ameias, torres e o portão.
    {
        float seg = 0.36;
        float tx = (fract(p.x / seg + 0.3) - 0.5) * seg;
        float isTower = step(abs(tx), 0.034);
        float topY = 0.262 + isTower * 0.034;
        float teeth = step(0.5, fract(p.x / 0.022)) * 0.011;
        float d = uv.y - topY - teeth;
        vec3 wc = mix(vec3(0.86, 0.60, 0.40), vec3(0.74, 0.47, 0.32), isTower * step(tx, 0.0));
        // Fiadas de pedra.
        float row = floor(uv.y / 0.020);
        float brick = step(0.90, fract(uv.y / 0.020))
                    + step(0.95, fract(p.x / 0.045 + row * 0.5));
        wc = mix(wc, wc * 0.90, clamp(brick, 0.0, 1.0));
        float slit = box(vec2(tx, uv.y - 0.262), vec2(0.0028, 0.010));
        wc = mix(wc, vec3(0.34, 0.20, 0.20), smoothstep(px, -px, slit) * isTower);
        vec2 gq = p - vec2(aspect * 0.47, 0.19);
        float gate = archShape(gq, vec2(0.022, 0.030));
        wc = mix(wc, vec3(0.92, 0.70, 0.48), smoothstep(px, -px, gate - 0.007));
        wc = mix(wc, vec3(0.26, 0.15, 0.18), smoothstep(px, -px, gate));
        col = mix(col, wc, smoothstep(px, -px, d));
    }

    // Colina da frente, ciprestes e oliveiras.
    float f1 = 0.185 + sin(p.x * 1.9 + 0.5) * 0.040 + sin(p.x * 4.7) * 0.010;
    col = mix(col, vec3(0.18, 0.40, 0.38), smoothstep(px, -px, uv.y - f1));
    for (int i = 0; i < 9; i++) {
        float fi = float(i);
        float x = (fi + 0.2 + hash(fi + 40.0) * 0.6) / 9.0 * aspect;
        float y = 0.165 + sin(x * 1.9 + 0.5) * 0.040 + sin(x * 4.7) * 0.010;
        float r = hash(fi + 60.0);
        if (r > 0.35) {
            float c = cypress(p, vec2(x, y), 0.10 + r * 0.10, t);
            col = mix(col, vec3(0.08, 0.26, 0.28), smoothstep(px, -px, c));
        } else {
            vec2 q = p - vec2(x, y + 0.030);
            float c = min(length(q) - 0.030, length(q - vec2(0.024, -0.008)) - 0.020);
            c = min(c, box(q - vec2(0.0, -0.030), vec2(0.003, 0.014)));
            col = mix(col, vec3(0.26, 0.48, 0.40), smoothstep(px, -px, c));
        }
    }
    float f2 = 0.085 + sin(p.x * 2.4 + 2.2) * 0.030 + sin(p.x * 6.1 + 1.0) * 0.008;
    col = mix(col, vec3(0.10, 0.28, 0.30), smoothstep(px, -px, uv.y - f2));
    float f3 = 0.030 + sin(p.x * 3.1 + 4.0) * 0.018;
    col = mix(col, vec3(0.05, 0.17, 0.21), smoothstep(px, -px, uv.y - f3));

    fragColor = vec4(col, 1.0);
}
