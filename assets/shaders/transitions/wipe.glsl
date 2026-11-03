// Transition "wipe": a soft diagonal curtain from left to right.
// progress: 0 = scene visible .. 1 = covered; phase: 0 covering, 1 uncovering
extern number progress;
extern number phase;
extern vec3 color;
extern vec2 center;
extern vec2 screenSize;

vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 px)
{
    vec4 col = Texel(tex, uv);
    float t = uv.x * 0.8 + (1.0 - uv.y) * 0.2;
    float edge = 0.06;
    float e = progress * (1.0 + edge);
    float cover;
    if (phase < 0.5) {
        cover = 1.0 - smoothstep(e - edge, e, t);
    } else {
        cover = smoothstep(1.0 - e, 1.0 - e + edge, t);
    }
    return vec4(mix(col.rgb, color, cover), 1.0) * vcolor;
}
