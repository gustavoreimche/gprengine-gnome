// Relógio com o céu da hora: o sol nasce às 6, cruza o céu e se põe às 18;
// à noite sobem a lua e as estrelas. As cores acompanham.

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


float hash(vec2 v) { return fract(sin(dot(v, vec2(127.1, 311.7))) * 43758.5453); }

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float px = 1.2 / iResolution.y;
    int secs = int(iDate.w);
    int hh = secs / 3600, mm = (secs / 60) % 60, ss = secs % 60;
    int year = int(iDate.x), month = int(iDate.y) + 1, day = int(iDate.z);

    const float TAU = 6.2831853;
    vec2 w = vec2(uv.x * aspect, uv.y);
    float dayFrac = float(secs) / 86400.0;
    float h = sin((dayFrac - 0.25) * TAU);            // altura do sol, de -1 a 1
    float dayK = smoothstep(-0.05, 0.35, h);
    float duskK = 1.0 - smoothstep(0.0, 0.45, abs(h));

    vec3 dayC[4] = vec3[4](vec3(0.80, 0.92, 0.98), vec3(0.62, 0.84, 0.97),
                           vec3(0.45, 0.74, 0.95), vec3(0.32, 0.62, 0.90));
    vec3 duskC[4] = vec3[4](vec3(0.99, 0.80, 0.52), vec3(0.96, 0.62, 0.44),
                            vec3(0.70, 0.45, 0.52), vec3(0.34, 0.34, 0.52));
    vec3 nightC[4] = vec3[4](vec3(0.16, 0.18, 0.34), vec3(0.11, 0.13, 0.27),
                             vec3(0.07, 0.09, 0.20), vec3(0.04, 0.05, 0.13));
    vec3 col = vec3(0.0);
    for (int i = 0; i < 4; i++) {
        vec3 band = mix(mix(nightC[i], dayC[i], dayK), duskC[i], duskK);
        float edge = 0.40 + float(i) * 0.15 + sin(w.x * 1.3 + float(i) * 2.0) * 0.010;
        col = i == 0 ? band : mix(col, band, smoothstep(-px, px, uv.y - edge));
    }

    // Estrelas, só com o céu escuro.
    vec2 sg = w * 46.0;
    vec2 sc = floor(sg);
    float sr = hash(sc);
    float star = smoothstep(0.10, 0.04, length(fract(sg) - 0.5 - (vec2(hash(sc + 3.1), hash(sc + 7.7)) - 0.5) * 0.6))
               * step(0.84, sr) * smoothstep(0.50, 0.62, uv.y)
               * (0.55 + 0.45 * sin(iTime * (0.6 + sr * 1.5) + sr * 40.0));
    col = mix(col, vec3(0.95, 0.92, 0.84), star * (1.0 - dayK) * (1.0 - duskK * 0.7));

    // Sol e lua em lados opostos do mesmo arco.
    const float HORIZON = 0.36;
    vec2 sun = vec2(aspect * (0.5 - 0.42 * cos((dayFrac - 0.25) * TAU)), HORIZON + h * 0.27);
    float ds = length(w - sun);
    vec3 sunC = mix(vec3(1.00, 0.70, 0.38), vec3(1.00, 0.97, 0.86), dayK);
    col = mix(col, sunC, smoothstep(px, -px, ds - 0.20) * 0.22);
    col = mix(col, sunC, smoothstep(px, -px, ds - 0.14) * 0.38);
    col = mix(col, sunC, smoothstep(px, -px, ds - 0.085));
    vec2 moon = vec2(aspect * (0.5 + 0.42 * cos((dayFrac - 0.25) * TAU)), HORIZON - h * 0.27);
    float dm = max(length(w - moon) - 0.060, 0.052 - length(w - moon - vec2(0.030, 0.018)));
    col = mix(col, vec3(0.93, 0.93, 0.86), smoothstep(px, -px, dm));

    // Colinas em camadas; escurecem à noite e esquentam no crepúsculo.
    float t = iTime * 0.05;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float edge = HORIZON + 0.03 - fi * 0.075
                   + sin(w.x * (1.5 + fi * 0.5) + fi * 1.9 + t * (0.4 + fi * 0.2)) * 0.035
                   + sin(w.x * (3.9 + fi) + fi * 4.1) * 0.012;
        vec3 layer = mix(vec3(0.36, 0.62, 0.56), vec3(0.06, 0.20, 0.24), fi / 4.0);
        layer = mix(layer, layer * vec3(1.25, 0.80, 0.75), duskK * (1.0 - fi / 4.0) * 0.8);
        layer *= mix(0.30, 1.0, max(dayK, duskK * 0.75));
        col = mix(col, layer, smoothstep(px, -px, uv.y - edge));
    }

    vec3 ink = mix(vec3(0.95, 0.96, 1.00), vec3(0.10, 0.20, 0.34), dayK * (1.0 - duskK));
    const float S = 0.110;
    float d = clockFace((p - vec2(0.0, 0.285)) / S, hh, mm, 1.0) * S;
    col = mix(col, ink, smoothstep(px, -px, d - 0.0032));
    const float S2 = 0.0125;
    d = dateLine((p - vec2(0.0, 0.180)) / S2, day, month, year) * S2;
    col = mix(col, ink, smoothstep(px, -px, d - 0.0011) * 0.75);

    fragColor = vec4(col, 1.0);
}
