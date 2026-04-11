shader_type canvas_item;

uniform float scroll_speed : hint_range(0.0, 2.0) = 0.25;
uniform float horizon : hint_range(0.0, 1.0) = 0.5;
uniform vec3 line_color : source_color = vec3(0.357, 0.753, 0.925);
uniform vec3 bg_top : source_color = vec3(0.05, 0.08, 0.14);
uniform vec3 bg_bot : source_color = vec3(0.01, 0.02, 0.06);
uniform float grid_size : hint_range(0.05, 1.0) = 0.4;
uniform float horizon_glow : hint_range(0.0, 2.0) = 0.7;
uniform float line_intensity : hint_range(0.0, 2.0) = 0.8;

float grid_line(float coord) {
    float d = abs(fract(coord - 0.5) - 0.5);
    float w = fwidth(coord) * 1.2;
    return 1.0 - smoothstep(0.0, w, d);
}

void fragment() {
    vec2 uv = UV;
    vec3 bg = mix(bg_top, bg_bot, uv.y);
    vec3 col = bg;

    if (uv.y > horizon) {
        float dy = uv.y - horizon;
        float depth = grid_size / (dy + 0.001);
        float z = depth - TIME * scroll_speed;
        float x_world = (uv.x - 0.5) * depth * 4.0;

        float line_z = grid_line(z / grid_size);
        float line_x = grid_line(x_world / grid_size);
        float grid = max(line_x, line_z);

        float fade_top = smoothstep(0.0, 0.06, dy);
        float fade_bot = 1.0 - smoothstep(0.82, 1.0, uv.y);
        float fade = fade_top * fade_bot;

        col += line_color * grid * line_intensity * fade;
    }

    float horizon_dist = abs(uv.y - horizon);
    float glow = exp(-horizon_dist * 35.0) * horizon_glow;
    col += line_color * glow;

    COLOR = vec4(col, 1.0);
}
