// Transition "clock": a clock hand sweeps around the center and reveals the new scene
// (another Star Wars favourite). Reveal transition: Texel(tex) = new, previous = old.
extern number progress;
extern Image previous;
extern vec2 center;       // 0..1, default the middle of the screen
extern vec2 screenSize;
extern number softness;   // soft edge, part of a full turn (default 0.04)

vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 px)
{
    const float PI = 3.14159265;
    vec2 c = center;
    if (c.x == 0.0 && c.y == 0.0) {
        c = vec2(0.5, 0.5);
    }
    vec2 v = (uv - c) * screenSize;
    // 0 at twelve o'clock, growing clockwise
    float a = atan(v.x, -v.y);
    float t = mod(a + 2.0 * PI, 2.0 * PI) / (2.0 * PI);
    float soft = softness > 0.0 ? softness : 0.04;
    float e = progress * (1.0 + soft);
    float old = smoothstep(e - soft, e, t);
    vec3 col = mix(Texel(tex, uv).rgb, Texel(previous, uv).rgb, old);
    return vec4(col, 1.0) * vcolor;
}
