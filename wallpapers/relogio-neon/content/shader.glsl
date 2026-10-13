// Relógio neon sobre uma grade synthwave que corre para o horizonte.

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

    const float HZ = -0.08;
    vec3 col = mix(vec3(0.30, 0.06, 0.34), vec3(0.03, 0.02, 0.10), smoothstep(HZ, 0.50, p.y));

    if (p.y < HZ) {
        float z = 1.0 / (HZ - p.y);
        float gx = abs(fract(p.x * z * 0.55) - 0.5);
        float gz = abs(fract(z * 0.45 + iTime * 0.35) - 0.5);
        float w = 0.012 + z * 0.012;
        float line = max(smoothstep(w, 0.0, 0.5 - gx), smoothstep(w, 0.0, 0.5 - gz));
        col = mix(vec3(0.03, 0.01, 0.08), vec3(0.95, 0.25, 0.80), line * exp(-z * 0.10));
    }
    // Brilho na linha do horizonte.
    col += vec3(1.00, 0.35, 0.75) * exp(-abs(p.y - HZ) * 38.0) * 0.55;

    const float S = 0.135;
    float d = clockFace((p - vec2(0.0, 0.215)) / S, hh, mm, 1.0) * S;
    float flicker = 0.94 + 0.06 * sin(iTime * 7.0) * sin(iTime * 2.3);
    col += vec3(0.10, 0.75, 1.00) * exp(-max(d, 0.0) * 34.0) * 0.50 * flicker;
    col += vec3(0.20, 0.85, 1.00) * exp(-max(d, 0.0) * 140.0) * 0.60 * flicker;
    col = mix(col, vec3(0.90, 0.99, 1.00), smoothstep(px, -px, d - 0.0030));

    const float S2 = 0.0135;
    d = dateLine((p - vec2(0.0, 0.070)) / S2, day, month, year) * S2;
    col += vec3(1.00, 0.30, 0.75) * exp(-max(d, 0.0) * 160.0) * 0.45;
    col = mix(col, vec3(1.00, 0.80, 0.95), smoothstep(px, -px, d - 0.0011));

    fragColor = vec4(col, 1.0);
}
