// Um editor rolando código sem fim: linhas, indentação e cores de sintaxe.

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 palette(float h) {
    if (h < 0.22) return vec3(1.00, 0.48, 0.45);   // palavra-chave
    if (h < 0.44) return vec3(0.47, 0.75, 1.00);   // função
    if (h < 0.62) return vec3(0.65, 0.84, 0.48);   // texto
    if (h < 0.76) return vec3(0.82, 0.66, 1.00);   // constante
    return vec3(0.79, 0.82, 0.86);                 // identificador
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    float rows = 44.0;
    float rowH = iResolution.y / rows;
    float charW = rowH * 0.52;
    float px = fragCoord.x / charW - 9.0;          // coluna, depois da margem
    float y = (iResolution.y - fragCoord.y) / rowH + iTime * 0.55;
    float row = floor(y);
    float fy = fract(y);

    vec3 bg = vec3(0.051, 0.066, 0.090);
    vec3 col = bg;
    float band = smoothstep(0.30, 0.34, fy) * smoothstep(0.74, 0.70, fy);

    // Calha com o número da linha.
    if (px < -1.5) {
        float digits = 1.0 + floor(log(mod(row, 9999.0) + 1.0) / log(10.0));
        float gx = px + 6.0;
        float inside = step(4.0 - digits, gx) * step(gx, 4.0);
        col += vec3(0.30, 0.34, 0.40) * inside * band * 0.55;
        fragColor = vec4(col, 1.0);
        return;
    }

    // Blocos de linhas separados por linhas em branco; a indentação muda
    // devagar, de linha para linha, como num arquivo de verdade.
    float blank = step(hash(vec2(row, 1.0)), 0.16);
    float indent = floor(3.0 * (0.5 + 0.5 * sin(row * 0.45) * sin(row * 0.13 + 2.0)) + hash(vec2(row, 2.0))) * 4.0;
    float length_ = 12.0 + floor(hash(vec2(row, 3.0)) * 52.0);
    float comment = step(0.90, hash(vec2(row, 4.0)));

    float start = indent;
    float lit = 0.0;
    vec3 tint = vec3(0.0);
    for (int i = 0; i < 9; i++) {
        float fi = float(i);
        float width = 2.0 + floor(hash(vec2(row, 10.0 + fi)) * 9.0);
        if (start + width > indent + length_)
            break;
        if (px >= start && px < start + width) {
            // Pontas arredondadas do bloco.
            float edge = min(px - start, start + width - px);
            lit = smoothstep(0.0, 0.25, edge);
            tint = palette(hash(vec2(row, 30.0 + fi)));
        }
        start += width + 1.0;
    }
    tint = mix(tint, vec3(0.45, 0.50, 0.56), comment);
    col += tint * lit * band * (1.0 - blank) * 0.62;

    // A linha do cursor, parada no meio, com o cursor piscando.
    float screenRow = (iResolution.y - fragCoord.y) / rowH;
    float current = step(abs(screenRow - 21.5), 0.5);
    col += vec3(0.10, 0.13, 0.19) * current;
    float cursor = current * step(abs(px - (indent + length_ * 0.6)), 0.12)
                 * step(0.5, fract(iTime * 1.1));
    col = mix(col, vec3(0.47, 0.75, 1.00), cursor);

    // Some suavemente em cima e embaixo.
    float v = fragCoord.y / iResolution.y;
    col = mix(bg, col, smoothstep(0.0, 0.10, v) * smoothstep(1.0, 0.90, v));
    fragColor = vec4(col, 1.0);
}
