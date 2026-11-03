// Sky sphere, in the spirit of Godot's ProceduralSkyMaterial: a sky gradient with a
// sun, drifting clouds and stars, a ground plane that fades into the horizon, and
// an optional panorama band (old-school parallax art wrapped around the camera).
// For every pixel the view ray of a camera (yaw, pitch, vertical fov) becomes a
// direction on the sphere, so the sky turns and tilts together with the camera.
extern vec2 screenSize;
extern number yaw;
extern number pitch;
extern number fov;
extern vec3 topColor;
extern vec3 horizonColor;
extern vec3 groundColor;
extern vec3 groundHorizon;
extern vec3 sunDir;
extern vec3 sunColor;
extern number sunSize;      // angular radius of the disc, radians
extern number clouds;       // 0..1 coverage
extern vec3 cloudColor;
extern number stars;        // 0..1
extern number grid;         // 0..1 how visible the ground pattern is
extern number time;
extern number useBand;
extern Image band;          // the panorama band (full turn wide)
extern vec2 bandLat;        // latitude of its bottom and top, radians

float hash(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p)
{
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * noise(p);
        p = p * 2.03 + vec2(17.0, 9.0);
        a *= 0.5;
    }
    return v;
}

vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 px)
{
    const float PI = 3.14159265;
    // the view ray
    float cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch);
    vec3 forward = vec3(sy * cp, sp, cy * cp);
    vec3 right = vec3(cy, 0.0, -sy);
    vec3 up = vec3(-sy * sp, cp, -cy * sp);
    float t = tan(fov * 0.5);
    vec2 ndc = vec2((px.x - screenSize.x * 0.5) / (screenSize.y * 0.5), (screenSize.y * 0.5 - px.y) / (screenSize.y * 0.5));
    vec3 dir = normalize(forward + right * ndc.x * t + up * ndc.y * t);
    vec3 col;
    if (dir.y >= 0.0) {
        col = mix(horizonColor, topColor, pow(dir.y, 0.6));
        // stars
        if (stars > 0.0) {
            vec2 sph = vec2(atan(dir.x, dir.z), asin(dir.y)) * 90.0;
            vec2 cell = floor(sph);
            float h = hash(cell);
            if (h > 1.0 - 0.06 * stars) {
                vec2 c = cell + 0.5 + (vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5) * 0.6;
                float d = length(sph - c);
                float tw = 0.6 + 0.4 * sin(time * (1.5 + h * 3.0) + h * 40.0);
                col += vec3(1.0, 0.97, 0.9) * (1.0 - smoothstep(0.0, 0.35, d)) * tw * stars * smoothstep(0.0, 0.15, dir.y);
            }
        }
        // clouds on a flat layer high above
        if (clouds > 0.0 && dir.y > 0.01) {
            vec2 p = dir.xz / (dir.y + 0.08) * 1.4 + vec2(time * 0.02, time * 0.008);
            float n = fbm(p);
            float cover = smoothstep(1.0 - clouds * 0.85, 1.25 - clouds * 0.85, n);
            cover *= smoothstep(0.01, 0.2, dir.y);
            col = mix(col, cloudColor * (0.85 + 0.25 * n), cover * 0.9);
        }
    } else {
        col = mix(groundHorizon, groundColor, pow(-dir.y, 0.45));
        // a faint pattern on the ground plane makes the turning visible
        if (grid > 0.0) {
            vec2 q = dir.xz / -dir.y * 3.0;
            float n = fbm(q * 0.7);
            float fade = smoothstep(0.0, 0.25, -dir.y);
            col *= 1.0 - grid * fade * (0.18 * n + 0.08 * step(0.5, fract((floor(q.x) + floor(q.y)) * 0.5)));
        }
    }
    // the sun with its glow
    float sd = dot(dir, normalize(sunDir));
    float glow = pow(max(sd, 0.0), 24.0) * 0.35 + pow(max(sd, 0.0), 300.0) * 0.6;
    col += sunColor * glow;
    if (sd > cos(sunSize)) {
        col = mix(col, sunColor, 0.95);
    }
    // the panorama band (parallax art) around the horizon
    if (useBand > 0.5) {
        float lat = asin(clamp(dir.y, -1.0, 1.0));
        if (lat > bandLat.x && lat < bandLat.y) {
            float u = atan(dir.x, dir.z) / (2.0 * PI) + 0.5;
            float v = (bandLat.y - lat) / (bandLat.y - bandLat.x);
            vec4 b = Texel(band, vec2(u, v));
            col = mix(col, b.rgb, b.a);
        }
    }
    // haze at the horizon
    col = mix(col, horizonColor, (1.0 - smoothstep(0.0, 0.06, abs(dir.y))) * 0.35);
    return vec4(col, 1.0) * vcolor;
}
