// Curvas de nível de um relevo que muda devagar.

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float height(vec2 p) {
    float t = iTime * 0.03;
    return noise(p * 1.3 + t) * 0.6 + noise(p * 2.9 - t * 1.3 + 4.0) * 0.3
         + noise(p * 6.1 + 9.0) * 0.1;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float h = height(p * 1.6);

    // Largura da linha medida em pixels, pela inclinação do relevo ali.
    float e = 1.5 / iResolution.y;
    vec2 grad = vec2(height((p + vec2(e, 0.0)) * 1.6) - h,
                     height((p + vec2(0.0, e)) * 1.6) - h) / e;
    float levels = 14.0;
    float v = h * levels;
    float dist = abs(fract(v) - 0.5) / (length(grad) * levels + 1e-4);
    float line = 1.0 - smoothstep(0.0, 1.6 / iResolution.y, 0.5 / (length(grad) * levels + 1e-4) - dist);

    vec3 low = vec3(0.04, 0.09, 0.13), high = vec3(0.07, 0.20, 0.22);
    vec3 col = mix(low, high, h);
    // Uma curva em cada cinco é mais forte, como nas cartas.
    float major = step(0.5, 1.0 - abs(mod(floor(v + 0.5), 5.0)));
    col += vec3(0.30, 0.85, 0.70) * line * mix(0.22, 0.60, major);
    fragColor = vec4(col, 1.0);
}
