// Cortinas de aurora sobre um céu noturno.

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * noise(p);
        p = p * 2.03 + 7.1;
        a *= 0.5;
    }
    return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;
    float t = iTime * 0.06;

    vec3 col = mix(vec3(0.02, 0.03, 0.08), vec3(0.01, 0.01, 0.03), uv.y);

    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float x = uv.x * aspect * (0.9 + fi * 0.35);
        float wave = fbm(vec2(x + t * (1.0 + fi * 0.4), fi * 3.7 + t));
        float base = 0.30 + fi * 0.12 + (wave - 0.5) * 0.35;
        float d = uv.y - base;
        float curtain = smoothstep(0.0, 0.04, d) * exp(-d * (4.5 - fi));
        float rays = 0.55 + 0.45 * noise(vec2(x * 14.0 + t * 3.0, fi));
        vec3 tint = mix(vec3(0.10, 0.95, 0.55), vec3(0.45, 0.25, 0.95),
                        clamp(d * 2.2 + fi * 0.2, 0.0, 1.0));
        col += tint * curtain * rays * (0.55 - fi * 0.12);
    }

    // Estrelas numa grade em unidades de tela, não em pixels: a mesma
    // quantidade em qualquer resolução.
    vec2 sp = vec2(uv.x * aspect, uv.y) * 80.0;
    vec2 cell = floor(sp);
    float seed = hash(cell);
    vec2 center = cell + 0.5 + (vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5) * 0.7;
    float star = step(0.965, seed) * smoothstep(0.15, 0.0, length(sp - center));
    float twinkle = 0.6 + 0.4 * sin(iTime * 1.5 + seed * 6.283);
    col += vec3(star * twinkle * smoothstep(0.25, 0.9, uv.y));

    fragColor = vec4(col, 1.0);
}
