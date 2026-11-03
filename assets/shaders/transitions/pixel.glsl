// Transition "pixel": the picture breaks into growing pixels (classic RPG battle start).
// progress: 0 = scene visible .. 1 = covered; phase: 0 covering, 1 uncovering
extern number progress;
extern number phase;
extern vec3 color;
extern vec2 center;
extern vec2 screenSize;

vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 px)
{
    float size = 1.0 + floor(progress * progress * 48.0);
    vec2 cell = vec2(size) / screenSize;
    vec2 p = (floor(uv / cell) + 0.5) * cell;
    vec4 c = Texel(tex, clamp(p, 0.0, 1.0));
    float k = clamp(progress * 1.4 - 0.4, 0.0, 1.0);
    return vec4(mix(c.rgb, color, k), 1.0) * vcolor;
}
