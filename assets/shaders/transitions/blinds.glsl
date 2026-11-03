// Transition "blinds": horizontal window blinds close and open.
// progress: 0 = scene visible .. 1 = covered; phase: 0 covering, 1 uncovering
extern number progress;
extern number phase;
extern vec3 color;
extern vec2 center;
extern vec2 screenSize;

vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 px)
{
    vec4 col = Texel(tex, uv);
    float f = fract(px.y / 36.0);
    float p = progress * 1.3 - uv.x * 0.3;
    float cover;
    if (phase < 0.5) {
        cover = step(f, p);
    } else {
        cover = step(1.0 - p, f);
    }
    if (progress > 0.995) {
        cover = 1.0;
    }
    return vec4(mix(col.rgb, color, cover), 1.0) * vcolor;
}
