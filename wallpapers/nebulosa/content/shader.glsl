// Nuvens de gás dobradas por ruído, com estrelas ao fundo.

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
        p = p * 2.02 + vec2(13.1, 7.7);
        a *= 0.5;
    }
    return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float t = iTime * 0.025;

    vec2 q = vec2(fbm(p * 1.4 + t), fbm(p * 1.4 + vec2(5.2, 1.3) - t));
    float n = fbm(p * 1.8 + q * 1.6 + vec2(t * 0.6, 0.0));

    vec3 col = vec3(0.02, 0.02, 0.06);
    col = mix(col, vec3(0.35, 0.10, 0.55), smoothstep(0.30, 0.75, n));
    col = mix(col, vec3(0.95, 0.35, 0.50), smoothstep(0.55, 0.90, n) * q.x);
    col = mix(col, vec3(0.20, 0.60, 0.95), smoothstep(0.45, 0.85, q.y) * 0.45);

    // Estrelas num grade fixa em unidades de tela, não em pixels: a mesma
    // quantidade em qualquer resolução.
    vec2 sp = p * 90.0;
    vec2 cell = floor(sp);
    float seed = hash(cell);
    vec2 center = cell + 0.5 + (vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5) * 0.7;
    float star = step(0.93, seed) * smoothstep(0.16, 0.0, length(sp - center));
    float twinkle = 0.65 + 0.35 * sin(iTime * (0.8 + seed * 2.0) + seed * 40.0);
    col += vec3(star * twinkle) * (1.0 - smoothstep(0.4, 0.8, n));

    fragColor = vec4(col, 1.0);
}
