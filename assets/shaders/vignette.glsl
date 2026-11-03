// Darker corners and an optional color tint (evening, danger...).

extern vec2 screenSize;
extern number strength;   // 0..1
extern vec3 tint;         // multiplied with the picture, (1, 1, 1) = none

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
    vec4 c = Texel(tex, uv);
    vec2 cc = (uv - 0.5) * vec2(screenSize.x / screenSize.y, 1.0);
    float v = smoothstep(0.95, 0.35, length(cc));
    c.rgb *= mix(1.0 - strength, 1.0, v);
    c.rgb *= tint;
    return c * color;
}
