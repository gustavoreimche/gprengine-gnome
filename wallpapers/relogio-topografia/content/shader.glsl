// Relógio sobre curvas de nível em tons de grafite.

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


float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float height(vec2 p) {
    float t = iTime * 0.03;
    return noise(p * 1.3 + t) * 0.6 + noise(p * 2.9 - t * 1.3 + 4.0) * 0.3
         + noise(p * 6.1 + 9.0) * 0.1;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float px = 1.2 / iResolution.y;
    int secs = int(iDate.w);
    int hh = secs / 3600, mm = (secs / 60) % 60, ss = secs % 60;
    int year = int(iDate.x), month = int(iDate.y) + 1, day = int(iDate.z);

    float h = height(p * 1.6);
    float e = 1.5 / iResolution.y;
    vec2 grad = vec2(height((p + vec2(e, 0.0)) * 1.6) - h,
                     height((p + vec2(0.0, e)) * 1.6) - h) / e;
    float levels = 14.0;
    float v = h * levels;
    float dist = abs(fract(v) - 0.5) / (length(grad) * levels + 1e-4);
    float line = 1.0 - smoothstep(0.0, 1.6 / iResolution.y, 0.5 / (length(grad) * levels + 1e-4) - dist);

    vec3 col = mix(vec3(0.060, 0.062, 0.068), vec3(0.125, 0.128, 0.138), h);
    float major = step(0.5, 1.0 - abs(mod(floor(v + 0.5), 5.0)));
    // As curvas somem atrás da hora, para os dígitos lerem bem.
    float clear = smoothstep(0.10, 0.34, length((p - vec2(0.0, 0.01)) * vec2(0.62, 1.25)));
    col += vec3(0.60, 0.62, 0.66) * line * mix(0.16, 0.42, major) * mix(0.12, 1.0, clear);

    vec3 ink = vec3(0.92, 0.93, 0.95);
    vec3 dim = vec3(0.56, 0.57, 0.60);
    const float S = 0.115;
    float d = clockFace((p - vec2(0.0, 0.040)) / S, hh, mm, 1.0) * S;
    col = mix(col, ink, smoothstep(px, -px, d - 0.0032));
    const float S2 = 0.0130;
    d = dateLine((p + vec2(0.0, 0.068)) / S2, day, month, year) * S2;
    col = mix(col, dim, smoothstep(px, -px, d - 0.0011));
    // Barra dos segundos.
    vec2 b = p + vec2(0.0, 0.112);
    col = mix(col, dim * 0.40, smoothstep(px, -px, max(abs(b.x) - 0.075, abs(b.y) - 0.0009)));
    float fill = max(max(-0.075 - b.x, b.x - (-0.075 + 0.150 * float(ss) / 59.0)), abs(b.y) - 0.0013);
    col = mix(col, ink, smoothstep(px, -px, fill));

    fragColor = vec4(col, 1.0);
}
