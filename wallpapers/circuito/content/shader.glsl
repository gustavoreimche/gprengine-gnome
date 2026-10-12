// Placa de circuito: trilhas, ilhas e pulsos saindo do chip no centro.

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(41.3, 289.1))) * 45758.5453);
}

float segment(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

float box(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float scale = 13.0;
    vec2 g = p * scale;
    vec2 id = floor(g);
    vec2 f = fract(g) - 0.5;
    float px = scale * 1.5 / iResolution.y;

    // Cada célula liga os meios dos seus lados: em diagonal para um lado,
    // para o outro, ou reto. As trilhas se emendam de célula em célula.
    float kind = hash(id);
    float d;
    if (kind < 0.40)
        d = min(segment(f, vec2(-0.5, 0.0), vec2(0.0, 0.5)),
                segment(f, vec2(0.0, -0.5), vec2(0.5, 0.0)));
    else if (kind < 0.80)
        d = min(segment(f, vec2(-0.5, 0.0), vec2(0.0, -0.5)),
                segment(f, vec2(0.0, 0.5), vec2(0.5, 0.0)));
    else
        d = min(segment(f, vec2(-0.5, 0.0), vec2(0.5, 0.0)),
                segment(f, vec2(0.0, -0.5), vec2(0.0, 0.5)));
    float trace = 1.0 - smoothstep(0.045, 0.045 + px, d);

    // Ilhas de solda nos cantos de algumas células.
    vec2 corner = floor(g + 0.5);
    float pad = length(g - corner);
    float hasPad = step(0.72, hash(corner + 17.0));
    float ring = hasPad * (1.0 - smoothstep(0.15, 0.15 + px, pad))
               * smoothstep(0.06, 0.06 + px, pad);

    // Pulsos em anéis quadrados, afastando-se do chip.
    float away = max(abs(p.x), abs(p.y));
    float pulse = pow(0.5 + 0.5 * sin(away * 16.0 - iTime * 1.6), 10.0);
    float spark = pow(0.5 + 0.5 * sin(dot(g, vec2(0.7, 1.1)) - iTime * 2.3 + kind * 6.0), 14.0);

    vec3 board = mix(vec3(0.015, 0.075, 0.060), vec3(0.008, 0.040, 0.036),
                     smoothstep(0.0, 0.9, length(p)));
    vec3 copper = vec3(0.10, 0.42, 0.34);
    vec3 col = board + copper * trace * 0.75;
    col += vec3(0.85, 0.70, 0.35) * ring * 0.85;
    col += vec3(0.35, 1.00, 0.85) * trace * (pulse * 0.9 + spark * 0.5);

    // O chip: corpo escuro, pinos nos quatro lados e um núcleo pulsando.
    float body = box(p, vec2(0.145)) - 0.012;
    float pins = box(p, vec2(0.185));
    float stripes = step(0.5, fract(max(abs(p.x), abs(p.y)) < abs(p.x) + 1e-5
                                    ? p.y * 26.0 : p.x * 26.0));
    float pinMask = smoothstep(px / scale, -px / scale, pins) * stripes
                  * step(max(abs(p.x), abs(p.y)), 0.185)
                  * step(min(abs(p.x), abs(p.y)), 0.125);
    col = mix(col, vec3(0.78, 0.66, 0.36), pinMask * smoothstep(-0.002, 0.002, body));
    float inside = smoothstep(px / scale, -px / scale, body);
    vec3 chip = vec3(0.035, 0.040, 0.050) + vec3(0.03) * smoothstep(0.004, 0.0, abs(body + 0.012));
    float core = box(p, vec2(0.055)) - 0.008;
    float beat = 0.6 + 0.4 * sin(iTime * 1.6);
    chip += vec3(0.35, 1.00, 0.85) * smoothstep(0.004, -0.004, core) * 0.22 * beat;
    chip += vec3(0.35, 1.00, 0.85) * smoothstep(0.006, 0.0, abs(core)) * 0.7 * beat;
    col = mix(col, chip, inside);

    fragColor = vec4(col, 1.0);
}
