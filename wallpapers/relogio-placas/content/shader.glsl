// Relógio de placas, como os de aeroporto: quatro cartões com a dobra no meio.

// Dígitos de sete traços finos com pontas redondas.
const int MASKS[10] = int[10](63, 6, 91, 79, 102, 109, 125, 7, 127, 111);

float stroke(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// Distância ao dígito n, numa caixa de 0,56 x 1,0 centrada na origem.
float digit(vec2 p, int n) {
    int m = MASKS[clamp(n, 0, 9)];
    const float a = 0.28, b = 0.50;
    float d = 1e3;
    if ((m & 1) != 0)  d = min(d, stroke(p, vec2(-a,  b), vec2( a,  b)));
    if ((m & 2) != 0)  d = min(d, stroke(p, vec2( a,  b), vec2( a, 0.0)));
    if ((m & 4) != 0)  d = min(d, stroke(p, vec2( a, 0.0), vec2( a, -b)));
    if ((m & 8) != 0)  d = min(d, stroke(p, vec2(-a, -b), vec2( a, -b)));
    if ((m & 16) != 0) d = min(d, stroke(p, vec2(-a, 0.0), vec2(-a, -b)));
    if ((m & 32) != 0) d = min(d, stroke(p, vec2(-a,  b), vec2(-a, 0.0)));
    if ((m & 64) != 0) d = min(d, stroke(p, vec2(-a, 0.0), vec2( a, 0.0)));
    return d;
}

float pair(vec2 p, int v, float gap) {
    return min(digit(p + vec2(gap, 0.0), v / 10), digit(p - vec2(gap, 0.0), v - (v / 10) * 10));
}

// HH:MM centrado na origem; a altura dos dígitos é 1.
float clockFace(vec2 p, int hh, int mm, float blink) {
    float d = min(pair(p + vec2(1.05, 0.0), hh, 0.45), pair(p - vec2(1.05, 0.0), mm, 0.45));
    float dots = min(length(p - vec2(0.0, 0.22)), length(p + vec2(0.0, 0.22))) + (1.0 - blink) * 1e3;
    return min(d, dots);
}

// DD · MM · AAAA centrado na origem.
float dateLine(vec2 p, int day, int month, int year) {
    const float s = 1.05;
    float d = pair(p + vec2(4.0 * s, 0.0), day, s * 0.5);
    d = min(d, pair(p + vec2(1.0 * s, 0.0), month, s * 0.5));
    d = min(d, pair(p - vec2(2.0 * s, 0.0), year / 100, s * 0.5));
    d = min(d, pair(p - vec2(4.0 * s, 0.0), year - (year / 100) * 100, s * 0.5));
    d = min(d, length(p + vec2(2.5 * s, 0.0)) - 0.03);
    d = min(d, length(p - vec2(0.5 * s, 0.0)) - 0.03);
    return d;
}

// 0 = domingo.
int weekday(int y, int m, int d) {
    const int T[12] = int[12](0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4);
    if (m < 3) y -= 1;
    return (y + y / 4 - y / 100 + y / 400 + T[m - 1] + d) % 7;
}


float roundBox(vec2 q, vec2 b, float r) {
    vec2 d = abs(q) - b + r;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float px = 1.2 / iResolution.y;
    int secs = int(iDate.w);
    int hh = secs / 3600, mm = (secs / 60) % 60, ss = secs % 60;
    int year = int(iDate.x), month = int(iDate.y) + 1, day = int(iDate.z);

    vec3 col = mix(vec3(0.075, 0.075, 0.085), vec3(0.120, 0.118, 0.130), exp(-dot(p, p) * 2.5));
    vec3 ink = vec3(0.95, 0.93, 0.88);

    int digits[4] = int[4](hh / 10, hh % 10, mm / 10, mm % 10);
    for (int i = 0; i < 4; i++) {
        float x = (float(i) - 1.5) * 0.205 + (i < 2 ? -0.030 : 0.030);
        vec2 q = p - vec2(x, 0.025);
        float card = roundBox(q, vec2(0.092, 0.135), 0.018);
        // Sombra chapada, deslocada para baixo.
        col = mix(col, vec3(0.030, 0.030, 0.036),
                  smoothstep(px, -px, roundBox(q + vec2(0.0, 0.010), vec2(0.092, 0.135), 0.018)));
        vec3 face = q.y > 0.0 ? vec3(0.185, 0.185, 0.205) : vec3(0.150, 0.150, 0.168);
        const float S = 0.170;
        float d = digit(q / S, digits[i]) * S;
        face = mix(face, q.y > 0.0 ? ink : ink * 0.86, smoothstep(px, -px, d - 0.0075));
        // Dobra e os dois pinos do eixo.
        face = mix(face, vec3(0.045, 0.045, 0.052), smoothstep(px, -px, abs(q.y) - 0.0016));
        float pins = roundBox(vec2(abs(q.x) - 0.092, q.y), vec2(0.006, 0.014), 0.003);
        face = mix(face, vec3(0.045, 0.045, 0.052), smoothstep(px, -px, pins));
        col = mix(col, face, smoothstep(px, -px, card));
    }
    float dots = min(length(p - vec2(0.0, 0.070)), length(p - vec2(0.0, -0.020))) - 0.0095;
    col = mix(col, ink * (ss % 2 == 0 ? 0.80 : 0.35), smoothstep(px, -px, dots));

    const float S2 = 0.0125;
    float d2 = dateLine((p + vec2(0.0, 0.165)) / S2, day, month, year) * S2;
    col = mix(col, vec3(0.50, 0.49, 0.50), smoothstep(px, -px, d2 - 0.0011));

    fragColor = vec4(col, 1.0);
}
