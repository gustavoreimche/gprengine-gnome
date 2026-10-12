// Hexágonos que acendem em ondas.

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(41.3, 289.1))) * 45758.5453);
}

// Centro do hexágono mais próximo e distância até a borda dele.
vec4 hexagon(vec2 p) {
    const vec2 s = vec2(1.0, 1.7320508);
    vec4 centers = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
    vec4 offsets = vec4(p - centers.xy * s, p - (centers.zw + 0.5) * s);
    bool first = dot(offsets.xy, offsets.xy) < dot(offsets.zw, offsets.zw);
    vec2 local = first ? offsets.xy : offsets.zw;
    vec2 id = first ? centers.xy : centers.zw + 0.5;
    vec2 a = abs(local);
    float edge = 0.5 - max(dot(a, s * 0.5), a.x);
    return vec4(local, edge, hash(id) + id.x * 0.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    vec2 g = p * 9.0;
    vec4 h = hexagon(g);
    vec2 center = g - h.xy;

    float wave = sin(length(center) * 0.9 - iTime * 0.9) * 0.5 + 0.5;
    float flicker = 0.5 + 0.5 * sin(iTime * (0.4 + h.w) + h.w * 30.0);
    float glow = pow(wave, 3.0) * 0.75 + flicker * 0.25;

    float px = 9.0 * 1.5 / iResolution.y;
    float border = 1.0 - smoothstep(0.03, 0.03 + px, h.z);
    float fill = smoothstep(0.03, 0.30, h.z);

    vec3 tint = mix(vec3(0.10, 0.55, 0.95), vec3(0.75, 0.25, 0.95), h.w);
    vec3 col = vec3(0.03, 0.04, 0.08);
    col += tint * fill * glow * 0.42;
    col += tint * border * (0.12 + glow * 0.55);
    col *= 1.0 - 0.35 * dot(p, p);
    fragColor = vec4(col, 1.0);
}
