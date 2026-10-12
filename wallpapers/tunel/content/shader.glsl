// Túnel de anéis de néon vindo na sua direção.

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    // O centro passeia um pouco, para o túnel parecer fazer curva.
    p -= vec2(sin(iTime * 0.21), cos(iTime * 0.17)) * 0.10;

    float r = length(p);
    float a = atan(p.y, p.x);
    float depth = 0.35 / (r + 0.02);
    float z = depth * 3.0 + iTime * 1.2;

    // Quanto do padrão cabe num pixel, para as linhas não serrilharem longe.
    float pixel = 3.0 * depth * depth / 0.35 * 1.5 / iResolution.y;
    float ring = 1.0 - smoothstep(0.0, 0.035 + pixel * 2.0, abs(fract(z) - 0.5)) * exp(-pixel * 6.0);
    float spoke = 1.0 - smoothstep(0.0, 0.02 + 0.004 / (r + 0.02),
                                   abs(fract(a * 12.0 / 6.2831853) - 0.5));

    vec3 tint = 0.5 + 0.5 * cos(vec3(0.0, 2.1, 4.2) + floor(z) * 0.45 + iTime * 0.15);
    float fog = smoothstep(0.0, 0.45, r);
    vec3 col = vec3(0.02, 0.01, 0.05);
    col += tint * ring * fog * 0.95;
    col += vec3(0.25, 0.35, 0.90) * spoke * fog * 0.22;
    col += vec3(0.60, 0.40, 1.00) * exp(-r * 9.0) * 0.5;
    fragColor = vec4(col, 1.0);
}
