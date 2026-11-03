// Transition "circle": iris closes on the center point (the hero) and opens again.
// progress: 0 = scene visible .. 1 = covered; phase: 0 covering, 1 uncovering
extern number progress;
extern number phase;
extern vec3 color;
extern vec2 center;
extern vec2 screenSize;

vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 px)
{
    vec4 col = Texel(tex, uv);
    vec2 aspect = vec2(screenSize.x / screenSize.y, 1.0);
    vec2 block = (floor(px / 4.0) * 4.0 + 2.0) / screenSize;  // chunky edge
    float r = length((block - center) * aspect);
    vec2 far = max(center, 1.0 - center) * aspect;
    float radius = (1.0 - progress) * (length(far) + 0.02);
    float cover = step(radius, r);
    if (progress > 0.995) {
        cover = 1.0;
    }
    return vec4(mix(col.rgb, color, cover), 1.0) * vcolor;
}
