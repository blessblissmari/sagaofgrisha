// Battle start transition: the picture breaks into bigger and bigger pixels.

extern vec2 screenSize;
extern number amount;     // 0 = normal, 1 = huge pixels

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
    float size = 1.0 + floor(amount * amount * 48.0);
    vec2 cell = size / screenSize;
    vec2 p = (floor(uv / cell) + 0.5) * cell;
    return Texel(tex, p) * color;
}
