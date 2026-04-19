shader_type canvas_item;

// 원형 구슬 (마나 구슬, 카드 코스트 구슬 공용).
// 좌상단 쪽 하이라이트 → 외곽 어두운 심도의 부드러운 방사 그라데이션 +
// 외곽 얇은 흰 림(림 두께는 rim_width 로 조정).
// 원 바깥은 discard 로 투명.

uniform vec4 bright_color : source_color = vec4(0.50, 0.82, 1.00, 1.0);
uniform vec4 deep_color   : source_color = vec4(0.12, 0.35, 0.60, 1.0);
uniform vec4 rim_color    : source_color = vec4(1.0, 1.0, 1.0, 0.9);

uniform float rim_width       : hint_range(0.0, 0.25) = 0.08;
uniform vec2  highlight_offset = vec2(-0.15, -0.15);
uniform float gradient_spread  : hint_range(0.2, 2.0) = 1.2;

void fragment() {
    vec2 uv = UV - 0.5;
    float dist = length(uv) * 2.0;  // 0(중심) ~ 1(원 가장자리)

    // fwidth = 인접 픽셀 간 dist 변화량 → 픽셀 한 개 폭 = aa.
    // 이걸 AA 밴드 반폭으로 쓰면 구슬 크기/배율과 무관하게 1~2px AA 보장.
    float aa = fwidth(dist);

    // 원 바깥 먼 영역은 바로 버림 (최적화)
    if (dist > 1.0 + aa * 2.0) {
        discard;
    }

    // 하이라이트 쪽에서 먼 지점일수록 어두워지는 방사 그라데이션
    float hl_dist = length(uv - highlight_offset) * 2.0;
    float t = smoothstep(0.0, gradient_spread, hl_dist);
    vec4 body = mix(bright_color, deep_color, t);

    // 림: body↔rim 전이도 픽셀 폭만큼 부드럽게 (작은 구슬에서도 안티앨리어스)
    float rim_inner = 1.0 - rim_width;
    float rim_mid   = 1.0 - rim_width * 0.35;
    float rim_t = smoothstep(rim_inner - aa, rim_mid + aa, dist);
    vec4 col = mix(body, rim_color, rim_t);

    // 외곽 AA — 원 가장자리 ±1픽셀 폭에서 알파 페이드
    col.a *= 1.0 - smoothstep(1.0 - aa, 1.0 + aa, dist);
    COLOR = col;
}
