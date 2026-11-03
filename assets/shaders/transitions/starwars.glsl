// Transition "starwars": the classic Star Wars wipe - a line moves across the screen
// and the new scene replaces the old one behind it; the edge is soft, so the line
// itself is invisible. Reveal transition: Texel(tex) = new scene, previous = old.
extern number progress;   // 0 = old .. 1 = new
extern Image previous;
extern vec2 direction;    // (1,0) left -> right (default), (0,1) top -> bottom, (1,1) diagonal
extern number softness;   // width of the soft edge, part of the screen (default 0.12)

vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 px)
{
    vec2 d = direction;
    if (dot(d, d) < 0.0001) {
        d = vec2(1.0, 0.0);
    }
    d = normalize(d);
    float lo = min(0.0, d.x) + min(0.0, d.y);
    float hi = max(0.0, d.x) + max(0.0, d.y);
    float t = (dot(uv, d) - lo) / (hi - lo);
    float soft = softness > 0.0 ? softness : 0.12;
    float e = progress * (1.0 + soft);
    float old = smoothstep(e - soft, e, t);
    vec3 c = mix(Texel(tex, uv).rgb, Texel(previous, uv).rgb, old);
    return vec4(c, 1.0) * vcolor;
}
