// Três cruzes no alto do monte, com o sol nascendo atrás.

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * noise(p);
        p = p * 2.03 + 5.3;
        a *= 0.5;
    }
    return v;
}

float box(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Cruz de altura s, com a base em p = 0.
float crossShape(vec2 p, float s) {
    return min(box(p - vec2(0.0, s * 0.5), vec2(s * 0.035, s * 0.5)),
               box(p - vec2(0.0, s * 0.70), vec2(s * 0.20, s * 0.035)));
}

float hill(float x) {
    return -0.20 - x * x * 0.30;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float px = 1.5 / iResolution.y;
    vec2 sun = vec2(0.0, -0.10);
    vec2 d = p - sun;
    float r = length(d);

    // Céu: dourado no horizonte, azul profundo no alto.
    float up = smoothstep(-0.25, 0.55, p.y);
    vec3 col = mix(vec3(1.00, 0.62, 0.28), vec3(0.42, 0.24, 0.42), smoothstep(0.0, 0.5, up));
    col = mix(col, vec3(0.05, 0.07, 0.20), smoothstep(0.45, 1.0, up));

    // Raios saindo de trás da cruz, girando muito devagar.
    float a = atan(d.y, d.x);
    float rays = 0.5 + 0.5 * sin(a * 9.0 + iTime * 0.05)
               * sin(a * 23.0 - iTime * 0.08);
    rays *= smoothstep(-0.2, 0.9, sin(a)) * exp(-r * 1.1);
    col += vec3(1.00, 0.80, 0.50) * rays * 0.35;
    col += vec3(1.00, 0.85, 0.60) * exp(-r * 3.2) * 0.75;
    col += vec3(1.00, 0.97, 0.85) * exp(-r * 13.0);

    // Nuvens altas, iluminadas por baixo.
    float clouds = fbm(vec2(p.x * 1.6 + iTime * 0.012, p.y * 4.5));
    float band = smoothstep(0.50, 0.80, clouds) * smoothstep(0.02, 0.30, p.y);
    col = mix(col, mix(vec3(1.00, 0.66, 0.42), vec3(0.20, 0.16, 0.32), up), band * 0.55);

    // Silhueta: o monte e as três cruzes.
    float ground = p.y - hill(p.x);
    float shape = ground;
    shape = min(shape, crossShape(p - vec2(0.0, hill(0.0) - 0.01), 0.40));
    shape = min(shape, crossShape(p - vec2(-0.40, hill(-0.40) - 0.01), 0.27));
    shape = min(shape, crossShape(p - vec2(0.40, hill(0.40) - 0.01), 0.27));
    vec3 dark = vec3(0.03, 0.02, 0.04);
    col = mix(col, dark, smoothstep(px, -px, shape));
    // Fio de luz contornando a silhueta, do lado do sol.
    col += vec3(1.00, 0.75, 0.45) * smoothstep(0.012, 0.0, abs(shape)) * exp(-r * 2.5) * 0.5;

    fragColor = vec4(col, 1.0);
}
