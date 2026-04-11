shader_type canvas_item;

// Local sampling radius is hardcoded for loop unrolling.
// Tunables below control which pixels qualify and how aggressively they darken.

// A pixel counts as "dark opaque" (hair sample) if its max channel is below this.
uniform float hair_brightness_max : hint_range(0.0, 1.0) = 0.40;

// Minimum number of dark opaque neighbors needed to classify the local area as hair.
uniform int hair_min_dark : hint_range(1, 12) = 3;

// 1.0 = full premultiply (white edge → near black). 0.0 = no effect.
uniform float darken_strength : hint_range(0.0, 1.0) = 1.0;

// A neighbor with alpha below this triggers "edge" classification.
uniform float edge_alpha_threshold : hint_range(0.0, 1.0) = 0.98;

const int RADIUS = 2;

void fragment() {
    vec4 src = texture(TEXTURE, UV);
    vec2 px = TEXTURE_PIXEL_SIZE;

    float min_neighbor_a = src.a;
    int dark_opaque = 0;

    for (int dy = -RADIUS; dy <= RADIUS; dy++) {
        for (int dx = -RADIUS; dx <= RADIUS; dx++) {
            if (dx == 0 && dy == 0) {
                continue;
            }
            vec4 n = texture(TEXTURE, UV + vec2(float(dx), float(dy)) * px);
            min_neighbor_a = min(min_neighbor_a, n.a);

            if (n.a > 0.98) {
                float brightest = max(max(n.r, n.g), n.b);
                if (brightest < hair_brightness_max) {
                    dark_opaque++;
                }
            }
        }
    }

    bool is_edge = min_neighbor_a < edge_alpha_threshold;
    bool is_hair_zone = dark_opaque >= hair_min_dark;

    if (is_edge && is_hair_zone) {
        float factor = mix(1.0, src.a, darken_strength);
        src.rgb *= factor;
    }

    COLOR = src;
}
