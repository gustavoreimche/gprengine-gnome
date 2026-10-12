// As três cruzes sobre montes em camadas, com o sol abrindo em leque.

float box(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float crossShape(vec2 p, float s) {
    return min(box(p - vec2(0.0, s * 0.5), vec2(s * 0.040, s * 0.5)),
               box(p - vec2(0.0, s * 0.70), vec2(s * 0.21, s * 0.040)));
}

float capsule(vec2 p, float halfLength, float radius) {
    p.x -= clamp(p.x, -halfLength, halfLength);
    return length(p) - radius;
}

float front(float x) {
    return -0.26 - x * x * 0.22;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float aspect = iResolution.x / iResolution.y;
    float px = 1.5 / iResolution.y;
    vec2 sun = vec2(0.0, -0.10);
    vec2 d = p - sun;

    // Céu em faixas, do roxo ao dourado.
    vec3 col = vec3(0.16, 0.12, 0.30);
    col = mix(col, vec3(0.36, 0.18, 0.40), smoothstep(px, -px, p.y - 0.34));
    col = mix(col, vec3(0.66, 0.26, 0.40), smoothstep(px, -px, p.y - 0.20));
    col = mix(col, vec3(0.93, 0.44, 0.34), smoothstep(px, -px, p.y - 0.07));
    col = mix(col, vec3(0.99, 0.68, 0.36), smoothstep(px, -px, p.y + 0.05));

    // Leque de raios: gomos alternados, girando muito devagar.
    float turn = atan(d.y, d.x) / 6.2831853 * 28.0 + iTime * 0.02;
    float wedge = abs(fract(turn) - 0.5);
    float edge = fwidth(turn) * 1.2;
    col += vec3(0.10, 0.07, 0.03) * smoothstep(0.25 - edge, 0.25 + edge, wedge);

    float r = length(d);
    col = mix(col, vec3(1.00, 0.84, 0.52), smoothstep(px, -px, r - 0.30) * 0.45);
    col = mix(col, vec3(1.00, 0.95, 0.76), smoothstep(px, -px, r - 0.20));

    // Nuvens: cápsulas chapadas, à deriva.
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float span = aspect + 0.8;
        float x = mod(fi * 0.71 * span + iTime * (0.006 + fi * 0.0015), span) - span * 0.5;
        vec2 c = vec2(x, 0.16 + fract(fi * 0.37) * 0.26);
        float cloud = min(capsule(p - c, 0.10 + fract(fi * 0.53) * 0.08, 0.013),
                          capsule(p - c - vec2(0.05, 0.022), 0.06, 0.011));
        col = mix(col, vec3(0.99, 0.80, 0.62), smoothstep(px, -px, cloud) * 0.70);
    }

    // Montes ao fundo, cada camada mais escura.
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float top = -0.10 - fi * 0.055 + sin(p.x * (1.5 + fi * 0.9) + fi * 2.6) * 0.045
                  + sin(p.x * (3.7 + fi * 1.3) + fi) * 0.014;
        vec3 shade = mix(vec3(0.52, 0.22, 0.36), vec3(0.20, 0.10, 0.24), fi / 2.0);
        col = mix(col, shade, smoothstep(px, -px, p.y - top));
    }

    float shape = p.y - front(p.x);
    shape = min(shape, crossShape(p - vec2(0.0, front(0.0) - 0.01), 0.42));
    shape = min(shape, crossShape(p - vec2(-0.38, front(-0.38) - 0.01), 0.29));
    shape = min(shape, crossShape(p - vec2(0.38, front(0.38) - 0.01), 0.29));
    col = mix(col, vec3(0.07, 0.04, 0.10), smoothstep(px, -px, shape));

    fragColor = vec4(col, 1.0);
}
