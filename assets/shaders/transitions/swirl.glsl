// Transition "swirl": Final Fantasy style vortex that sucks the picture in.
// progress: 0 = scene visible .. 1 = covered; phase: 0 covering, 1 uncovering
extern number progress;
extern number phase;
extern vec3 color;
extern vec2 center;
extern vec2 screenSize;

vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 px)
{
    vec2 aspect = vec2(screenSize.x / screenSize.y, 1.0);
    vec2 d = (uv - center) * aspect;
    float r = length(d);
    float p = progress * progress;
    float angle = p * 10.0 * max(0.0, 1.3 - r);
    float s = sin(angle);
    float c = cos(angle);
    d = vec2(d.x * c - d.y * s, d.x * s + d.y * c);
    d *= 1.0 + p * 0.6;
    vec2 q = d / aspect + center;
    vec4 col = Texel(tex, clamp(q, 0.0, 1.0));
    float k = smoothstep(0.55, 1.0, progress);
    return vec4(mix(col.rgb, color, k), 1.0) * vcolor;
}
