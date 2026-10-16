// Relógio no meio do céu: o sol nasce às 8 e se põe às 17, cruzando o céu da
// esquerda para a direita; das 17 às 8 é a vez da lua e das estrelas.

const float SUNRISE = 8.0;
const float SUNSET = 17.0;

// Dígitos de sete traços grossos com pontas redondas.
const int MASKS[10] = int[10](63, 6, 91, 79, 102, 109, 125, 7, 127, 111);

float stroke(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// Distância ao dígito n, numa caixa de 0,56 x 1,0 centrada na origem.
float digit(vec2 p, int n) {
    int m = MASKS[clamp(n, 0, 9)];
    const float a = 0.28, b = 0.50;
    if (n == 1) p.x += a * 0.5;   // o 1 só tem traços à direita: centraliza
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
float clockFace(vec2 p, int hh, int mm) {
    float d = min(pair(p + vec2(1.05, 0.0), hh, 0.45), pair(p - vec2(1.05, 0.0), mm, 0.45));
    return min(d, min(length(p - vec2(0.0, 0.22)), length(p + vec2(0.0, 0.22))));
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

float hash(vec2 v) { return fract(sin(dot(v, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 v) {
    vec2 i = floor(v), f = fract(v);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    vec2 w = vec2(uv.x * aspect, uv.y);
    float px = 1.2 / iResolution.y;
    int secs = int(iDate.w);
    int hh = secs / 3600, mm = (secs / 60) % 60;
    int year = int(iDate.x), month = int(iDate.y) + 1, day = int(iDate.z);
    const float PI = 3.14159265;

    // Onde estamos no arco: phase vai de 0 (nascer) a 1 (pôr), tanto para o
    // sol de dia quanto para a lua de noite. edge é a distância em horas até
    // o nascer ou o pôr mais próximo: positiva de dia, negativa de noite.
    float hours = iDate.w / 3600.0;
    bool isDay = hours >= SUNRISE && hours < SUNSET;
    float phase, edge, sunX;   // sunX: onde o sol está (ou acabou de sumir)
    if (isDay) {
        phase = (hours - SUNRISE) / (SUNSET - SUNRISE);
        edge = min(hours - SUNRISE, SUNSET - hours);
        sunX = 0.06 + 0.88 * phase;
    } else {
        float nightLen = 24.0 - (SUNSET - SUNRISE);
        float nh = mod(hours - SUNSET, 24.0);
        phase = nh / nightLen;
        edge = -min(nh, nightLen - nh);
        sunX = nh < nightLen * 0.5 ? 0.94 : 0.06;
    }
    // Tudo varia com edge em curvas largas, para a luz mudar devagar: o dia
    // fica pleno 3 h depois do nascer, a noite fecha 3,5 h depois do pôr.
    float dayK = smoothstep(-0.5, 3.0, edge);
    float duskK = exp(-edge * edge / 1.8);
    float nightK = smoothstep(-0.5, -3.0, edge);

    // Céu em quatro faixas, passando por cinco paletas: noite, hora azul,
    // crepúsculo, luz dourada e dia. Cada uma se funde na seguinte.
    vec3 nightC[4] = vec3[4](vec3(0.12, 0.15, 0.30), vec3(0.08, 0.10, 0.23),
                             vec3(0.05, 0.06, 0.16), vec3(0.03, 0.04, 0.10));
    vec3 blueC[4]  = vec3[4](vec3(0.36, 0.34, 0.56), vec3(0.24, 0.26, 0.50),
                             vec3(0.15, 0.18, 0.40), vec3(0.08, 0.11, 0.27));
    vec3 duskC[4]  = vec3[4](vec3(1.00, 0.68, 0.44), vec3(0.92, 0.52, 0.46),
                             vec3(0.60, 0.40, 0.56), vec3(0.26, 0.26, 0.50));
    vec3 goldC[4]  = vec3[4](vec3(1.00, 0.86, 0.64), vec3(0.92, 0.80, 0.72),
                             vec3(0.64, 0.70, 0.84), vec3(0.40, 0.55, 0.82));
    vec3 dayC[4]   = vec3[4](vec3(0.80, 0.92, 0.98), vec3(0.62, 0.84, 0.97),
                             vec3(0.45, 0.74, 0.95), vec3(0.30, 0.60, 0.90));
    float kBlue = smoothstep(-3.5, -1.3, edge);
    float kDusk = smoothstep(-1.3, 0.1, edge);
    float kGold = smoothstep(0.1, 1.3, edge);
    float kDay  = smoothstep(1.3, 3.2, edge);
    vec3 col = vec3(0.0);
    for (int i = 0; i < 4; i++) {
        vec3 band = mix(mix(mix(mix(nightC[i], blueC[i], kBlue), duskC[i], kDusk), goldC[i], kGold), dayC[i], kDay);
        float e = 0.38 + float(i) * 0.16 + sin(w.x * 1.3 + float(i) * 2.0) * 0.010;
        col = i == 0 ? band : mix(col, band, smoothstep(-0.06, 0.06, uv.y - e));
    }
    // Brilho quente no horizonte, do lado em que o sol nasce ou se põe.
    float gx = (w.x - aspect * sunX) / aspect;
    col += vec3(1.00, 0.52, 0.26) * duskK * 0.30 * exp(-gx * gx * 6.0) * smoothstep(0.80, 0.30, uv.y);

    // Estrelas: só de noite, e piscando devagar.
    vec2 sg = w * 46.0;
    vec2 sc = floor(sg);
    float sr = hash(sc);
    float star = smoothstep(0.10, 0.04, length(fract(sg) - 0.5 - (vec2(hash(sc + 3.1), hash(sc + 7.7)) - 0.5) * 0.6))
               * step(0.85, sr) * smoothstep(0.40, 0.65, uv.y)
               * (0.55 + 0.45 * sin(iTime * (0.6 + sr * 1.5) + sr * 40.0));
    col = mix(col, vec3(0.95, 0.92, 0.84), star * nightK);

    // O astro da vez percorre o mesmo arco, da esquerda para a direita.
    const float HORIZON = 0.30;
    vec2 body = vec2(aspect * (0.06 + 0.88 * phase), HORIZON - 0.02 + sin(phase * PI) * 0.56);
    float db = length(w - body);
    if (isDay) {
        vec3 sunC = mix(vec3(1.00, 0.55, 0.28), vec3(1.00, 0.97, 0.86), smoothstep(0.0, 3.0, edge));
        float fade = smoothstep(0.0, 0.4, edge);   // some de leve atrás das colinas
        col += sunC * exp(-db * 9.0) * 0.35 * fade;
        col = mix(col, sunC, smoothstep(px, -px, db - 0.15) * 0.18 * fade);
        col = mix(col, sunC, smoothstep(px, -px, db - 0.11) * 0.30 * fade);
        col = mix(col, sunC, smoothstep(px, -px, db - 0.072) * fade);
    } else {
        float fade = smoothstep(0.0, -0.4, edge);
        col += vec3(0.55, 0.60, 0.80) * exp(-db * 11.0) * 0.22 * fade;
        float disc = smoothstep(px, -px, db - 0.058) * fade;
        float shadow = smoothstep(px, -px, length(w - body - vec2(0.026, 0.016)) - 0.050);
        vec3 moonC = vec3(0.94, 0.93, 0.86);
        // Mares escuras na parte iluminada.
        moonC *= 1.0 - 0.10 * smoothstep(0.45, 0.75, noise((w - body) * 60.0));
        col = mix(col, moonC, disc * (1.0 - shadow));
        col = mix(col, col * 0.92 + vec3(0.03, 0.035, 0.06), disc * shadow);
    }

    // Nuvens passando devagar; somem à noite.
    float t = iTime * 0.012;
    vec2 cq = vec2(w.x * 2.2 + t, uv.y * 7.0);
    float cn = noise(cq) * 0.6 + noise(cq * 2.1 + 3.7) * 0.3 + noise(cq * 4.3 + 9.1) * 0.1;
    float cloud = smoothstep(0.56, 0.74, cn) * smoothstep(0.48, 0.62, uv.y) * smoothstep(0.98, 0.84, uv.y);
    vec3 cloudC = mix(vec3(0.30, 0.32, 0.45), mix(vec3(1.0), vec3(1.0, 0.78, 0.66), duskK), max(dayK, duskK));
    col = mix(col, cloudC, cloud * mix(0.18, 0.75, max(dayK, duskK * 0.8)));

    // Colinas em camadas; escurecem à noite e esquentam no crepúsculo.
    float ht = iTime * 0.04;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float e = HORIZON + 0.03 - fi * 0.065
                + sin(w.x * (1.5 + fi * 0.5) + fi * 1.9 + ht * (0.4 + fi * 0.2)) * 0.032
                + sin(w.x * (3.9 + fi) + fi * 4.1) * 0.011;
        vec3 layer = mix(vec3(0.36, 0.62, 0.50), vec3(0.06, 0.20, 0.22), fi / 4.0);
        layer = mix(layer, layer * vec3(1.25, 0.80, 0.72), duskK * (1.0 - fi / 4.0) * 0.8);
        layer *= mix(0.28, 1.0, max(dayK, duskK * 0.7));
        col = mix(col, layer, smoothstep(px, -px, uv.y - e));
    }

    // Relógio e data no meio da tela, com um halo para destacar do céu.
    // A tinta troca de branca para azul-escura numa faixa curta, com o halo
    // sempre do tom oposto, para não passar muito tempo num cinza sem contraste.
    float lightK = smoothstep(0.30, 0.40, dayK * (1.0 - duskK));
    vec3 ink = mix(vec3(0.96, 0.97, 1.00), vec3(0.08, 0.17, 0.30), lightK);
    vec3 halo = mix(vec3(0.02, 0.03, 0.08), vec3(1.0), lightK);
    const float S = 0.15, R = 0.012;   // altura dos dígitos e raio do traço
    vec2 cp = p - vec2(0.0, 0.03);
    float d = clockFace(cp / S, hh, mm) * S - R;
    float ds = clockFace((cp + vec2(-0.004, 0.007)) / S, hh, mm) * S - R;
    col = mix(col, halo, smoothstep(0.06, 0.0, d) * 0.20);
    col = mix(col, col * 0.55, smoothstep(0.018, -0.004, ds) * 0.45);
    col = mix(col, ink, smoothstep(px, -px, d));
    const float S2 = 0.018;
    d = dateLine((p - vec2(0.0, -0.14)) / S2, day, month, year) * S2;
    col = mix(col, halo, smoothstep(0.025, 0.0, d) * 0.30);
    col = mix(col, ink, smoothstep(px, -px, d - 0.0024) * 0.92);

    fragColor = vec4(col, 1.0);
}
