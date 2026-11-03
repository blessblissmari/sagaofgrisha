// Transition "dissolve": random blocks vanish one by one.
// progress: 0 = scene visible .. 1 = covered; phase: 0 covering, 1 uncovering
extern number progress;
extern number phase;
extern vec3 color;
extern vec2 center;
extern vec2 screenSize;

float hash(vec2 p)
{
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 px)
{
    vec4 col = Texel(tex, uv);
    vec2 cell = floor(px / 12.0);
    float n = hash(cell + vec2(phase * 17.0, phase * 31.0));
    float cover = step(n, progress * 1.02 - 0.01);
    return vec4(mix(col.rgb, color, cover), 1.0) * vcolor;
}
