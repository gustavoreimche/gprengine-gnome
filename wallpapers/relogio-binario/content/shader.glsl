// Relógio binário: cada coluna é um dígito de HH MM SS, lido de baixo para
// cima em 1, 2, 4 e 8. Os dígitos embaixo ajudam a conferir.

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


void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float px = 1.2 / iResolution.y;
    int secs = int(iDate.w);
    int hh = secs / 3600, mm = (secs / 60) % 60, ss = secs % 60;
    int year = int(iDate.x), month = int(iDate.y) + 1, day = int(iDate.z);

    vec3 col = vec3(0.035, 0.050, 0.055);
    // Grade de fundo bem discreta.
    vec2 g = abs(fract(p / 0.05) - 0.5);
    col += vec3(0.010, 0.022, 0.020) * step(0.47, max(g.x, g.y));

    vec3 on = vec3(0.35, 0.95, 0.62);
    vec3 off = vec3(0.09, 0.16, 0.15);
    int digits[6] = int[6](hh / 10, hh % 10, mm / 10, mm % 10, ss / 10, ss % 10);
    int rows[6] = int[6](2, 4, 3, 4, 3, 4);
    for (int i = 0; i < 6; i++) {
        float x = (float(i) - 2.5) * 0.085 + (float(i / 2) - 1.0) * 0.045;
        for (int r = 0; r < 4; r++) {
            if (r >= rows[i]) continue;
            vec2 q = p - vec2(x, -0.075 + float(r) * 0.085);
            bool lit = ((digits[i] >> r) & 1) != 0;
            float dd = length(q) - 0.026;
            if (lit) col += on * exp(-max(dd, 0.0) * 55.0) * 0.22;
            col = mix(col, lit ? on : off, smoothstep(px, -px, dd));
        }
        const float S = 0.030;
        float d = digit((p - vec2(x, -0.165)) / S, digits[i]) * S;
        col = mix(col, vec3(0.36, 0.50, 0.48), smoothstep(px, -px, d - 0.0013));
    }

    fragColor = vec4(col, 1.0);
}
