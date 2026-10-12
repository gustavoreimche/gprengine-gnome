// Histórico de um repositório: branches que nascem, recebem commits e voltam
// para a principal.

const float LANES = 5.0;
const float GAP = 1.15;        // distância entre as raias, em alturas de linha

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 laneColor(float i) {
    if (i < 0.5) return vec3(0.35, 0.65, 1.00);
    if (i < 1.5) return vec3(0.48, 0.85, 0.50);
    if (i < 2.5) return vec3(1.00, 0.62, 0.32);
    if (i < 3.5) return vec3(0.82, 0.55, 1.00);
    return vec3(1.00, 0.45, 0.55);
}

// A raia i existe na linha r? A principal sempre; as outras, em trechos.
bool alive(float i, float r) {
    if (i < 0.5)
        return true;
    float period = 7.0 + i * 3.0;
    float shifted = r + i * 5.0;
    float stretch = floor(shifted / period);
    float pos = mod(shifted, period);
    float len = 3.0 + floor(hash(vec2(i, stretch)) * (period - 4.0));
    return hash(vec2(stretch, i + 20.0)) > 0.12 && pos >= 1.0 && pos <= len;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    float rows = 22.0;
    float unit = iResolution.y / rows;
    vec2 g = fragCoord / unit;
    float px = 1.5 / unit;
    float y = g.y + iTime * 0.45;
    float row = floor(y);
    float fy = fract(y);
    float x = g.x - 5.0;                 // 0 é a raia principal

    vec3 bg = vec3(0.051, 0.066, 0.090);
    vec3 col = bg + vec3(0.012) * step(0.5, mod(row, 2.0));

    // Em qual raia cai o commit desta linha.
    // Tenta algumas raias sorteadas; vale a primeira que esteja de pé e reta
    // nesta linha. Se nenhuma servir, o commit vai para a principal.
    float commitLane = 0.0;
    for (int k = 0; k < 4; k++) {
        float pick = floor(hash(vec2(row, 7.0 + float(k))) * LANES);
        if (pick > 0.5 && alive(pick, row) && alive(pick, row - 1.0) && alive(pick, row + 1.0)) {
            commitLane = pick;
            break;
        }
    }

    for (int k = 0; k < 5; k++) {
        float i = float(k);
        if (!alive(i, row))
            continue;
        float lx = i * GAP;
        float d;
        if (!alive(i, row - 1.0) && alive(i, row + 1.0))
            // Nasce: sai da principal e chega à sua raia.
            d = abs(x - lx * smoothstep(0.0, 1.0, fy));
        else if (!alive(i, row + 1.0) && alive(i, row - 1.0))
            // Termina: volta para a principal.
            d = abs(x - lx * (1.0 - smoothstep(0.0, 1.0, fy)));
        else if (!alive(i, row + 1.0))
            continue;
        else
            d = abs(x - lx);
        col = mix(col, laneColor(i), smoothstep(0.085 + px, 0.085, d));
    }

    // O commit: disco com miolo escuro.
    vec2 c = vec2(x - commitLane * GAP, fy - 0.5);
    float dot_ = length(c);
    vec3 tint = laneColor(commitLane);
    col = mix(col, tint, smoothstep(0.26 + px, 0.26, dot_));
    col = mix(col, bg, smoothstep(0.13 + px, 0.13, dot_));

    // À direita: etiqueta (às vezes), mensagem, e o hash do commit.
    float tx = x - (LANES * GAP + 0.6);
    float band = smoothstep(0.30, 0.30 + px, fy) * smoothstep(0.70, 0.70 - px, fy);
    float tag = step(0.78, hash(vec2(row, 11.0)));
    float tagWidth = 2.0 + floor(hash(vec2(row, 12.0)) * 3.0);
    if (tx > 0.0 && tag > 0.5 && tx < tagWidth) {
        float inside = smoothstep(0.0, 0.2, min(tx, tagWidth - tx));
        col = mix(col, tint * 0.55, inside * smoothstep(0.20, 0.20 + px, fy)
                  * smoothstep(0.80, 0.80 - px, fy));
    }
    float start = tag > 0.5 ? tagWidth + 0.5 : 0.0;
    float cursor = start;
    for (int k = 0; k < 6; k++) {
        float fk = float(k);
        float width = 1.0 + floor(hash(vec2(row, 30.0 + fk)) * 4.0);
        if (cursor > start + 6.0 + hash(vec2(row, 13.0)) * 12.0)
            break;
        if (tx >= cursor && tx < cursor + width) {
            float edge = min(tx - cursor, cursor + width - tx);
            col += vec3(0.42, 0.46, 0.52) * smoothstep(0.0, 0.15, edge) * band;
        }
        cursor += width + 0.45;
    }
    float hx = tx - 26.0;
    if (hx > 0.0 && hx < 3.2)
        col += vec3(0.20, 0.24, 0.30) * smoothstep(0.0, 0.15, min(hx, 3.2 - hx)) * band;

    float v = fragCoord.y / iResolution.y;
    col = mix(bg, col, smoothstep(0.0, 0.08, v) * smoothstep(1.0, 0.92, v));
    fragColor = vec4(col, 1.0);
}
