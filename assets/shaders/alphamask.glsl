// Draws only the solid pixels of a picture (for stencil masks: what stands in
// front of whom, see the x-ray silhouettes in game/modes/iso.lua).

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
    vec4 c = Texel(tex, uv) * color;
    if (c.a < 0.5) {
        discard;
    }
    return c;
}
