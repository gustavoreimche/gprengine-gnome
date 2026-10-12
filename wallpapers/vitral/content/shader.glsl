// Vitral de igreja: uma cruz no centro, vidro colorido e linhas de chumbo.

vec2 hash2(vec2 p) {
    return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(41.3, 289.1))) * 45758.5453);
}

float box(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Janela em arco ogival. Negativo dentro.
float arch(vec2 p, float w, float base, float spring) {
    if (p.y < spring)
        return max(abs(p.x) - w, base - p.y);
    return max(length(p - vec2(-w, spring)), length(p - vec2(w, spring))) - 2.0 * w;
}

// Distância até a borda da célula de Voronoi, e o sorteio da célula.
vec2 panes(vec2 x) {
    vec2 n = floor(x), f = fract(x);
    vec2 nearest = vec2(0.0), offset = vec2(0.0);
    float best = 8.0;
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        vec2 g = vec2(float(i), float(j));
        vec2 r = g + hash2(n + g) - f;
        float d = dot(r, r);
        if (d < best) { best = d; nearest = r; offset = g; }
    }
    float border = 8.0;
    for (int j = -2; j <= 2; j++)
    for (int i = -2; i <= 2; i++) {
        vec2 g = offset + vec2(float(i), float(j));
        vec2 r = g + hash2(n + g) - f;
        if (dot(nearest - r, nearest - r) > 0.00001)
            border = min(border, dot(0.5 * (nearest + r), normalize(r - nearest)));
    }
    return vec2(border, hash(n + offset));
}

vec3 jewel(float h) {
    if (h < 0.26) return vec3(0.10, 0.25, 0.75);
    if (h < 0.46) return vec3(0.72, 0.10, 0.16);
    if (h < 0.62) return vec3(0.08, 0.50, 0.40);
    if (h < 0.80) return vec3(0.45, 0.16, 0.62);
    return vec3(0.95, 0.62, 0.14);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float px = 1.5 / iResolution.y;
    float window = arch(p, 0.27, -0.46, -0.06);

    vec2 heart = p - vec2(0.0, 0.06);
    float crossD = min(box(p - vec2(0.0, -0.07), vec2(0.034, 0.30)),
                       box(heart, vec2(0.15, 0.034)));
    float halo = abs(length(heart) - 0.19) - 0.022;
    float rim = window + 0.035;                    // faixa de contorno

    vec2 cell = panes(p * 8.0);
    vec3 glass = jewel(cell.y);
    float lead = smoothstep(0.045, 0.045 - px * 8.0, cell.x);
    float shade = cell.y;

    if (rim > 0.0) {
        // Contorno: quadrinhos vermelhos e azuis alternados.
        float along = floor((atan(p.y + 0.06, p.x) * 3.0 + p.y * 14.0));
        glass = mod(along, 2.0) < 1.0 ? vec3(0.70, 0.10, 0.15) : vec3(0.12, 0.22, 0.65);
        lead = 0.0;
        shade = fract(along * 0.37);
    }
    if (halo < 0.0) {
        float slice = floor(atan(heart.y, heart.x) / 6.2831853 * 16.0);
        glass = mod(slice, 2.0) < 1.0 ? vec3(1.00, 0.72, 0.18) : vec3(0.98, 0.55, 0.12);
        lead = 0.0;
        shade = fract(slice * 0.41);
    }
    if (crossD < 0.0) {
        glass = vec3(1.00, 0.95, 0.80);
        lead = 0.0;
        shade = 0.9;
    }

    // A luz de fora muda devagar: cada vidro clareia e escurece no seu ritmo,
    // e uma claridade larga atravessa a janela.
    float sweep = 0.5 + 0.5 * sin(p.x * 2.0 + p.y * 3.0 - iTime * 0.25);
    float light = 0.62 + 0.20 * sin(iTime * (0.2 + shade * 0.5) + shade * 30.0) + 0.28 * sweep;
    // A cruz é o vidro mais claro da janela: nunca escurece de todo.
    if (crossD < 0.0)
        light = max(light, 0.92);
    vec3 col = glass * light;

    float lines = lead;
    lines = max(lines, smoothstep(0.006 + px, 0.006, abs(crossD)));
    lines = max(lines, smoothstep(0.005 + px, 0.005, abs(halo)) * step(0.0, crossD));
    lines = max(lines, smoothstep(0.005 + px, 0.005, abs(rim)));
    col = mix(col, vec3(0.03, 0.03, 0.04), lines);

    // Parede de pedra, com a cor da janela derramando um pouco.
    vec3 wall = vec3(0.060, 0.055, 0.070) + vec3(0.02) * hash(floor(p * vec2(9.0, 22.0)));
    wall += glass * exp(-max(window, 0.0) * 9.0) * 0.10 * light;
    vec3 frame = vec3(0.20, 0.18, 0.17);
    wall = mix(wall, frame, smoothstep(0.028 + px, 0.028, window));
    col = mix(col, wall, smoothstep(-px, px, window));

    fragColor = vec4(col, 1.0);
}
