// Transition "battle": two white flashes, then the picture shatters into a vortex.
// progress: 0 = scene visible .. 1 = covered; phase: 0 covering, 1 uncovering
extern number progress;
extern number phase;
extern vec3 color;
extern vec2 center;
extern vec2 screenSize;

vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 px)
{
    if (phase > 0.5) {
        vec4 c = Texel(tex, uv);
        return vec4(mix(c.rgb, color, progress), 1.0) * vcolor;
    }
    float flash = 0.0;
    float t = progress / 0.35;
    if (t < 1.0) {
        flash = abs(sin(t * 6.2831));
    }
    float p = clamp((progress - 0.35) / 0.65, 0.0, 1.0);
    vec2 aspect = vec2(screenSize.x / screenSize.y, 1.0);
    vec2 d = (uv - center) * aspect;
    float r = length(d);
    float angle = p * p * 12.0 * max(0.0, 1.4 - r);
    float s = sin(angle);
    float c = cos(angle);
    d = vec2(d.x * c - d.y * s, d.x * s + d.y * c) * (1.0 + p * 0.8);
    vec2 q = d / aspect + center;
    float size = 1.0 + floor(p * 24.0);
    vec2 cell = vec2(size) / screenSize;
    q = (floor(q / cell) + 0.5) * cell;
    vec3 col = Texel(tex, clamp(q, 0.0, 1.0)).rgb;
    col = mix(col, vec3(1.0), flash * 0.85);
    col = mix(col, color, smoothstep(0.5, 1.0, p));
    return vec4(col, 1.0) * vcolor;
}
