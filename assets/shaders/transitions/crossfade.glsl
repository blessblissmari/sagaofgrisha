// Transition "crossfade": the old screen melts into the new one.
extern number progress;
extern Image previous;

vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 px)
{
    float k = progress * progress * (3.0 - 2.0 * progress);
    return vec4(mix(Texel(previous, uv).rgb, Texel(tex, uv).rgb, k), 1.0) * vcolor;
}
