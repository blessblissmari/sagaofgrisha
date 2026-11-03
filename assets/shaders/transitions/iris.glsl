// Transition "iris": the new scene opens in a growing circle with a soft rim
// (iris wipe). Reveal transition: Texel(tex) = new scene, previous = old screen.
extern number progress;
extern Image previous;
extern vec2 center;       // 0..1, default the middle of the screen
extern vec2 screenSize;
extern number softness;   // soft rim in pixels (default 40)

vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 px)
{
    vec2 c = center;
    if (c.x == 0.0 && c.y == 0.0) {
        c = vec2(0.5, 0.5);
    }
    vec2 v = (uv - c) * screenSize;
    vec2 far = max(c, 1.0 - c) * screenSize;
    float soft = softness > 0.0 ? softness : 40.0;
    float r = progress * (length(far) + soft);
    float old = smoothstep(r - soft, r, length(v));
    vec3 col = mix(Texel(tex, uv).rgb, Texel(previous, uv).rgb, old);
    return vec4(col, 1.0) * vcolor;
}
