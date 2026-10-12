// Camadas de ondas suaves, do horizonte para a frente.

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float x = uv.x * iResolution.x / iResolution.y;
    float t = iTime * 0.12;

    vec3 col = mix(vec3(0.98, 0.72, 0.55), vec3(0.20, 0.16, 0.38), uv.y);
    // Sol baixo atrás das ondas.
    float sun = length(vec2(x - 0.5 * iResolution.x / iResolution.y, uv.y - 0.62));
    col += vec3(1.0, 0.75, 0.45) * smoothstep(0.42, 0.0, sun) * 0.55;

    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float depth = fi / 5.0;
        float base = 0.58 - depth * 0.50;
        float wave = sin(x * (1.6 + fi * 0.5) + t * (1.0 + fi * 0.35) + fi * 1.9) * 0.035
                   + sin(x * (3.7 + fi) - t * (0.7 + fi * 0.2) + fi * 4.1) * 0.015;
        float edge = base + wave * (0.6 + depth);
        vec3 layer = mix(vec3(0.42, 0.30, 0.55), vec3(0.05, 0.07, 0.20), depth);
        float px = 1.5 / iResolution.y;
        col = mix(col, layer, smoothstep(edge + px, edge - px, uv.y));
    }

    fragColor = vec4(col, 1.0);
}
