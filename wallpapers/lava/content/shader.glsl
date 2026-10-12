// Bolhas que se fundem e se separam, como numa luminária de lava.

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float t = iTime * 0.18;

    float field = 0.0;
    for (int i = 0; i < 9; i++) {
        float fi = float(i);
        vec2 c = vec2(sin(t * (0.5 + fi * 0.07) + fi * 2.4) * 0.75,
                      sin(t * (0.35 + fi * 0.05) + fi * 1.3) * 0.48);
        float r = 0.10 + 0.05 * sin(fi * 3.7);
        vec2 d = p - c;
        field += r * r / dot(d, d);
    }

    float edge = smoothstep(0.95, 1.05, field);
    float core = smoothstep(1.0, 2.6, field);
    vec3 bg = mix(vec3(0.10, 0.02, 0.12), vec3(0.03, 0.01, 0.06), length(p));
    bg += vec3(0.9, 0.25, 0.10) * smoothstep(0.35, 1.0, field) * 0.18;
    vec3 blob = mix(vec3(0.95, 0.22, 0.20), vec3(1.00, 0.78, 0.25), core);
    fragColor = vec4(mix(bg, blob, edge), 1.0);
}
