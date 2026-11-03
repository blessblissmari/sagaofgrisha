// Raycaster floor and ceiling: for every pixel below (above) the horizon the
// floor (ceiling) point is found from the camera and a texture of the wall
// atlas is sampled. Same math as Lode Vandevenne's "Raycasting II: Floor and
// Ceiling" (https://lodev.org/cgtutor/raycasting2.html), done on the GPU.
// GLSL ES 1.0 safe (works in the web build).
extern Image atlas;
extern vec2 pos;
extern vec2 dir;
extern vec2 plane;
extern vec2 size;
extern float horizon;
extern vec4 floorRect;
extern vec4 ceilRect;
extern vec3 fogColor;
extern float fogDist;
extern float light;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc)
{
    float x = tc.x * size.x;
    float y = tc.y * size.y;
    float p = y - horizon;
    float ap = max(abs(p), 0.5);
    float rowDist = (0.5 * size.y) / ap;
    float camX = 2.0 * x / size.x - 1.0;
    vec2 ray = dir + plane * camX;
    vec2 world = pos + ray * rowDist;
    vec2 f = fract(world);
    vec4 rect = mix(ceilRect, floorRect, step(0.0, p));
    vec2 uv = rect.xy + clamp(f, 0.002, 0.998) * rect.zw;
    vec4 c = Texel(atlas, uv);
    float fog = clamp(rowDist / fogDist, 0.0, 1.0);
    float shade = mix(0.55, 1.0, step(0.0, p)); // the ceiling is darker
    vec3 rgb = mix(c.rgb * light * shade, fogColor, fog);
    return vec4(rgb, 1.0) * color;
}
