// Vagalumes numa clareira ao anoitecer.

float hash(float n) {
    return fract(sin(n * 127.1) * 43758.5453);
}

float ridge(float x, float scale, float seed) {
    return sin(x * scale + seed) * 0.5 + sin(x * scale * 2.3 + seed * 1.7) * 0.25
         + sin(x * scale * 5.1 + seed * 0.3) * 0.12;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;
    vec2 p = vec2(uv.x * aspect, uv.y);
    float px = 1.5 / iResolution.y;

    vec3 col = mix(vec3(0.20, 0.30, 0.34), vec3(0.03, 0.06, 0.13),
                   smoothstep(0.15, 0.95, uv.y));
    // Lua baixa e o halo dela.
    float moon = length(p - vec2(aspect * 0.72, 0.74));
    col += vec3(0.95, 0.95, 0.80) * smoothstep(0.055 + px, 0.055 - px, moon);
    col += vec3(0.50, 0.60, 0.55) * exp(-moon * 5.0) * 0.35;

    // Três linhas de árvores, mais escuras quanto mais perto.
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float top = 0.42 - fi * 0.13 + ridge(p.x, 2.2 + fi * 1.4, fi * 11.0) * 0.06
                  + abs(sin(p.x * (26.0 + fi * 9.0) + fi)) * 0.030;
        vec3 shade = mix(vec3(0.07, 0.14, 0.15), vec3(0.01, 0.03, 0.04), fi / 2.0);
        col = mix(col, shade, smoothstep(top + px, top - px, uv.y));
    }

    for (int i = 0; i < 34; i++) {
        float fi = float(i);
        float t = iTime * (0.05 + hash(fi + 1.0) * 0.06);
        vec2 c = vec2(hash(fi + 2.0) * aspect + sin(t * 2.1 + fi) * 0.07,
                      0.06 + hash(fi + 3.0) * 0.50 + sin(t * 1.7 + fi * 2.0) * 0.05);
        float blink = pow(0.5 + 0.5 * sin(iTime * (0.6 + hash(fi + 4.0)) + fi * 5.0), 4.0);
        float d = length(p - c);
        col += vec3(0.85, 1.00, 0.35) * blink
             * (smoothstep(0.006, 0.0, d) + exp(-d * 60.0) * 0.35);
    }

    fragColor = vec4(col, 1.0);
}
