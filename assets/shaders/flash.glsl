// Paints a sprite with one color, keeping its shape (alpha).
// Used for the white "got hit" flash and for outlines (the sprite is drawn
// a few times with an offset in the outline color, then normally on top).

extern number amount;     // 0 = normal sprite, 1 = solid color
extern vec3 flashColor;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
    vec4 c = Texel(tex, uv) * color;
    c.rgb = mix(c.rgb, flashColor, amount);
    return c;
}
