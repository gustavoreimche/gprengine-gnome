// Um cardume nadando em círculo, e alguns peixes indo contra a corrente.

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(41.3, 289.1))) * 45758.5453);
}

// Peixe de comprimento ~1, com a cabeça para +x. Negativo dentro.
float fishShape(vec2 q) {
    float body = length(vec2(q.x - 0.08, q.y * 2.3)) - 0.42;
    float back = -q.x - 0.28;
    float tail = max(abs(q.y) - back * 0.75, max(-back, back - 0.34));
    return min(body, tail);
}

// Peixes em anéis ao redor do centro. dir = +1 gira num sentido, -1 no outro.
// Devolve (distância, sorteio do peixe).
vec2 ring(vec2 p, float dir, float offset) {
    const float spacing = 0.105;
    const float size = 0.078;
    float r = length(p);
    float k = floor((r - offset) / spacing + 0.5);
    if (k < 1.0)
        return vec2(1.0, 0.0);
    float radius = offset + k * spacing;
    float count = floor(6.2831853 * radius / 0.20);
    float angle = atan(p.y, p.x) - dir * 0.05 / radius * iTime
                + hash(vec2(k, 3.0)) * 6.2831853;
    float cell = angle / 6.2831853 * count;
    float index = mod(floor(cell), count);
    float h = hash(vec2(index, k + dir * 50.0));
    vec2 q = vec2((fract(cell) - 0.5) * 6.2831853 * radius / count * dir,
                  r - radius) / size;
    // A cauda balança; a cabeça quase não.
    q.y += sin(q.x * 5.0 - iTime * 5.0 + h * 20.0) * 0.07 * clamp(0.3 - q.x, 0.0, 1.0);
    return vec2(fishShape(q) * size, h);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float px = 1.5 / iResolution.y;
    float r = length(p);

    // Água em faixas chapadas, mais clara no centro.
    float band = floor(r * 7.0) / 7.0;
    vec3 col = mix(vec3(0.075, 0.300, 0.320), vec3(0.030, 0.150, 0.175), band);

    vec2 crowd = ring(p, 1.0, 0.0);
    float present = step(crowd.y, 0.86);
    vec3 gray = mix(vec3(0.20, 0.42, 0.44), vec3(0.30, 0.52, 0.53), crowd.y);
    col = mix(col, gray, smoothstep(px, -px, crowd.x) * present);

    // Os que vão contra a corrente nadam entre os anéis dos outros.
    vec2 against = ring(p, -1.0, 0.0525);
    float few = step(0.80, against.y);
    col = mix(col, vec3(0.45, 0.95, 0.85), smoothstep(px, -px, against.x) * few);

    fragColor = vec4(col, 1.0);
}
