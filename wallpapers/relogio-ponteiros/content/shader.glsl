// Relógio de ponteiros minimalista: aro fino, doze marcas e a data embaixo.

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
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float px = 1.2 / iResolution.y;
    int secs = int(iDate.w);
    int hh = secs / 3600, mm = (secs / 60) % 60, ss = secs % 60;
    int year = int(iDate.x), month = int(iDate.y) + 1, day = int(iDate.z);

    float glow = exp(-dot(p, p) * 4.0);
    vec3 col = mix(vec3(0.045, 0.040, 0.050), vec3(0.110, 0.090, 0.095), glow);

    vec3 ink = vec3(0.95, 0.92, 0.88);
    vec3 dim = vec3(0.55, 0.48, 0.46);
    vec3 accent = vec3(0.98, 0.62, 0.28);

    vec2 c = p - vec2(0.0, 0.045);
    const float R = 0.23;
    const float TAU = 6.2831853;
    float r = length(c);
    col = mix(col, dim * 0.6, smoothstep(px, -px, abs(r - R) - 0.0010));

    // Marcas das horas; as de 12, 3, 6 e 9 são mais longas.
    float ang = atan(c.x, c.y);
    float slot = floor(ang / TAU * 12.0 + 0.5);
    float da = ang - slot * TAU / 12.0;
    bool major = int(mod(slot + 12.0, 3.0)) == 0;
    float len = major ? 0.022 : 0.010;
    float tick = max(abs(sin(da) * r) - (major ? 0.0016 : 0.0010),
                     abs(cos(da) * r - (R - 0.016 - len * 0.5)) - len * 0.5);
    col = mix(col, major ? ink : dim, smoothstep(px, -px, tick));

    float am = (float(mm) + float(ss) / 60.0) / 60.0 * TAU;
    float ah = (float(hh % 12) + float(mm) / 60.0) / 12.0 * TAU;
    float as = float(ss) / 60.0 * TAU;
    float hand = stroke(c, vec2(0.0), vec2(sin(ah), cos(ah)) * R * 0.52) - 0.0042;
    col = mix(col, ink, smoothstep(px, -px, hand));
    hand = stroke(c, vec2(0.0), vec2(sin(am), cos(am)) * R * 0.80) - 0.0026;
    col = mix(col, ink, smoothstep(px, -px, hand));
    hand = stroke(c, -vec2(sin(as), cos(as)) * R * 0.14, vec2(sin(as), cos(as)) * R * 0.88) - 0.0010;
    col = mix(col, accent, smoothstep(px, -px, hand));
    col = mix(col, accent, smoothstep(px, -px, r - 0.0070));
    col = mix(col, vec3(0.045, 0.040, 0.050), smoothstep(px, -px, r - 0.0028));

    const float S2 = 0.0125;
    float d = dateLine((p + vec2(0.0, 0.235)) / S2, day, month, year) * S2;
    col = mix(col, dim, smoothstep(px, -px, d - 0.0011));

    fragColor = vec4(col, 1.0);
}
