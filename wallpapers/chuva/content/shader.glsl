// Chuva caindo à noite, em três planos de distância.

float hash(float n) {
    return fract(sin(n * 78.233) * 43758.5453);
}

float layer(vec2 uv, float scale, float speed, float seed) {
    uv.x += uv.y * 0.12;                 // leve inclinação do vento
    uv *= vec2(scale, scale * 0.16);
    float column = floor(uv.x);
    float offset = hash(column + seed);
    float y = uv.y + iTime * speed * (0.7 + 0.6 * offset) + offset * 30.0;
    float drop = fract(y);
    // Só algumas colunas têm gota, e o rastro some para cima.
    float present = step(0.55, hash(column * 1.7 + floor(y) + seed));
    float streak = smoothstep(0.0, 0.08, drop) * smoothstep(0.75, 0.08, drop);
    float width = smoothstep(0.42, 0.50, 0.5 - abs(fract(uv.x) - 0.5));
    return present * streak * width;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 p = vec2(uv.x * iResolution.x / iResolution.y, uv.y);

    vec3 col = mix(vec3(0.02, 0.04, 0.08), vec3(0.06, 0.10, 0.17), uv.y);
    // Luzes da cidade, desfocadas, perto do horizonte.
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        vec2 c = vec2(hash(fi + 3.0) * iResolution.x / iResolution.y,
                      0.10 + hash(fi + 9.0) * 0.22);
        vec3 tint = mix(vec3(1.0, 0.62, 0.25), vec3(0.35, 0.65, 1.0), hash(fi + 5.0));
        float pulse = 0.8 + 0.2 * sin(iTime * 0.6 + fi * 2.0);
        col += tint * exp(-dot(p - c, p - c) * 38.0) * 0.30 * pulse;
    }

    col += vec3(0.55, 0.68, 0.85) * layer(p, 90.0, 2.6, 1.0) * 0.16;
    col += vec3(0.60, 0.74, 0.92) * layer(p, 55.0, 3.4, 7.0) * 0.26;
    col += vec3(0.75, 0.85, 1.00) * layer(p, 30.0, 4.4, 13.0) * 0.38;
    fragColor = vec4(col, 1.0);
}
