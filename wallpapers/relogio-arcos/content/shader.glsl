// Relógio em arcos: três anéis que se fecham com as horas, os minutos e os
// segundos, e a hora no centro.

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


const float TAU = 6.2831853;

// Arco de espessura w no raio R, do topo até a fração f, com pontas redondas.
float arc(vec2 c, float R, float f, float w) {
    float a = mod(atan(c.x, c.y) + TAU, TAU) / TAU;
    float ring = abs(length(c) - R) - w;
    float body = a <= f ? ring : 1e3;
    float e = f * TAU;
    float caps = min(length(c - vec2(0.0, R)), length(c - vec2(sin(e), cos(e)) * R)) - w;
    return min(body, caps);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float px = 1.2 / iResolution.y;
    int secs = int(iDate.w);
    int hh = secs / 3600, mm = (secs / 60) % 60, ss = secs % 60;
    int year = int(iDate.x), month = int(iDate.y) + 1, day = int(iDate.z);

    vec3 col = mix(vec3(0.040, 0.045, 0.070), vec3(0.075, 0.085, 0.125), exp(-dot(p, p) * 3.0));
    vec3 ink = vec3(0.93, 0.95, 0.99);

    float fh = (float(hh % 12) + float(mm) / 60.0) / 12.0;
    float fm = (float(mm) + float(ss) / 60.0) / 60.0;
    float fs = float(ss) / 60.0;
    float radius[3] = float[3](0.300, 0.252, 0.204);
    float frac[3] = float[3](fh, fm, fs);
    vec3 tint[3] = vec3[3](vec3(0.98, 0.45, 0.42), vec3(0.98, 0.76, 0.36), vec3(0.36, 0.80, 0.86));
    for (int i = 0; i < 3; i++) {
        float track = abs(length(p) - radius[i]) - 0.0135;
        col = mix(col, tint[i] * 0.16, smoothstep(px, -px, track));
        col = mix(col, tint[i], smoothstep(px, -px, arc(p, radius[i], frac[i], 0.0135)));
    }

    const float S = 0.058;
    float d = clockFace((p - vec2(0.0, 0.012)) / S, hh, mm, 1.0) * S;
    col = mix(col, ink, smoothstep(px, -px, d - 0.0022));
    const float S2 = 0.0095;
    d = dateLine((p + vec2(0.0, 0.052)) / S2, day, month, year) * S2;
    col = mix(col, ink * 0.55, smoothstep(px, -px, d - 0.0009));

    fragColor = vec4(col, 1.0);
}
