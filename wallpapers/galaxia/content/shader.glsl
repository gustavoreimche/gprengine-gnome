// Galáxia espiral girando devagar.

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    // Disco visto inclinado.
    vec2 q = vec2(p.x, p.y * 1.9);
    float r = length(q);
    float a = atan(q.y, q.x) + iTime * 0.03;

    // Dois braços: a fase cresce com o logaritmo do raio.
    float arms = 0.5 + 0.5 * cos(2.0 * a - 7.0 * log(r + 0.06));
    float dust = noise(vec2(a * 3.0, r * 9.0) + 3.0) * 0.6
               + noise(q * 14.0 + iTime * 0.02) * 0.4;
    float disk = exp(-r * 3.4);
    float density = disk * (0.25 + pow(arms, 2.5) * (0.55 + dust * 0.6));

    vec3 col = vec3(0.012, 0.012, 0.03);
    col += mix(vec3(0.30, 0.42, 1.00), vec3(1.00, 0.55, 0.75), dust) * density * 1.5;
    col += vec3(1.00, 0.88, 0.65) * exp(-r * 11.0) * 1.3;

    vec2 sp = p * 110.0;
    vec2 cell = floor(sp);
    float seed = hash(cell);
    vec2 center = cell + 0.5 + (vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5) * 0.7;
    float star = step(0.94, seed) * smoothstep(0.17, 0.0, length(sp - center));
    col += vec3(star * (0.55 + 0.45 * sin(iTime * (0.7 + seed) + seed * 50.0)));

    fragColor = vec4(col, 1.0);
}
