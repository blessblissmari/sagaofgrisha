// Gentle horizontal sway for background layers (trees, clouds) in the novel:
// every row of pixels moves by a sine of its height and time.

extern number time;
extern vec2 textureSize;
extern number amount;      // pixels

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
    float row = floor(uv.y * textureSize.y);
    float weight = 1.0 - uv.y;               // the tops of the trees move more
    float dx = floor(sin(time * 1.3 + row * 0.15) * amount * weight + 0.5);
    return Texel(tex, uv + vec2(dx / textureSize.x, 0.0)) * color;
}
