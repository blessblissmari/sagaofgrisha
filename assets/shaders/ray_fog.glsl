// Raycaster walls and sprites: the vertex color carries light (r), fog (g)
// and a white hit flash (b) instead of a plain tint.
extern vec3 fogColor;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc)
{
    vec4 c = Texel(tex, tc);
    vec3 rgb = mix(c.rgb * color.r, fogColor, color.g);
    rgb = mix(rgb, vec3(1.0, 1.0, 1.0), color.b);
    return vec4(rgb, c.a * color.a);
}
