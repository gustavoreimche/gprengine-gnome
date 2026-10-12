// Camadas de um sistema, em perspectiva isométrica, flutuando em ritmos
// diferentes, com dados subindo e descendo entre elas.

const float W = 0.34;          // meia largura do losango
const float H = 0.17;          // meia altura
const float T = 0.050;         // espessura da placa

// Valor < 1 dentro da face de cima.
float topFace(vec2 q) {
    return abs(q.x) / W + abs(q.y) / H;
}

// Valor < 1 dentro da placa inteira (face de cima mais as laterais).
float slab(vec2 q) {
    float below = q.y > 0.0 ? q.y : (q.y < -T ? -(q.y + T) : 0.0);
    return abs(q.x) / W + below / H;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float px = 1.5 / iResolution.y;

    // Fundo em faixas largas, como degraus de luz.
    float band = floor((p.y - p.x * 0.35 + 0.6) * 5.0) / 5.0;
    vec3 col = mix(vec3(0.06, 0.07, 0.14), vec3(0.11, 0.12, 0.24), band);

    // Sombra no chão.
    float ground = topFace((p - vec2(0.0, -0.40)) * vec2(1.0, 1.25));
    col = mix(col, vec3(0.03, 0.04, 0.09), smoothstep(1.0 + px * 6.0, 1.0 - px * 6.0, ground) * 0.6);

    vec3 hues[4] = vec3[4](vec3(0.98, 0.62, 0.28), vec3(0.42, 0.80, 0.62),
                           vec3(0.38, 0.62, 1.00), vec3(0.78, 0.52, 1.00));

    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float y = -0.30 + fi * 0.165 + sin(iTime * 0.7 + fi * 1.3) * 0.012;
        vec2 q = p - vec2(0.0, y);
        float s = slab(q);
        float t = topFace(q);
        float edge = fwidth(s) * 1.2;
        vec3 hue = hues[i];
        vec3 side = q.x < 0.0 ? hue * 0.62 : hue * 0.42;
        vec3 face = hue;

        // Na face de cima: uma grade fina e alguns blocos acesos.
        vec2 iso = vec2(q.x / W + q.y / H, q.x / W - q.y / H) * 3.0;
        vec2 cell = floor(iso);
        vec2 f = fract(iso);
        float grid = smoothstep(0.06, 0.03, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
        float lit = step(0.72, fract(sin(dot(cell, vec2(12.9898, 78.233)) + fi) * 43758.5453
                                     + floor(iTime * 0.5 + fi) * 0.37));
        face = mix(face, hue * 1.25, lit * (1.0 - grid));
        face = mix(face, hue * 0.80, grid);

        vec3 paint = t < 1.0 ? face : side;
        // Quina entre as duas laterais.
        if (t >= 1.0)
            paint *= 1.0 - 0.25 * smoothstep(px * 2.0, 0.0, abs(q.x));
        col = mix(col, paint, smoothstep(1.0 + edge, 1.0 - edge, s));
        // Aresta clara na borda da face de cima.
        float te = fwidth(t) * 1.5;
        col = mix(col, hue * 1.35, smoothstep(te * 2.0, 0.0, abs(t - 1.0)) * step(-0.001, q.y)
                  * step(s, 1.0));
    }

    // Dados: pontos subindo por duas colunas, entre as placas.
    for (int i = 0; i < 2; i++) {
        float fi = float(i);
        float cx = (fi - 0.5) * 0.86;
        float span = 0.62;
        for (int k = 0; k < 5; k++) {
            float fk = float(k);
            float u = fract(iTime * 0.16 + fk / 5.0 + fi * 0.37);
            float yy = -0.36 + (fi < 0.5 ? u : 1.0 - u) * span;
            float d = length(p - vec2(cx, yy));
            col = mix(col, vec3(0.92, 0.96, 1.00),
                      smoothstep(0.011 + px, 0.011, d) * sin(u * 3.14159));
        }
        col = mix(col, vec3(0.30, 0.36, 0.55),
                  smoothstep(0.0025 + px, 0.0025, abs(p.x - cx))
                  * step(-0.36, p.y) * step(p.y, 0.26) * 0.5);
    }

    fragColor = vec4(col, 1.0);
}
