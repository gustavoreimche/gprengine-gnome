// Rede de nós que derivam devagar; os próximos se ligam por linhas.

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(41.3, 289.1))) * 45758.5453);
}

vec2 node(vec2 id) {
    float h = hash(id);
    float k = hash(id + 7.3);
    return id + 0.5 + 0.34 * vec2(sin(iTime * (0.15 + h * 0.2) + h * 30.0),
                                  cos(iTime * (0.13 + k * 0.2) + k * 30.0));
}

float segment(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float scale = 5.5;
    vec2 g = p * scale;
    vec2 id = floor(g);
    float px = scale * 1.5 / iResolution.y;

    vec2 pts[9];
    for (int j = 0; j < 3; j++)
    for (int i = 0; i < 3; i++)
        pts[j * 3 + i] = node(id + vec2(float(i) - 1.0, float(j) - 1.0));

    vec3 col = mix(vec3(0.045, 0.060, 0.110), vec3(0.020, 0.028, 0.060), length(p));
    vec3 line = vec3(0.30, 0.55, 0.95);

    // Liga cada par de nós vizinhos; a linha some à medida que eles se afastam.
    float edges = 0.0;
    for (int a = 0; a < 9; a++)
    for (int b = a + 1; b < 9; b++) {
        float len = length(pts[a] - pts[b]);
        float strength = smoothstep(1.25, 0.70, len);
        if (strength <= 0.0)
            continue;
        float d = segment(g, pts[a], pts[b]);
        edges = max(edges, smoothstep(0.018 + px, 0.018, d) * strength);
    }
    col = mix(col, line, edges * 0.75);

    for (int a = 0; a < 9; a++) {
        float h = hash(floor(pts[a]) + 3.0);
        float radius = 0.045 + h * 0.045;
        float d = length(g - pts[a]);
        vec3 tint = h > 0.80 ? vec3(1.00, 0.72, 0.35) : vec3(0.60, 0.85, 1.00);
        col = mix(col, tint, smoothstep(radius + px, radius, d));
        col = mix(col, vec3(0.045, 0.060, 0.110), smoothstep(radius * 0.45 + px, radius * 0.45, d)
                  * step(0.80, h));
    }

    fragColor = vec4(col, 1.0);
}
