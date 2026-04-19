shader_type canvas_item;

// 좌→우 선형 그라데이션으로 채워지는 HP 바.
// fill_ratio 이하만 렌더되어 부드럽게 끊어지고, 그 위치까지만 그라데이션 보간된다.
// 배경(어두운 바닥 + 테두리)은 외곽 Panel + StyleBoxFlat 이 담당.

uniform vec4 fill_left  : source_color = vec4(0.82, 0.22, 0.24, 1.0);
uniform vec4 fill_right : source_color = vec4(1.0,  0.40, 0.40, 1.0);
uniform float fill_ratio : hint_range(0.0, 1.0) = 1.0;

void fragment() {
    if (UV.x > fill_ratio) {
        discard;
    }
    COLOR = mix(fill_left, fill_right, UV.x);
}
