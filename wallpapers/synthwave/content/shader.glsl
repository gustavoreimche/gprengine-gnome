// Grade em perspectiva correndo para um sol listrado.

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float horizon = 0.02;
    vec3 col;

    if (p.y > horizon) {
        col = mix(vec3(0.55, 0.10, 0.45), vec3(0.04, 0.02, 0.14),
                  smoothstep(horizon, 0.5, p.y));
        vec2 s = p - vec2(0.0, horizon + 0.16);
        float d = length(s);
        float px = 1.5 / iResolution.y;
        float disk = smoothstep(0.20 + px, 0.20 - px, d);
        // Faixas que sobem devagar e engrossam perto da base.
        float band = fract(s.y * 14.0 - iTime * 0.25);
        float cut = smoothstep(0.0, 0.08, band - mix(0.75, 0.15, clamp((s.y + 0.20) / 0.30, 0.0, 1.0)));
        vec3 sun = mix(vec3(1.00, 0.25, 0.55), vec3(1.00, 0.85, 0.30),
                       clamp((s.y + 0.20) / 0.40, 0.0, 1.0));
        col = mix(col, sun, disk * (s.y > 0.0 ? 1.0 : cut));
        col += vec3(1.0, 0.3, 0.6) * exp(-d * 5.0) * 0.25;
    } else {
        // z cresce até o infinito no horizonte; a grade vive em (x*z, z).
        float z = 1.0 / (horizon - p.y + 0.001);
        vec2 g = vec2(p.x * z * 1.5, z * 1.5 + iTime * 0.8);
        vec2 dist = 0.5 - abs(fract(g) - 0.5);
        // Quanto da grade cabe num pixel, em cada eixo: a linha engrossa na
        // mesma medida, para ter largura constante na tela e não serrilhar.
        vec2 pixel = vec2(z, z * z) * 1.5 / iResolution.y;
        vec2 width = pixel * 1.6 + 0.004;
        vec2 lines = 1.0 - smoothstep(vec2(0.0), width, dist);
        float fade = exp(-z * 0.10);
        col = vec3(0.04, 0.01, 0.10);
        col += vec3(0.95, 0.20, 0.75) * max(lines.x, lines.y) * fade;
        col += vec3(0.55, 0.10, 0.45) * exp(-(horizon - p.y) * 14.0) * 0.6;
    }

    fragColor = vec4(col, 1.0);
}
