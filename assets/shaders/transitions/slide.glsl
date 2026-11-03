// Transition "slide": the new scene pushes the old one out of the screen.
extern number progress;
extern Image previous;
extern vec2 direction;    // where the old screen goes: (-1,0) to the left (default), (0,1) down...

vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 px)
{
    vec2 d = direction;
    if (dot(d, d) < 0.0001) {
        d = vec2(-1.0, 0.0);
    }
    d = normalize(d);
    float k = progress * progress * (3.0 - 2.0 * progress);
    vec2 shift = d * k;
    // the old screen moved by shift, the new one comes from the opposite side
    vec2 a = uv - shift;
    vec2 b = uv - shift + d;
    vec3 col;
    if (a.x >= 0.0 && a.x <= 1.0 && a.y >= 0.0 && a.y <= 1.0) {
        col = Texel(previous, a).rgb * (1.0 - 0.3 * k);
    } else {
        col = Texel(tex, clamp(b, 0.0, 1.0)).rgb;
    }
    return vec4(col, 1.0) * vcolor;
}
