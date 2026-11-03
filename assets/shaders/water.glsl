// Animated pixel-art water with reflections and shore foam.
//
// The water tile layer is drawn into a canvas, then that canvas is drawn
// through this shader (see engine/world.lua, World:drawShaded).
//
// Ideas taken from:
//  * InJuly, "Water surface shader for 2D pixel art games":
//    reflections = entities drawn flipped vertically into their own canvas,
//    blue tint, and sin * cos waves that displace the texture over time.
//    https://injuly.in/blog/water-shader/index.html
//  * Alex Griffith, "LOVE2D Shaders" (the water of the game Potions):
//    a mask decides which pixels are water and how much they move.
//    https://alexjgriffith.com/3.html
//  * LOVE wiki, "Introduction to shaders" (effect(), Texel, extern):
//    https://www.love2d.org/wiki/Tutorial:Introduction_to_Shaders
//
// Here the mask is the color itself (bluish pixels are water), so no extra
// mask texture is needed and the island tiles are left untouched.
// All waves are computed in WORLD pixels and rounded to whole pixels:
// they stay attached to the map while the camera moves, and the result
// still looks like pixel art.

extern number time;
extern vec2 canvasSize;          // size of the drawn texture in pixels
extern vec2 worldOffset;         // world position of its top left pixel
extern number zoom;              // texture pixels per world pixel
extern Image reflection;         // reflections canvas (same size)
extern number reflectionStrength;
extern number maskMode;          // 1: only bluish pixels are water, 0: everything
extern number waveHeight;        // in world pixels

bool isWater(vec4 c) {
    if (maskMode < 0.5) {
        return c.a > 0.5;
    }
    return c.a > 0.5 && c.b - max(c.r, c.g) > 0.05;
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
    vec4 base = Texel(tex, uv);
    if (!isWater(base)) {
        return base * color;
    }
    vec2 px = 1.0 / canvasSize;
    vec2 world = floor(uv * canvasSize / zoom + worldOffset);

    // 1. waves: move the texture a little, like in the InJuly article
    float dx = sin(world.y * 0.21 + time * 1.7) * cos(world.y * 0.07 - time * 0.8) * waveHeight;
    float dy = sin(world.x * 0.13 + time * 1.2) * cos(world.x * 0.05 + time * 0.6) * waveHeight * 0.5;
    vec2 shift = floor(vec2(dx, dy) + 0.5) * zoom * px;
    vec4 moved = Texel(tex, uv + shift);
    // never pull the shore into the water
    vec4 water = isWater(moved) ? moved : base;

    // 2. foam along the shore: how far is the nearest land pixel (1..3)?
    float shore = 0.0;
    for (int i = 3; i >= 1; i--) {
        vec2 d = vec2(float(i) * zoom) * px;
        if (!isWater(Texel(tex, uv + vec2(d.x, 0.0))) || !isWater(Texel(tex, uv - vec2(d.x, 0.0))) ||
            !isWater(Texel(tex, uv + vec2(0.0, d.y))) || !isWater(Texel(tex, uv - vec2(0.0, d.y)))) {
            shore = float(i);
        }
    }
    if (shore > 0.0) {
        float pulse = sin(time * 2.4 - shore * 1.6 + hash(floor(world / 8.0)) * 6.283);
        float foam = 0.0;
        if (shore < 1.5) {
            foam = 0.45 + 0.2 * pulse;
        } else if (pulse > 0.35) {
            foam = shore < 2.5 ? 0.35 : 0.2;
        }
        water.rgb = mix(water.rgb, vec3(0.62, 0.78, 0.92), foam);
    }

    // 3. reflections of the entities, distorted a bit more than the water
    if (reflectionStrength > 0.0) {
        float rx = sin(world.y * 0.45 + time * 3.1) * cos(world.y * 0.13 + time * 1.4) * (waveHeight + 0.6);
        vec4 r = Texel(reflection, uv + vec2(floor(rx + 0.5) * zoom * px.x, 0.0));
        if (r.a > 0.01) {
            vec3 rc = r.rgb / r.a; // the canvas holds premultiplied colors
            rc = mix(rc, vec3(0.2, 0.3, 0.6), 0.45); // water absorbs red and green
            water.rgb = mix(water.rgb, rc, r.a * reflectionStrength);
        }
    }

    // 4. sparkles: a few random pixels blink
    vec2 cell = floor(world / 4.0);
    float h = hash(cell);
    vec2 inCell = world - cell * 4.0;
    if (h > 0.97 && inCell.x == 1.0 && inCell.y == 1.0) {
        float blink = sin(time * (1.3 + h * 2.0) + h * 50.0);
        if (blink > 0.85) {
            water.rgb = mix(water.rgb, vec3(0.9, 0.95, 1.0), 0.75);
        }
    }

    return vec4(water.rgb, 1.0) * color;
}
