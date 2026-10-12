// Chuva de símbolos verdes.

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    float cell = iResolution.y / 46.0;
    vec2 g = fragCoord / vec2(cell * 0.62, cell);
    vec2 id = floor(g);
    vec2 f = fract(g);

    // Cada coluna tem a sua gota: velocidade, fase e comprimento próprios.
    float speed = 3.0 + hash(vec2(id.x, 1.0)) * 7.0;
    float span = 46.0 + hash(vec2(id.x, 2.0)) * 40.0;
    float head = mod(iTime * speed + hash(vec2(id.x, 3.0)) * span, span);
    float row = 46.0 - id.y;
    float behind = head - row;
    float tail = 10.0 + hash(vec2(id.x, 4.0)) * 20.0;
    float glow = behind < 0.0 ? 0.0 : exp(-behind / tail * 3.0);
    float lead = smoothstep(1.2, 0.0, abs(behind - 0.5));

    // Símbolo: uma grade 4x6 de pontos sorteados, que troca de vez em quando.
    float change = floor(iTime * (0.6 + hash(id) * 3.0) + hash(id + 9.0) * 10.0);
    vec2 sub = floor(f * vec2(4.0, 6.0));
    vec2 sf = fract(f * vec2(4.0, 6.0));
    float bit = step(0.52, hash(id * 1.37 + sub * 7.31 + change));
    float dot_ = smoothstep(0.50, 0.30, max(abs(sf.x - 0.5), abs(sf.y - 0.5)));
    float margin = step(0.5, sub.x) * step(sub.x, 3.5) * step(0.5, sub.y);
    float glyph = bit * dot_ * margin;

    vec3 col = vec3(0.0, 0.02, 0.01);
    col += vec3(0.05, 0.85, 0.35) * glyph * glow;
    col += vec3(0.75, 1.00, 0.85) * glyph * lead;
    col += vec3(0.0, 0.10, 0.04) * glow * 0.5;
    fragColor = vec4(col, 1.0);
}
