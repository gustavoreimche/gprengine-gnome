// Luzes desfocadas subindo devagar.

float hash(float n) {
    return fract(sin(n * 91.345) * 47453.5453);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;
    vec2 p = vec2(uv.x * aspect, uv.y);

    vec3 col = mix(vec3(0.10, 0.05, 0.16), vec3(0.02, 0.03, 0.09), uv.y);

    for (int i = 0; i < 28; i++) {
        float fi = float(i);
        float size = mix(0.035, 0.13, hash(fi + 0.3));
        float speed = mix(0.012, 0.035, hash(fi + 1.7));
        // A altura dá a volta com folga, para o círculo entrar e sair inteiro.
        float y = fract(hash(fi + 2.9) + iTime * speed) * (1.0 + 2.0 * size) - size;
        float x = hash(fi + 4.1) * aspect + sin(iTime * 0.15 + fi) * 0.03;
        float d = length(p - vec2(x, y));
        float disk = smoothstep(size, size * 0.82, d);
        float rim = smoothstep(size * 0.70, size, d) * disk;
        vec3 tint = mix(vec3(1.00, 0.55, 0.30), vec3(0.35, 0.60, 1.00), hash(fi + 5.5));
        tint = mix(tint, vec3(1.00, 0.35, 0.65), step(0.7, hash(fi + 6.6)));
        float pulse = 0.75 + 0.25 * sin(iTime * 0.5 + fi * 2.3);
        col += tint * (disk * 0.10 + rim * 0.07) * pulse;
    }

    fragColor = vec4(col, 1.0);
}
