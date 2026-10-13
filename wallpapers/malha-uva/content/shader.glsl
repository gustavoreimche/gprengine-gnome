// Gradiente de malha em outra paleta: roxos, lilás e rosa.

vec3 blob(vec2 p, vec2 center, vec3 color, float radius) {
    float d = length(p - center);
    return color * exp(-d * d / (radius * radius));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float t = iTime * 0.08 + 17.0;

    // Dobra o espaço um pouco, para as manchas não serem círculos perfeitos.
    p += 0.08 * vec2(sin(p.y * 2.3 + t * 1.7), cos(p.x * 1.9 - t * 1.3));

    vec3 col = vec3(0.06, 0.03, 0.12);
    col += blob(p, vec2(sin(t * 1.1) * 0.55, cos(t * 0.9) * 0.30), vec3(0.55, 0.20, 0.95), 0.55);
    col += blob(p, vec2(cos(t * 0.7 + 1.0) * 0.60, sin(t * 1.3 + 2.0) * 0.35), vec3(0.90, 0.35, 0.85), 0.60);
    col += blob(p, vec2(sin(t * 0.5 + 4.0) * 0.45, cos(t * 0.6 + 0.5) * 0.40), vec3(0.30, 0.25, 0.90), 0.45);
    col += blob(p, vec2(cos(t * 0.9 + 3.0) * 0.70, sin(t * 0.4 + 5.0) * 0.25), vec3(0.95, 0.55, 0.75), 0.50);

    // Compressão suave: onde as manchas se somam a cor satura sem estourar.
    col = col / (1.0 + col * 0.55);
    fragColor = vec4(col, 1.0);
}
