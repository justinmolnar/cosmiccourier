// shaders/fog_of_war.glsl
// Cloud fog of war using domain-warped FBM for organic cloud shapes.

extern vec2  cam_pos;
extern float cam_scale;
extern vec2  vp_offset;
extern vec2  world_pixel_size;
extern Image reveal_mask;
extern float time;
extern vec3  fog_color;
extern float cloud_density;
extern float noise_scale;
extern vec2  drift;
extern Image cloud_tex;

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
    vec2 mask_uv = world_pos / world_pixel_size;
    float revealed = Texel(reveal_mask, mask_uv).r;

    // Skip pixels deep inside the revealed area
    if (revealed > 0.92) return vec4(0.0);

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

    // Color: lighter tops, darker shadows
    vec3 bright = fog_color * 1.1;
    vec3 shadow = fog_color * vec3(0.7, 0.72, 0.82);
    vec3 col = mix(shadow, bright, cloud);

    // Use noise to perturb the reveal boundary — biased inward so fog
    // encroaches into the revealed area rather than bleeding outward
    float edge_noise = f * 0.5 + baked * 0.5;
    float threshold = 0.7 + (edge_noise - 0.5) * 0.4;
    float fog_factor = smoothstep(threshold + 0.1, threshold - 0.1, revealed);

    // Modulate opacity with cloud density so thin areas are slightly translucent
    fog_factor *= mix(0.88, 1.0, cloud) * cloud_density;

    if (fog_factor < 0.01) return vec4(0.0);

    return vec4(col, fog_factor);
}
