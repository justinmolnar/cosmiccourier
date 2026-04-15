// shaders/fog_of_war.glsl
// Cloud fog of war using domain-warped FBM for organic cloud shapes.
// Opacity ramps from translucent near revealed areas to fully opaque far away.

extern vec2  cam_pos;
extern float cam_scale;
extern vec2  vp_offset;
extern vec2  world_pixel_size;
extern Image reveal_mask;
extern vec2  mask_size;
extern float time;
extern vec3  fog_color;
extern float noise_scale;
extern vec2  drift;
extern Image cloud_tex;
extern Image dist_field;  // normalized distance to nearest revealed cell (0=edge, 1=far)

// --- Hash + noise for procedural FBM ---

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
        u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    vec2 shift = vec2(100.0);
    mat2 rot = mat2(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    for (int i = 0; i < 5; i++) {
        v += a * vnoise(p);
        p = rot * p * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc)
{
    vec2 world_pos = (sc - vp_offset) / cam_scale + cam_pos;
    // World wraps horizontally; sample the reveal/dist textures in tile-local
    // UV so looped copies of the world inherit the same fog state. fract on y
    // is a no-op for in-range positions.
    vec2 mask_uv_raw = world_pos / world_pixel_size;
    vec2 mask_uv = vec2(fract(mask_uv_raw.x), fract(mask_uv_raw.y));
    float revealed = Texel(reveal_mask, mask_uv).r;

    // Skip pixels deep inside the revealed area
    if (revealed > 0.92) return vec4(0.0);

    // Distance from nearest revealed cell (0 = at edge, 1 = very far)
    float dist = Texel(dist_field, mask_uv).r;

    // Domain-warped FBM for cloud shapes
    vec2 st = world_pos * noise_scale * 1.5;
    st += drift * time * 30.0;

    vec2 q;
    q.x = fbm(st);
    q.y = fbm(st + vec2(1.0));

    vec2 r;
    r.x = fbm(st + 1.0 * q + vec2(1.7, 9.2) + 0.15 * time * 0.3);
    r.y = fbm(st + 1.0 * q + vec2(8.3, 2.8) + 0.12 * time * 0.3);

    float f = fbm(st + r);

    // Also sample the pre-baked noise for extra detail
    vec2 cloud_uv = world_pos * noise_scale + time * drift;
    float baked = Texel(cloud_tex, cloud_uv).r;
    f = f * 0.8 + baked * 0.2;

    // Cloud density: sculpt the FBM into cloud-like shapes
    float cloud = (f * f * f + 0.6 * f * f + 0.5 * f);
    cloud = clamp(cloud, 0.0, 1.0);

    // Use noise to perturb the reveal boundary — biased inward so fog
    // encroaches into the revealed area rather than bleeding outward
    float edge_noise = f * 0.5 + baked * 0.5;
    float threshold = 0.7 + (edge_noise - 0.5) * 0.4;
    float fog_factor = smoothstep(threshold + 0.1, threshold - 0.1, revealed);

    // Distance-based final opacity: slight haze at edge, fully opaque within a few tiles
    float final_alpha = 0.4 + 0.6 * smoothstep(0.0, 0.015, dist);
    fog_factor = fog_factor * final_alpha;

    // Color: cloud texture only visible in fully opaque areas.
    // In the transition zone use flat fog color so cloud patterns
    // don't create visible streaks against the terrain underneath.
    vec3 bright = fog_color * 1.1;
    vec3 shadow = fog_color * vec3(0.7, 0.72, 0.82);
    float color_blend = smoothstep(0.85, 1.0, fog_factor);
    vec3 col = mix(fog_color, mix(shadow, bright, cloud), color_blend);

    if (fog_factor < 0.01) return vec4(0.0);

    return vec4(col, fog_factor);
}
