// O símbolo </> em flat design, com sombra longa e faixas ao fundo.

float segment(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

float symbol(vec2 p) {
    float d = segment(p, vec2(-0.47, 0.0), vec2(-0.27, 0.17));
    d = min(d, segment(p, vec2(-0.47, 0.0), vec2(-0.27, -0.17)));
    d = min(d, segment(p, vec2(0.47, 0.0), vec2(0.27, 0.17)));
    d = min(d, segment(p, vec2(0.47, 0.0), vec2(0.27, -0.17)));
    d = min(d, segment(p, vec2(-0.085, -0.22), vec2(0.085, 0.22)));
    return d - 0.034;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float px = 1.5 / iResolution.y;

    // Fundo: faixas diagonais em tons próximos, deslizando devagar.
    float stripe = (p.x + p.y) * 2.2 + iTime * 0.04;
    float id = floor(stripe);
    float tone = fract(sin(id * 12.9898) * 43758.5453);
    vec3 col = mix(vec3(0.07, 0.17, 0.30), vec3(0.10, 0.25, 0.42), tone);
    float seam = min(fract(stripe), 1.0 - fract(stripe));
    col *= 1.0 - 0.10 * smoothstep(px * 2.2, 0.0, seam);

    // Sombra longa: o símbolo arrastado na diagonal para baixo.
    vec2 dir = normalize(vec2(1.0, -1.0));
    float shadow = 1.0;
    for (int i = 1; i <= 40; i++)
        shadow = min(shadow, symbol(p - dir * float(i) * 0.02));
    float reach = smoothstep(0.9, 0.2, length(p));
    col = mix(col, vec3(0.03, 0.09, 0.18), smoothstep(px, -px, shadow) * 0.75 * reach);

    float breath = 0.5 + 0.5 * sin(iTime * 0.8);
    float d = symbol(p - vec2(0.0, breath * 0.006));
    vec3 ink = mix(vec3(0.96, 0.98, 1.00), vec3(0.55, 0.92, 1.00),
                   smoothstep(-0.25, 0.25, p.y));
    col = mix(col, ink, smoothstep(px, -px, d));

    // Cursor piscando depois do símbolo.
    vec2 c = p - vec2(0.60, -0.17);
    float cursor = max(abs(c.x) - 0.045, abs(c.y) - 0.016);
    col = mix(col, ink, smoothstep(px, -px, cursor) * step(0.5, fract(iTime * 0.9)));

    fragColor = vec4(col, 1.0);
}
