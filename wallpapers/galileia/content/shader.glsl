// Amanhecer no mar da Galileia: sol, colinas ao longe e um barco de pesca.

float box(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float wave(float x, float i, float t) {
    return sin(x * (1.8 + i * 0.6) + t * (0.9 + i * 0.3) + i * 1.9) * 0.014
         + sin(x * (4.1 + i) - t * (0.6 + i * 0.2) + i * 4.1) * 0.006;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;
    vec2 p = vec2(uv.x * aspect, uv.y);
    float px = 1.5 / iResolution.y;
    float t = iTime * 0.25;

    // Céu em quatro faixas chapadas.
    vec3 col = vec3(0.99, 0.80, 0.52);
    col = mix(col, vec3(0.96, 0.66, 0.46), smoothstep(-px, px, uv.y - 0.60));
    col = mix(col, vec3(0.62, 0.52, 0.56), smoothstep(-px, px, uv.y - 0.74));
    col = mix(col, vec3(0.30, 0.38, 0.50), smoothstep(-px, px, uv.y - 0.88));

    vec2 sun = vec2(aspect * 0.66, 0.60);
    float ds = length(p - sun);
    col = mix(col, vec3(1.00, 0.86, 0.60), smoothstep(px, -px, ds - 0.21) * 0.45);
    col = mix(col, vec3(1.00, 0.91, 0.68), smoothstep(px, -px, ds - 0.15) * 0.60);
    col = mix(col, vec3(1.00, 0.97, 0.86), smoothstep(px, -px, ds - 0.095));

    // Colinas da outra margem.
    float far = 0.50 + sin(p.x * 1.7 + 1.0) * 0.035 + sin(p.x * 4.3) * 0.012;
    col = mix(col, vec3(0.42, 0.50, 0.58), smoothstep(px, -px, uv.y - far));
    float near = 0.47 + sin(p.x * 2.6 + 4.0) * 0.030 + sin(p.x * 6.1 + 2.0) * 0.010;
    col = mix(col, vec3(0.24, 0.36, 0.44), smoothstep(px, -px, uv.y - near));

    // Água em camadas; o barco fica entre a segunda e a terceira.
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float edge = 0.44 - fi * 0.075 + wave(p.x, fi, t) * (1.0 + fi * 0.5);
        vec3 layer = mix(vec3(0.20, 0.52, 0.56), vec3(0.03, 0.14, 0.22), fi / 5.0);
        col = mix(col, layer, smoothstep(px, -px, uv.y - edge));

        if (i == 0) {
            // Reflexo do sol: traços que afinam ao chegar perto.
            float rows = fract(uv.y * 34.0 - t * 0.6);
            float width = 0.012 + (0.44 - uv.y) * 0.30;
            float dash = step(0.45, rows) * step(abs(p.x - sun.x + sin(uv.y * 40.0 + t) * 0.01), width)
                       * step(uv.y, 0.43) * step(0.10, uv.y);
            col = mix(col, vec3(1.00, 0.88, 0.62), dash * 0.55);
        }
        if (i == 1) {
            float bx = aspect * 0.33 + sin(t * 0.3) * 0.04;
            float by = 0.44 - 0.075 + wave(bx, 1.0, t) * 1.5 + 0.004;
            float tilt = cos(bx * 2.4 + t * 1.2 + 1.9) * 0.05;
            vec2 q = p - vec2(bx, by);
            q = vec2(q.x * cos(tilt) - q.y * sin(tilt), q.x * sin(tilt) + q.y * cos(tilt));
            // Casco: trapézio com a proa e a popa erguidas.
            float hull = max(abs(q.y - 0.012) - 0.016,
                             abs(q.x) - 0.075 - (q.y - 0.012) * 1.3);
            float mast = box(q - vec2(-0.004, 0.090), vec2(0.0028, 0.066));
            float yard = box(q - vec2(-0.004, 0.128), vec2(0.040, 0.0024));
            // Vela: triângulo preso ao mastro.
            vec2 s = q - vec2(0.004, 0.040);
            float sail = max(max(-s.x, -s.y), s.x * 1.55 + s.y - 0.082);
            col = mix(col, vec3(0.97, 0.90, 0.74), smoothstep(px, -px, sail));
            col = mix(col, vec3(0.08, 0.13, 0.17),
                      smoothstep(px, -px, min(hull, min(mast, yard))));
        }
    }

    fragColor = vec4(col, 1.0);
}
