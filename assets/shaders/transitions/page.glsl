// Transition "page": the old screen is turned over like a book page (it rolls on a
// cylinder from the bottom-right corner) and shows the new scene underneath.
// Reveal transition: Texel(tex) is the new scene, `previous` is the old screen.
// Own derivation of the classic cylinder page curl: a sheet rolled on a cylinder of
// radius R shows, at the distance x from the fold, the point with arc length
// R*asin(x/R) (front side) or R*(pi - asin(x/R)) (back side, on top).
extern number progress;   // 0 = old screen .. 1 = new scene
extern Image previous;
extern vec2 screenSize;
extern vec2 direction;    // where the fold moves from (default bottom-right -> top-left)

bool onPage(vec2 q, vec2 size)
{
    return q.x >= 0.0 && q.y >= 0.0 && q.x <= size.x && q.y <= size.y;
}

vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 px)
{
    const float PI = 3.14159265;
    vec2 size = screenSize;
    vec2 p = uv * size;
    vec2 d = direction;
    if (dot(d, d) < 0.0001) {
        d = vec2(1.0, 0.4);
    }
    d = normalize(d);
    float R = size.y * 0.09;
    // the fold line travels from the far corner (along d) to beyond the opposite one
    float sMax = max(0.0, d.x) * size.x + max(0.0, d.y) * size.y;
    float sMin = min(0.0, d.x) * size.x + min(0.0, d.y) * size.y;
    float k = progress * progress * (3.0 - 2.0 * progress);
    float fold = mix(sMax, sMin - R - 2.0, k);
    float x = dot(p, d) - fold;
    vec3 paper = vec3(0.94, 0.91, 0.84);
    vec4 nw = Texel(tex, uv);
    if (x > R) {
        // the new scene with the soft shadow of the roll
        float shadow = 1.0 - 0.5 * (1.0 - smoothstep(R, R * 2.4, x));
        return vec4(nw.rgb * shadow, 1.0) * vcolor;
    }
    if (x >= 0.0) {
        float a = asin(clamp(x / R, 0.0, 1.0));
        // the back of the sheet on the top of the roll
        vec2 q = p + d * (R * (PI - a) - x);
        if (onPage(q, size)) {
            vec3 o = Texel(previous, q / size).rgb;
            float light = 0.62 + 0.38 * cos(a);
            return vec4(mix(paper, o, 0.18) * light, 1.0) * vcolor;
        }
        // the front of the sheet under it
        q = p + d * (R * a - x);
        if (onPage(q, size)) {
            vec3 o = Texel(previous, q / size).rgb;
            return vec4(o * (0.5 + 0.5 * cos(a)), 1.0) * vcolor;
        }
        return vec4(nw.rgb * 0.55, 1.0) * vcolor;
    }
    // flat part: the turned-over sheet may lie on top (back side up)
    vec2 q = p + d * (PI * R - 2.0 * x);
    if (onPage(q, size)) {
        vec3 o = Texel(previous, q / size).rgb;
        float edge = smoothstep(0.0, R * 0.6, -x);
        return vec4(mix(paper, o, 0.18) * (0.9 + 0.1 * edge), 1.0) * vcolor;
    }
    // the old screen that is not turned yet, a little darker near the roll
    vec3 old = Texel(previous, uv).rgb;
    return vec4(old * (0.85 + 0.15 * smoothstep(0.0, R, -x)), 1.0) * vcolor;
}
