import Cogl from 'gi://Cogl';
import GObject from 'gi://GObject';
import Shell from 'gi://Shell';

const DECLARATIONS = `
uniform vec2 actor_size;
uniform vec4 clip_bounds;
uniform float clip_radius;
`;

// Distância com sinal até um retângulo de cantos arredondados; fora dele o
// pixel some. A cor é pré-multiplicada, então basta escalar tudo.
const CODE = `
vec2 p = cogl_tex_coord0_in.xy * actor_size;
vec2 center = (clip_bounds.xy + clip_bounds.zw) * 0.5;
vec2 half_size = (clip_bounds.zw - clip_bounds.xy) * 0.5;
vec2 q = abs(p - center) - half_size + clip_radius;
float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - clip_radius;
cogl_color_out *= 1.0 - smoothstep(-0.5, 0.5, d);
`;

// Recorta o ator num retângulo de cantos arredondados, como o
// MetaBackgroundContent faz com o fundo estático na visão geral.
export const RoundedClipEffect = GObject.registerClass(
class PrimoEngineRoundedClipEffect extends Shell.GLSLEffect {
    vfunc_build_pipeline() {
        this.add_glsl_snippet(
            Cogl.SnippetHook.FRAGMENT, DECLARATIONS, CODE, false);
    }

    setClip(width, height, bounds, radius) {
        this.set_uniform_float(
            this.get_uniform_location('actor_size'), 2, [width, height]);
        this.set_uniform_float(
            this.get_uniform_location('clip_bounds'), 4, bounds);
        this.set_uniform_float(
            this.get_uniform_location('clip_radius'), 1, [radius]);
        this.queue_repaint();
    }
});
