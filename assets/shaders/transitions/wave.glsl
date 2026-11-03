// Transition "wave": the picture melts in waves (dream / flashback).
// progress: 0 = scene visible .. 1 = covered; phase: 0 covering, 1 uncovering
extern number progress;
extern number phase;
extern vec3 color;
extern vec2 center;
extern vec2 screenSize;

vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 px)
{
    float a = progress * progress;
    vec2 q = uv;
    q.x += sin(uv.y * 38.0 + progress * 22.0) * 0.05 * a;
    q.y += cos(uv.x * 26.0 + progress * 15.0) * 0.02 * a;
    vec4 col = Texel(tex, clamp(q, 0.0, 1.0));
    float k = smoothstep(0.45, 1.0, progress);
    return vec4(mix(col.rgb, color, k), 1.0) * vcolor;
}
