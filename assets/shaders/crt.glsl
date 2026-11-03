// Old TV look for the arcade: curved screen, scanlines, a little color
// fringing and dark corners. Post effect for the whole screen.
// Based on the classic CRT shader tricks: barrel distortion of uv,
// a sine of the pixel row for scanlines, sampling r/g/b with small offsets.

extern vec2 screenSize;
extern number time;
extern number curvature;   // 0 = flat
extern number scanlines;   // 0..1 strength

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
    vec2 cc = uv - 0.5;
    vec2 duv = uv + cc * dot(cc, cc) * curvature;
    if (duv.x < 0.0 || duv.x > 1.0 || duv.y < 0.0 || duv.y > 1.0) {
        return vec4(0.0, 0.0, 0.0, 1.0);
    }
    float shift = 0.7 / screenSize.x;
    vec3 col;
    col.r = Texel(tex, duv + vec2(shift, 0.0)).r;
    col.g = Texel(tex, duv).g;
    col.b = Texel(tex, duv - vec2(shift, 0.0)).b;
    float line = sin(duv.y * screenSize.y * 3.14159);
    col *= 1.0 - scanlines * (0.5 - 0.5 * line);
    col *= 1.0 + 0.015 * sin(time * 60.0);
    float vignette = smoothstep(0.85, 0.3, length(cc * vec2(1.0, 1.15)));
    col *= mix(0.55, 1.08, vignette);
    return vec4(col, 1.0) * color;
}
