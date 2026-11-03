// Transition "diamond": a sweep of growing diamonds (old console games).
// progress: 0 = scene visible .. 1 = covered; phase: 0 covering, 1 uncovering
extern number progress;
extern number phase;
extern vec3 color;
extern vec2 center;
extern vec2 screenSize;

vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 px)
{
    vec4 col = Texel(tex, uv);
    vec2 f = fract(px / 48.0) - 0.5;
    float d = abs(f.x) + abs(f.y);
    float pos;
    if (phase < 0.5) {
        pos = uv.x * 0.8 + uv.y * 0.4;
    } else {
        pos = (1.0 - uv.x) * 0.8 + (1.0 - uv.y) * 0.4;
    }
    float sweep = progress * 2.2 - pos - 0.001;
    float cover = step(d, sweep);
    return vec4(mix(col.rgb, color, cover), 1.0) * vcolor;
}
