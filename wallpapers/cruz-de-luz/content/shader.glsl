// Uma cruz de luz no escuro, com raios e poeira dourada.

float hash(float n) {
    return fract(sin(n * 127.1) * 43758.5453);
}

float box(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float aspect = iResolution.x / iResolution.y;
    float px = 1.5 / iResolution.y;

    // Haste e travessa; o cruzamento fica acima do centro da tela.
    vec2 c = p - vec2(0.0, 0.02);
    float d = min(box(c, vec2(0.016, 0.30)),
                  box(c - vec2(0.0, 0.11), vec2(0.15, 0.016)));
    vec2 heart = c - vec2(0.0, 0.11);
    float r = length(heart);

    vec3 col = mix(vec3(0.05, 0.04, 0.10), vec3(0.01, 0.01, 0.03),
                   smoothstep(0.0, 0.9, length(p)));

    float breath = 0.85 + 0.15 * sin(iTime * 0.5);
    float a = atan(heart.y, heart.x);
    float rays = pow(0.5 + 0.5 * sin(a * 12.0 + iTime * 0.07), 3.0)
               + pow(0.5 + 0.5 * sin(a * 7.0 - iTime * 0.05), 3.0) * 0.6;
    col += vec3(1.00, 0.78, 0.42) * rays * exp(-r * 2.6) * 0.22 * breath;
    col += vec3(1.00, 0.80, 0.48) * exp(-max(d, 0.0) * 9.0) * 0.55 * breath;
    col += vec3(1.00, 0.90, 0.65) * exp(-max(d, 0.0) * 40.0) * 0.6;
    col = mix(col, vec3(1.00, 0.98, 0.92), smoothstep(px, -px, d));

    // Poeira subindo devagar.
    vec2 q = vec2(p.x + 0.5 * aspect, p.y + 0.5);
    for (int i = 0; i < 40; i++) {
        float fi = float(i);
        float y = fract(hash(fi + 1.0) + iTime * (0.008 + hash(fi + 2.0) * 0.012));
        vec2 at = vec2(hash(fi + 3.0) * aspect + sin(iTime * 0.2 + fi) * 0.02, y);
        float twinkle = 0.5 + 0.5 * sin(iTime * (0.8 + hash(fi + 4.0)) + fi * 3.0);
        float dist = length(q - at);
        col += vec3(1.00, 0.85, 0.55) * smoothstep(0.004, 0.0, dist)
             * twinkle * sin(y * 3.14159) * 0.8;
    }

    fragColor = vec4(col, 1.0);
}
