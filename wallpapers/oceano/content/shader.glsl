// Fundo do mar raso, com os reflexos de luz da superfície.

float caustic(vec2 p, float t) {
    // Rede de luz: soma de ondas dobradas umas pelas outras.
    vec2 q = p;
    float c = 0.0;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        q += vec2(cos(t + q.y * 1.3 + fi), sin(t * 0.9 + q.x * 1.1 - fi)) * 0.45;
        c += 1.0 / (1.0 + abs(sin(q.x + t) + cos(q.y - t * 0.8)) * 6.0);
    }
    return c / 4.0;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float t = iTime * 0.35;

    float light = caustic(p * 7.0, t);
    vec3 deep = vec3(0.00, 0.10, 0.22), shallow = vec3(0.02, 0.42, 0.55);
    vec3 col = mix(deep, shallow, uv.y * 0.8 + 0.1);
    col += vec3(0.55, 0.95, 0.90) * pow(light, 2.0) * 0.9;

    // Feixes de luz descendo da superfície.
    float rays = 0.5 + 0.5 * sin(p.x * 9.0 + p.y * 2.5 + sin(t * 0.7 + p.x * 3.0) * 1.5);
    col += vec3(0.30, 0.70, 0.75) * pow(rays, 4.0) * uv.y * 0.22;
    col *= 1.0 - 0.45 * dot(p, p);
    fragColor = vec4(col, 1.0);
}
