// PlayStation 1 look for engine/r3d.lua (the world map). One file, three shaders:
//   model   (default)       textured triangles and sprites, textures from an atlas
//   TERRAIN (#define)       the ground: up to 8 textures blended by vertex weights,
//                           with ragged pixel-art borders between them
//   WATER   (#define)       the sea: scrolling waves, depth colour, foam at the shore
// Common: vertices snapped to the pixels of the small canvas (the PS1 "wobble"),
// affine texture mapping, per-vertex fog, the world bending down with the distance
// (a small round planet), 15-bit colour with ordered dithering.

varying float v_fog;
varying float v_depth;
#ifdef TERRAIN
varying vec4 v_w1;
varying vec4 v_w2;
#else
varying vec4 v_rect;
varying vec3 v_affine;
#endif
#ifdef WATER
varying vec2 v_world;
#endif

#ifdef VERTEX
uniform mat4 u_proj;
uniform mat4 u_view;
uniform vec3 u_offset;   // the copy of the world this chunk is drawn at (the world wraps)
uniform vec2 u_rot;      // cos, sin of a turn around y (moving models: the boat), 1, 0 = none
uniform vec3 u_center;   // the point the camera looks at: the world bends around it
uniform float u_curve;   // y -= distance^2 * curve
uniform vec2 u_snap;     // half the canvas size in pixels, 0 = no vertex snapping
uniform vec2 u_fog;      // fog start and end (distance from the eye)
uniform float u_wave;    // time for the waves
#ifdef TERRAIN
attribute vec4 a_w1;
attribute vec4 a_w2;
#else
attribute vec4 a_rect;
#endif

vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    vec4 world = vertex_position;
    world.xz = vec2(world.x * u_rot.x + world.z * u_rot.y, world.z * u_rot.x - world.x * u_rot.y);
    world.xyz += u_offset;
#ifdef WATER
    // VertexColor.a = how deep the water is: waves only out at sea
    world.y += sin(u_wave * 1.6 + world.x * 1.7 + world.z * 0.8) * 0.04 * VertexColor.a;
    v_world = VertexTexCoord.xy;
#endif
    vec2 d = world.xz - u_center.xz;
    world.y -= dot(d, d) * u_curve;
    vec4 view = u_view * world;
    vec4 clip = u_proj * view;
    if (u_snap.x > 0.0 && clip.w > 0.05) {
        clip.xy = floor(clip.xy / clip.w * u_snap + 0.5) / u_snap * clip.w;
    }
    v_fog = clamp((length(view.xyz) - u_fog.x) / (u_fog.y - u_fog.x), 0.0, 1.0);
    v_depth = clip.w;
#ifdef TERRAIN
    v_w1 = a_w1;
    v_w2 = a_w2;
#else
    v_rect = a_rect;
    v_affine = vec3(VertexTexCoord.xy * clip.w, clip.w);
#endif
    clip.y = -clip.y; // we always draw into a canvas
    return clip;
}
#endif

#ifdef PIXEL
uniform vec3 u_fogColor;
uniform float u_affine;  // 0 = correct textures, 1 = PS1 affine textures
uniform float u_time;
#ifdef TERRAIN
uniform vec4 u_layer[8];    // atlas rectangle of every ground texture
uniform float u_repeat[8];  // world units per texture
uniform vec2 u_period;      // the world size: the noise wraps with the world
uniform float u_texels;     // texture pixels per world unit
uniform float u_edge;       // how ragged the borders between the grounds are
#endif
#if !defined(TERRAIN) && !defined(WATER)
uniform vec4 u_focus;       // see-through circle around the hero: x, y (pixels), radius, depth
#endif
#ifdef WATER
uniform vec4 u_waterRect;   // the water texture in its image (atlas rectangle)
uniform float u_waterRepeat;
uniform vec3 u_deep;        // colour of the open sea
uniform vec3 u_shallow;     // colour near the shore
#endif

float bayer2(vec2 a) { a = floor(a); return fract(dot(a, vec2(0.5, a.y * 0.75))); }
float bayer4(vec2 a) { return bayer2(0.5 * a) * 0.25 + bayer2(a); }

vec3 finish(vec3 c, vec2 px)
{
    c = mix(c, u_fogColor, v_fog);
    return floor(c * 31.0 + bayer4(px)) / 31.0;
}

#if defined(TERRAIN) || defined(WATER)
float hash(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
#endif

#ifdef TERRAIN
float vnoise(vec2 p, vec2 period)
{
    vec2 i = floor(p);
    vec2 f = p - i;
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash(mod(i, period));
    float b = hash(mod(i + vec2(1.0, 0.0), period));
    float c = hash(mod(i + vec2(0.0, 1.0), period));
    float e = hash(mod(i + vec2(1.0, 1.0), period));
    return mix(mix(a, b, u.x), mix(c, e, u.x), u.y);
}
#endif

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 px)
{
#ifdef TERRAIN
    // tc = world x, z. Every ground gets a ragged score, the best one is drawn.
    vec2 q = (floor(tc * u_texels) + 0.5) / u_texels;   // whole texture pixels
    vec2 per = u_period * 2.0;
    float jit = (hash(floor(q * u_texels)) - 0.5) * 0.08;
    float s[8];
    s[0] = v_w1.x + (vnoise(q * 2.0, per) - 0.5) * u_edge;
    s[1] = v_w1.y + (vnoise(q * 2.0 + vec2(17.0, 3.0), per) - 0.5) * u_edge;
    s[2] = v_w1.z + (vnoise(q * 2.0 + vec2(5.0, 29.0), per) - 0.5) * u_edge;
    s[3] = v_w1.w + (vnoise(q * 2.0 + vec2(41.0, 13.0), per) - 0.5) * u_edge;
    s[4] = v_w2.x + (vnoise(q * 2.0 + vec2(23.0, 47.0), per) - 0.5) * u_edge;
    s[5] = v_w2.y + (vnoise(q * 2.0 + vec2(59.0, 7.0), per) - 0.5) * u_edge;
    s[6] = v_w2.z + (vnoise(q * 2.0 + vec2(11.0, 61.0), per) - 0.5) * u_edge;
    s[7] = v_w2.w + (vnoise(q * 2.0 + vec2(37.0, 53.0), per) - 0.5) * u_edge;
    float best = s[0] + jit;
    vec4 rect = u_layer[0];
    float rep = u_repeat[0];
    for (int i = 1; i < 8; i++) {
        if (s[i] + jit * float(i) * 0.37 > best) {
            best = s[i] + jit * float(i) * 0.37;
            rect = u_layer[i];
            rep = u_repeat[i];
        }
    }
    vec2 uv = rect.xy + fract(tc / rep) * rect.zw;
    vec4 c = Texel(tex, uv) * color;
    return vec4(finish(c.rgb, px), 1.0);
#else
#ifdef WATER
    vec2 w = v_world / u_waterRepeat;
    vec2 a = fract(w + vec2(u_time * 0.035, u_time * 0.02));
    vec2 b = fract(w * 0.7 + vec2(-u_time * 0.025, u_time * 0.03) + 0.37);
    vec3 t1 = Texel(tex, u_waterRect.xy + a * u_waterRect.zw).rgb;
    vec3 t2 = Texel(tex, u_waterRect.xy + b * u_waterRect.zw).rgb;
    vec3 t = (t1 + t2) * 0.5;
    float deep = color.a;                       // 0 at the shore .. 1 open sea
    vec3 base = mix(u_shallow, u_deep, deep);
    vec3 c = base * (0.55 + t * 0.9) * color.rgb;
    // foam: a ragged white line where the water is shallow
    vec2 cell = floor(v_world * 16.0);
    float f = hash(cell + floor(u_time * 2.0));
    if (deep < 0.12 + 0.06 * sin(u_time * 2.0 + v_world.x * 3.0) && f > 0.35) {
        c = mix(c, vec3(0.93, 0.97, 1.0), 0.75);
    }
    float alpha = mix(0.55, 0.92, deep);
    return vec4(finish(c, px), alpha);
#else
    vec2 uv = tc;
    if (u_affine > 0.0) {
        uv = mix(tc, v_affine.xy / v_affine.z, u_affine);
    }
    if (v_rect.z > 0.0) {
        uv = v_rect.xy + fract(uv) * v_rect.zw;
    }
    vec4 c = Texel(tex, uv) * color;
    // transparency is dithered (no sorting needed): 0.5 alpha = every other pixel
    if (c.a < bayer4(px) * 0.96 + 0.02) {
        discard;
    }
    // trees and houses between the camera and the hero: see-through (dithered)
    if (u_focus.z > 0.0 && v_depth < u_focus.w) {
        float k = 1.0 - smoothstep(u_focus.z * 0.55, u_focus.z, length(px - u_focus.xy));
        if (bayer4(px) < k * 0.75) {
            discard;
        }
    }
    return vec4(finish(c.rgb, px), 1.0);
#endif
#endif
}
#endif
