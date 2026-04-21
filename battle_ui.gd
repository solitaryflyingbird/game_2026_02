extends Control

# ============================================================
# battle_ui — mockup/목업.html 레이아웃의 Godot 이식.
#
# 단방향 흐름 유지:
#   - 상태 읽기: BattleManager.get_snapshot() + get_card_preview(idx)
#   - 명령: BattleManager.play_card(idx), BattleManager.end_turn()
#   - 상태 직접 수정 금지
#
# 시각 요소는 StyleBoxFlat + 라벨 + 기존 스프라이트로만 구성
# (카드/바/오브 등에는 PNG 텍스처 불필요).
# 에셋 참조:
#   - 배경: 배틀 리소스/배경/배경1.png
#   - 히로인 idle/attack 시퀀스
#   - 적: 배틀 리소스/예시 적/몬스터 예시.png
#   - 아이콘: 배틀 리소스/아이콘/적_공격_아이콘_레드.png, 방어 아이콘.png
# ============================================================


# --- 스테이지 · 레이아웃 상수 ---
const STAGE_W: int = 1280
const STAGE_H: int = 720
const HUD_H: int = 86
const CARD_W: int = 150
const CARD_H: int = 210

# --- 핸드 원호 배치 (mockup/hand_01_arc.html 기반) ---
const HAND_BASELINE_Y: int = 688          # 중앙 카드 하단 y좌표 (slot=0일 때)
const HAND_SLOT_SPACING: float = 130.0    # 슬롯 간 x 거리 (카드 폭과 거의 같아 살짝만 겹침)
const HAND_ROT_PER_SLOT_DEG: float = 3.6  # 슬롯 당 회전 각도 (°)
const HAND_Y_CURVE: float = 3.5           # 파라볼릭 y 내림 계수 (|slot|^2 * 계수)
const HAND_PIVOT_BELOW: float = 80.0      # 회전·확대 피벗: 카드 하단에서 더 아래
const HAND_HOVER_LIFT: float = 60.0       # 호버 시 추가 상승
const HAND_HOVER_SCALE: float = 1.35      # 호버 확대 배율
const HAND_TWEEN_TIME: float = 0.22       # 호버 트랜지션 시간

# --- 에셋 경로 ---
const BG_TEX_PATH := "res://에셋/배틀 리소스/배경/배경1.png"
const ENEMY_TEX_PATH := "res://에셋/배틀 리소스/예시 적/몬스터 예시.png"
const ATTACK_ICON_RED_PATH := "res://에셋/배틀 리소스/아이콘/적_공격_아이콘_레드.png"
const HEROINE_FRONT_DIR := "res://에셋/타이틀/"   # 프론트뷰 idle 8프레임 (타이틀 공용)

const HP_BAR_SHADER_PATH := "res://ui/hp_bar.gdshader"
const ORB_SHADER_PATH := "res://ui/orb.gdshader"

# --- 색상 팔레트 (목업.html 기반) ---
const COL_HUD_BG := Color(0.04, 0.06, 0.1, 0.85)
const COL_HUD_BORDER := Color(0.71, 0.78, 0.9, 0.25)
const COL_BAR_BG := Color(0.0, 0.0, 0.0, 0.7)

const COL_BODY_FILL_L := Color("c33a3c")      # 어두운 빨강 (바 좌측)
const COL_BODY_FILL_R := Color("ff6566")      # 밝은 빨강 (바 우측)
const COL_BODY_BORDER := Color(1.0, 0.39, 0.39, 0.55)
const COL_BODY_LBL := Color(0.75, 0.63, 0.63)

const COL_L_ACCENT := Color(0.42, 0.66, 1.0)
const COL_R_ACCENT := Color(1.0, 0.72, 0.42)

# 양팔 주황 바
const COL_ARM_FILL_L := Color("c88a3a")
const COL_ARM_FILL_R := Color("ffb86a")
const COL_ARM_BORDER := Color(1.0, 0.72, 0.42, 0.55)

# 블록 보조 바 (파랑)
const COL_BLOCK_FILL_L := Color("3a7dc8")
const COL_BLOCK_FILL_R := Color("6aa9ff")
const COL_BLOCK_BORDER := Color(0.42, 0.66, 1.0, 0.55)

const COL_ENEMY_FILL_L := Color("7a1a8a")
const COL_ENEMY_FILL_R := Color("c44cdd")
const COL_ENEMY_BORDER := Color(0.78, 0.39, 0.9, 0.55)
const COL_ENEMY_NAME := Color(1.0, 0.72, 0.91)
const COL_ENEMY_LEVEL := Color(0.69, 0.56, 0.78)
const COL_ENEMY_INTENT_TXT := Color(1.0, 0.86, 0.84)

# 오브 (마나, 카드 코스트) — 방사 그라데이션 + 흰 림
const COL_ORB_DEEP := Color("1e5a9a")
const COL_ORB_BRIGHT := Color("7ed1ff")
const COL_ORB_RIM := Color(1.0, 1.0, 1.0, 0.9)

const COL_ENERGY := Color(0.31, 0.62, 0.93)
const COL_ENERGY_MAX := Color(0.54, 0.71, 0.88)
const COL_TURN_LABEL := Color(1.0, 0.85, 0.54)
const COL_GOLD := Color(1.0, 0.85, 0.54)

const COL_CHIP_BG := Color(0.0, 0.0, 0.0, 0.45)
const COL_CHIP_BORDER := Color(0.55, 0.71, 0.9, 0.2)

const COL_ATK_BG := Color(0.26, 0.11, 0.16)
const COL_ATK_BORDER := Color(0.78, 0.31, 0.38)
const COL_DEF_BG := Color(0.1, 0.17, 0.24)
const COL_DEF_BORDER := Color(0.31, 0.51, 0.78)

const COL_CARD_ART_BG := Color(0.0, 0.0, 0.0, 0.4)
const COL_CARD_DMG := Color(1.0, 0.60, 0.56)
const COL_CARD_BLK := Color(0.55, 0.77, 1.0)
const COL_CARD_SELF := Color(0.82, 0.63, 0.69)

const COL_END_TURN_BG := Color(0.29, 0.23, 0.13)
const COL_END_TURN_BORDER := Color(0.79, 0.63, 0.38)
const COL_DECK_LBL := Color(0.66, 0.71, 0.78)


# ============================================================
# 노드 참조
# ============================================================

# 배경
var _bg: TextureRect

# 상단 HUD
var _hud_panel: Panel

var _body_hp_bar: Control
var _body_hp_num: Label

var _arm_l_bar: Control
var _arm_l_block_bar: Control
var _arm_l_hp_num: Label
var _arm_r_bar: Control
var _arm_r_block_bar: Control
var _arm_r_hp_num: Label

var _energy_label: Label
var _energy_max_label: Label
var _turn_number_label: Label

var _enemy_name_label: Label
var _enemy_level_label: Label
var _enemy_hp_bar: Control
var _enemy_hp_num: Label

# 적 의도 — 몬스터 상단에 떠있는 아이콘 + 숫자 (검은 외곽선)
var _intent_root: Control
var _intent_value_label: Label

var _deck_count_num: Label
var _discard_count_num: Label
var _hand_count_num: Label

# 캐릭터
var _heroine_sprite: AnimatedSprite2D
var _enemy_sprite: TextureRect

# 핸드 + 버튼
var _hand_root: Control
var _card_roots: Array = []

# 턴 종료 + 로그
var _end_turn_button: Button
var _log_label: Label


# ============================================================
# 초기화
# ============================================================

func _ready() -> void:
    # 전체 스테이지 기준 좌표 사용 (anchors_preset=0 유지)
    position = Vector2.ZERO
    size = Vector2(STAGE_W, STAGE_H)

    _build_bg()
    _build_hud()
    _build_heroine()
    _build_enemy()
    _build_intent()
    _build_hand_area()
    _build_end_turn()
    _build_log()
    _connect_signals()


# ------------------------------------------------------------
# 배경
# ------------------------------------------------------------

func _build_bg() -> void:
    _bg = TextureRect.new()
    _bg.position = Vector2.ZERO
    _bg.size = Vector2(STAGE_W, STAGE_H)
    _bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    _bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _bg.modulate = Color(0.62, 0.62, 0.62)   # brightness 0.6 approx
    var t: Texture2D = load(BG_TEX_PATH)
    if t != null:
        _bg.texture = t
    add_child(_bg)


# ------------------------------------------------------------
# HUD
# ------------------------------------------------------------

func _build_hud() -> void:
    _hud_panel = Panel.new()
    _hud_panel.position = Vector2.ZERO
    _hud_panel.size = Vector2(STAGE_W, HUD_H)
    _hud_panel.add_theme_stylebox_override("panel", _make_hud_style())
    add_child(_hud_panel)

    _build_hp_panel_hero()
    _build_hud_center()
    _build_hp_enemy()
    _build_hud_deck()


func _make_hud_style() -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = COL_HUD_BG
    s.border_width_bottom = 1
    s.border_color = COL_HUD_BORDER
    return s


# --- 좌: 히로인 HP 패널 ---
func _build_hp_panel_hero() -> void:
    var root := VBoxContainer.new()
    root.position = Vector2(26, 10)
    root.custom_minimum_size = Vector2(540, 66)
    root.add_theme_constant_override("separation", 6)
    _hud_panel.add_child(root)

    # 몸 라인
    var body_line := HBoxContainer.new()
    body_line.add_theme_constant_override("separation", 8)
    body_line.custom_minimum_size = Vector2(540, 16)
    root.add_child(body_line)

    var lbl_body := _make_label("몸", 10, COL_BODY_LBL)
    lbl_body.custom_minimum_size = Vector2(36, 14)
    lbl_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    body_line.add_child(lbl_body)

    _body_hp_bar = _make_gradient_bar(COL_BODY_FILL_L, COL_BODY_FILL_R, COL_BODY_BORDER, Vector2(410, 14))
    _body_hp_bar.size_flags_horizontal = 0
    body_line.add_child(_body_hp_bar)

    _body_hp_num = _make_label("0 / 0", 12, Color.WHITE)
    _body_hp_num.custom_minimum_size = Vector2(78, 14)
    _body_hp_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _body_hp_num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    body_line.add_child(_body_hp_num)

    # 팔 줄
    var arm_row := HBoxContainer.new()
    arm_row.add_theme_constant_override("separation", 10)
    arm_row.custom_minimum_size = Vector2(540, 40)
    root.add_child(arm_row)

    arm_row.add_child(_build_arm_chip("L"))
    arm_row.add_child(_build_arm_chip("R"))


func _build_arm_chip(side: String) -> Panel:
    var chip := Panel.new()
    chip.custom_minimum_size = Vector2(265, 38)
    chip.add_theme_stylebox_override(
        "panel", _make_panel_style(COL_CHIP_BG, COL_CHIP_BORDER, 2))

    var row := HBoxContainer.new()
    row.position = Vector2(8, 4)
    row.custom_minimum_size = Vector2(249, 30)
    row.add_theme_constant_override("separation", 6)
    chip.add_child(row)

    # L/R 라벨 (양팔 동일 주황 계열)
    var side_lbl := _make_label(side, 11, COL_R_ACCENT)
    side_lbl.custom_minimum_size = Vector2(14, 30)
    side_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(side_lbl)

    # 바 VBox: 주황 HP + (선택) 파란 블록
    var bar_box := VBoxContainer.new()
    bar_box.add_theme_constant_override("separation", 2)
    bar_box.custom_minimum_size = Vector2(155, 28)
    row.add_child(bar_box)

    var hp_bar := _make_gradient_bar(COL_ARM_FILL_L, COL_ARM_FILL_R, COL_ARM_BORDER, Vector2(155, 10))
    if side == "L":
        _arm_l_bar = hp_bar
    else:
        _arm_r_bar = hp_bar
    bar_box.add_child(hp_bar)

    var block_bar := _make_gradient_bar(COL_BLOCK_FILL_L, COL_BLOCK_FILL_R, COL_BLOCK_BORDER, Vector2(155, 5))
    block_bar.visible = false
    if side == "L":
        _arm_l_block_bar = block_bar
    else:
        _arm_r_block_bar = block_bar
    bar_box.add_child(block_bar)

    # HP 숫자
    var hp_num := _make_label("0 / 0", 11, Color.WHITE)
    hp_num.custom_minimum_size = Vector2(70, 30)
    hp_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    hp_num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    if side == "L":
        _arm_l_hp_num = hp_num
    else:
        _arm_r_hp_num = hp_num
    row.add_child(hp_num)

    return chip


# --- 중앙: 에너지 + 턴 ---
func _build_hud_center() -> void:
    var root := HBoxContainer.new()
    root.position = Vector2(594, 16)
    root.custom_minimum_size = Vector2(160, 56)
    root.add_theme_constant_override("separation", 18)
    root.alignment = BoxContainer.ALIGNMENT_CENTER
    _hud_panel.add_child(root)

    # 에너지
    var energy_wrap := HBoxContainer.new()
    energy_wrap.add_theme_constant_override("separation", 6)
    root.add_child(energy_wrap)

    var orb := _make_orb(Vector2(36, 36))
    # HBox 안에서 세로로 늘어나지 않도록 — 36×36 정방형 유지 → 정원
    orb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    orb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    energy_wrap.add_child(orb)

    _energy_label = _make_label("0", 16, Color.WHITE)
    _energy_label.position = Vector2(0, 0)
    _energy_label.size = Vector2(36, 36)
    _energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _energy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    orb.add_child(_energy_label)

    _energy_max_label = _make_label("/ 0", 12, COL_ENERGY_MAX)
    _energy_max_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _energy_max_label.custom_minimum_size = Vector2(0, 36)
    energy_wrap.add_child(_energy_max_label)

    # 턴
    var turn_block := VBoxContainer.new()
    turn_block.custom_minimum_size = Vector2(60, 36)
    turn_block.add_theme_constant_override("separation", 0)
    turn_block.alignment = BoxContainer.ALIGNMENT_CENTER
    root.add_child(turn_block)

    var turn_lbl := _make_label("TURN", 10, COL_TURN_LABEL)
    turn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    turn_block.add_child(turn_lbl)

    _turn_number_label = _make_label("0", 22, Color.WHITE)
    _turn_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    turn_block.add_child(_turn_number_label)


# --- 우: 적 HP 패널 ---
func _build_hp_enemy() -> void:
    var root := VBoxContainer.new()
    root.position = Vector2(782, 10)
    root.custom_minimum_size = Vector2(360, 66)
    root.add_theme_constant_override("separation", 4)
    _hud_panel.add_child(root)

    var head := HBoxContainer.new()
    head.add_theme_constant_override("separation", 8)
    head.custom_minimum_size = Vector2(360, 16)
    root.add_child(head)

    _enemy_name_label = _make_label("", 14, COL_ENEMY_NAME)
    _enemy_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _enemy_name_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
    head.add_child(_enemy_name_label)

    _enemy_level_label = _make_label("", 9, COL_ENEMY_LEVEL)
    _enemy_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _enemy_level_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
    _enemy_level_label.custom_minimum_size = Vector2(60, 16)
    head.add_child(_enemy_level_label)

    _enemy_hp_bar = _make_gradient_bar(COL_ENEMY_FILL_L, COL_ENEMY_FILL_R, COL_ENEMY_BORDER, Vector2(360, 14))
    root.add_child(_enemy_hp_bar)

    _enemy_hp_num = _make_label("HP 0 / 0", 12, Color.WHITE)
    _enemy_hp_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _enemy_hp_num.custom_minimum_size = Vector2(360, 22)
    root.add_child(_enemy_hp_num)


# --- 최우: 덱 카운트 ---
func _build_hud_deck() -> void:
    var root := VBoxContainer.new()
    root.position = Vector2(1160, 12)
    root.custom_minimum_size = Vector2(110, 60)
    root.add_theme_constant_override("separation", 2)
    _hud_panel.add_child(root)

    _deck_count_num = _make_deck_row("덱", root)
    _discard_count_num = _make_deck_row("버림", root)
    _hand_count_num = _make_deck_row("손", root)


func _make_deck_row(lbl_text: String, parent: Control) -> Label:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 4)
    parent.add_child(row)
    var lbl := _make_label(lbl_text, 11, COL_DECK_LBL)
    row.add_child(lbl)
    var num := _make_label("0", 13, Color.WHITE)
    row.add_child(num)
    return num


# ------------------------------------------------------------
# 캐릭터
# ------------------------------------------------------------

func _build_heroine() -> void:
    # 프론트뷰 — 타이틀과 동일 8프레임 idle 공유. 공격 전용 프레임은 미정이라
    # 공격 모션은 컷씬/피격 플래시로 대체 예정.
    _heroine_sprite = AnimatedSprite2D.new()
    var frames := SpriteFrames.new()

    frames.add_animation("idle")
    frames.set_animation_speed("idle", 8)
    frames.set_animation_loop("idle", true)
    for i in range(1, 9):  # 1.png ~ 8.png
        var f: Texture2D = load(HEROINE_FRONT_DIR + "%d.png" % i)
        if f != null:
            frames.add_frame("idle", f)

    _heroine_sprite.sprite_frames = frames
    _heroine_sprite.animation = "idle"
    _heroine_sprite.autoplay = "idle"
    # 에셋이 허벅지 윗부분에서 끊긴 초상화 → 그 끊긴 선이 스테이지 밖으로
    # 나가도록 scale 키우고 pos 내림. 결과: 에셋 하단이 y≈727(스테이지 720 아래)로
    # 화면에 보이지 않음. 얼굴은 원래 위치(≈246) 근처 유지.
    _heroine_sprite.scale = Vector2(0.45, 0.45)
    _heroine_sprite.position = Vector2(240, 441)
    _heroine_sprite.animation_finished.connect(_on_heroine_anim_finished)
    add_child(_heroine_sprite)


func _build_enemy() -> void:
    _enemy_sprite = TextureRect.new()
    _enemy_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _enemy_sprite.stretch_mode = TextureRect.STRETCH_SCALE
    _enemy_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var t: Texture2D = load(ENEMY_TEX_PATH)
    if t != null:
        _enemy_sprite.texture = t
        var tex_sz: Vector2 = t.get_size()
        var h: float = 600.0
        var w: float = tex_sz.x * (h / tex_sz.y)
        _enemy_sprite.size = Vector2(w, h)
        # 목업: right -40, bottom 40 (우측 40px 넘침)
        _enemy_sprite.position = Vector2(STAGE_W - w + 40, STAGE_H - 40 - h)
    add_child(_enemy_sprite)


# ------------------------------------------------------------
# 적 의도 — 슬더스 스타일 (몬스터 상단에 아이콘 + 숫자, 검은 외곽선)
# ------------------------------------------------------------

const INTENT_ICON_SIZE := Vector2(38, 38)
const INTENT_OUTLINE := 2

func _build_intent() -> void:
    var panel_w: int = 96
    var panel_h: int = 76

    _intent_root = Control.new()
    _intent_root.size = Vector2(panel_w, panel_h)
    _intent_root.custom_minimum_size = _intent_root.size
    _intent_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_intent_root)

    var atk_tex: Texture2D = load(ATTACK_ICON_RED_PATH)
    var icon := _make_outlined_icon(atk_tex, INTENT_ICON_SIZE, Color.BLACK, INTENT_OUTLINE)
    icon.position = Vector2((panel_w - icon.size.x) / 2.0, 0)
    _intent_root.add_child(icon)

    _intent_value_label = _make_outlined_label("0", 26, Color.WHITE, 2)
    _intent_value_label.position = Vector2(0, icon.size.y + 2)
    _intent_value_label.size = Vector2(panel_w, 30)
    _intent_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _intent_value_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    _intent_root.add_child(_intent_value_label)

    # 적 스프라이트 중앙 상단(HUD 바 아래 약간)에 위치
    var enemy_cx: float = float(STAGE_W - 200)
    var enemy_top: float = float(HUD_H + 10)
    if _enemy_sprite != null and _enemy_sprite.texture != null:
        enemy_cx = _enemy_sprite.position.x + _enemy_sprite.size.x / 2.0
        enemy_top = max(float(HUD_H + 6), _enemy_sprite.position.y + 8.0)
    _intent_root.position = Vector2(enemy_cx - panel_w / 2.0, enemy_top)


# ------------------------------------------------------------
# 핸드
# ------------------------------------------------------------

func _build_hand_area() -> void:
    # 원호 배치용 — 자식 카드는 절대 좌표 + 회전 + pivot 사용
    _hand_root = Control.new()
    _hand_root.position = Vector2.ZERO
    _hand_root.size = Vector2(STAGE_W, STAGE_H)
    _hand_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_hand_root)


# ------------------------------------------------------------
# 턴 종료
# ------------------------------------------------------------

func _build_end_turn() -> void:
    _end_turn_button = Button.new()
    _end_turn_button.text = "턴 종료"
    _end_turn_button.custom_minimum_size = Vector2(140, 44)
    _end_turn_button.position = Vector2(STAGE_W - 30 - 140, STAGE_H - 90 - 44)
    _end_turn_button.add_theme_font_size_override("font_size", 14)
    _end_turn_button.add_theme_color_override("font_color", COL_GOLD)
    _end_turn_button.add_theme_color_override("font_hover_color", COL_GOLD)
    _end_turn_button.add_theme_color_override("font_pressed_color", COL_GOLD)
    _end_turn_button.focus_mode = Control.FOCUS_NONE

    var normal := _make_panel_style(COL_END_TURN_BG, COL_END_TURN_BORDER, 4, 2)
    var hover := normal.duplicate() as StyleBoxFlat
    hover.bg_color = COL_END_TURN_BG.lightened(0.12)
    _end_turn_button.add_theme_stylebox_override("normal", normal)
    _end_turn_button.add_theme_stylebox_override("hover", hover)
    _end_turn_button.add_theme_stylebox_override("pressed", normal)
    _end_turn_button.add_theme_stylebox_override("disabled", normal)
    _end_turn_button.pressed.connect(_on_end_turn_pressed)
    add_child(_end_turn_button)


func _build_log() -> void:
    _log_label = Label.new()
    _log_label.position = Vector2(260, 498)
    _log_label.size = Vector2(760, 24)
    _log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _log_label.add_theme_font_size_override("font_size", 13)
    _log_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
    _log_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
    _log_label.add_theme_constant_override("shadow_offset_x", 1)
    _log_label.add_theme_constant_override("shadow_offset_y", 1)
    _log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_log_label)


# ============================================================
# 시그널 구독 · 핸들러
# ============================================================

func _connect_signals() -> void:
    BattleManager.state_changed.connect(_on_battle_state_changed)
    BattleManager.damage_dealt.connect(_on_damage_dealt)
    BattleManager.block_added.connect(_on_block_added)
    BattleManager.block_absorbed.connect(_on_block_absorbed)
    BattleManager.body_damaged.connect(_on_body_damaged)
    BattleManager.arm_self_damaged.connect(_on_arm_self_damaged)
    BattleManager.arm_destroyed.connect(_on_arm_destroyed)
    BattleManager.battle_ended.connect(_on_battle_ended)
    BattleManager.play_failed.connect(_on_play_failed)


func begin_combat() -> void:
    _log_label.text = ""
    _end_turn_button.disabled = false
    _refresh_from_snapshot()


func _on_battle_state_changed() -> void:
    _refresh_from_snapshot()


func _on_damage_dealt(amount: int) -> void:
    # 프론트뷰 전환 후 공격 전용 프레임 없음 — 컷씬/피격 플래시로 대체 예정
    if _heroine_sprite.sprite_frames != null \
            and _heroine_sprite.sprite_frames.has_animation("attack"):
        _heroine_sprite.play("attack")
    _append_log("적에게 %d 데미지" % amount)


func _on_block_added(side: String, amount: int) -> void:
    _append_log("%s 블록 +%d" % [_side_kor(side), amount])


func _on_block_absorbed(side: String, amount: int) -> void:
    _append_log("%s 블록이 %d 흡수" % [_side_kor(side), amount])


func _on_body_damaged(amount: int) -> void:
    _append_log("몸 피해 %d" % amount)


func _on_arm_self_damaged(side: String, amount: int) -> void:
    _append_log("%s 반동 -%d" % [_side_kor(side), amount])


func _on_arm_destroyed(side: String) -> void:
    _append_log("%s 파괴됨" % _side_kor(side))


func _on_battle_ended(result: Dictionary) -> void:
    _end_turn_button.disabled = true
    for root in _card_roots:
        root.disabled = true
    _append_log("전투 종료 — %s" % ("승리" if result.get("result") == "victory" else "패배"))


func _on_play_failed(reason: String) -> void:
    match reason:
        "energy_insufficient":
            _append_log("에너지 부족")
        _:
            _append_log("사용 불가 (%s)" % reason)


func _on_heroine_anim_finished() -> void:
    _heroine_sprite.play("idle")


func _on_end_turn_pressed() -> void:
    BattleManager.end_turn()


func _on_card_pressed(idx: int) -> void:
    BattleManager.play_card(idx)


# ============================================================
# 스냅샷 → 화면
# ============================================================

func _refresh_from_snapshot() -> void:
    var snap: Dictionary = BattleManager.get_snapshot()
    if snap.is_empty():
        return
    _refresh_hud(snap)
    _refresh_hand(snap)


func _refresh_hud(snap: Dictionary) -> void:
    _set_bar_value(_body_hp_bar, snap.body_hp, snap.body_max_hp)
    _body_hp_num.text = "%d / %d" % [snap.body_hp, snap.body_max_hp]

    _refresh_arm("L", snap.arm_l_hp, snap.arm_l_max_hp, snap.arm_l_alive, snap.block_l)
    _refresh_arm("R", snap.arm_r_hp, snap.arm_r_max_hp, snap.arm_r_alive, snap.block_r)

    _energy_label.text = "%d" % snap.energy
    var max_energy: int = GameData.BATTLE_RULES.energy_per_arm * 2
    _energy_max_label.text = "/ %d" % max_energy
    _turn_number_label.text = "%d" % snap.turn

    _enemy_name_label.text = snap.enemy_name
    _enemy_level_label.text = ""   # TODO: 노드/층 정보 연결
    _set_bar_value(_enemy_hp_bar, snap.enemy_hp, snap.enemy_max_hp)
    _enemy_hp_num.text = "HP %d / %d" % [snap.enemy_hp, snap.enemy_max_hp]

    # 적 의도 — 몬스터 상단의 외곽선 아이콘 + 숫자
    if snap.enemy_hp > 0:
        _intent_root.visible = true
        _intent_value_label.text = "%d" % snap.next_intent
    else:
        _intent_root.visible = false

    _deck_count_num.text = "%d" % snap.deck_size
    _discard_count_num.text = "%d" % snap.discard_size
    _hand_count_num.text = "%d" % snap.hand_size


func _refresh_arm(side: String, hp: int, max_hp: int, alive: bool, block: int) -> void:
    var bar: Control = _arm_l_bar if side == "L" else _arm_r_bar
    var num: Label = _arm_l_hp_num if side == "L" else _arm_r_hp_num
    var blk_bar: Control = _arm_l_block_bar if side == "L" else _arm_r_block_bar

    _set_bar_value(bar, hp, max_hp)
    if max_hp == 0:
        num.text = "(빈)"
    elif alive:
        num.text = "%d / %d" % [hp, max_hp]
    else:
        num.text = "파괴"

    # 블록 보조 바 (파란색) — 팔 max_hp 기준 스케일
    if block > 0 and max_hp > 0:
        blk_bar.visible = true
        _set_bar_value(blk_bar, min(block, max_hp), max_hp)
    else:
        blk_bar.visible = false


func _refresh_hand(snap: Dictionary) -> void:
    for root in _card_roots:
        root.queue_free()
    _card_roots.clear()

    var hand: Array = snap.hand
    var n: int = hand.size()
    if n == 0:
        return

    var center_idx: float = float(n - 1) / 2.0
    var hand_cx: float = float(STAGE_W) / 2.0

    # 히트 영역 Button용 빈 스타일 (Button 기본 렌더를 비활성화)
    var empty_style := StyleBoxEmpty.new()

    for i in range(n):
        var inst: Dictionary = hand[i]

        # 슬롯 오프셋 계산
        var slot: float = float(i) - center_idx
        var base_x: float = hand_cx - float(CARD_W) / 2.0 + slot * HAND_SLOT_SPACING
        var base_y: float = float(HAND_BASELINE_Y) - float(CARD_H) + slot * slot * HAND_Y_CURVE
        var base_rot: float = deg_to_rad(slot * HAND_ROT_PER_SLOT_DEG)
        var base_z: int = i + 1

        # === 히트 영역 (Button) — 기본 위치/회전 고정. 호버 시 변형하지 않음.
        #     덕분에 비주얼이 확대/이동해도 mouse_exited 가 튀지 않는다.
        var hit_area := Button.new()
        hit_area.custom_minimum_size = Vector2(CARD_W, CARD_H)
        hit_area.size = Vector2(CARD_W, CARD_H)
        hit_area.focus_mode = Control.FOCUS_NONE
        hit_area.flat = true
        hit_area.clip_contents = false
        hit_area.add_theme_stylebox_override("normal", empty_style)
        hit_area.add_theme_stylebox_override("hover", empty_style)
        hit_area.add_theme_stylebox_override("pressed", empty_style)
        hit_area.add_theme_stylebox_override("disabled", empty_style)
        hit_area.add_theme_stylebox_override("focus", empty_style)

        hit_area.pivot_offset = Vector2(float(CARD_W) / 2.0, float(CARD_H) + HAND_PIVOT_BELOW)
        hit_area.position = Vector2(base_x, base_y)
        hit_area.rotation = base_rot
        hit_area.z_index = base_z
        hit_area.set_meta("base_z", base_z)

        # === 비주얼 (Panel, hit_area 의 자식) — 호버 시 scale/rotate/translate 애니메이션
        var visual: Panel = _make_card_view(i, inst, snap.energy)
        visual.pivot_offset = Vector2(float(CARD_W) / 2.0, float(CARD_H) + HAND_PIVOT_BELOW)
        visual.position = Vector2.ZERO
        visual.rotation = 0.0
        visual.scale = Vector2.ONE
        hit_area.add_child(visual)

        # 카드 disabled (에너지 부족) — hit_area 단에서 처리. 비주얼은 modulate 로 표시.
        var card_def: Dictionary = GameData.CARD_TEMPLATES[inst.card_id]
        hit_area.disabled = card_def.cost > snap.energy

        # 시그널
        hit_area.mouse_entered.connect(_on_card_hover_enter.bind(hit_area, visual, base_rot))
        hit_area.mouse_exited.connect(_on_card_hover_exit.bind(hit_area, visual))
        hit_area.pressed.connect(_on_card_pressed.bind(i))

        _hand_root.add_child(hit_area)
        _card_roots.append(hit_area)


func _on_card_hover_enter(hit_area: Button, visual: Control, base_rot: float) -> void:
    if not is_instance_valid(visual) or not is_instance_valid(hit_area):
        return
    hit_area.z_index = 100
    _kill_card_tween(visual)
    # visual 의 rotation = -base_rot 는 부모(hit_area) 의 회전을 상쇄 → 화면상 직립.
    var tween := create_tween().set_parallel(true)
    tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tween.tween_property(visual, "rotation", -base_rot, HAND_TWEEN_TIME)
    tween.tween_property(visual, "scale", Vector2(HAND_HOVER_SCALE, HAND_HOVER_SCALE), HAND_TWEEN_TIME)
    tween.tween_property(visual, "position", Vector2(0, -HAND_HOVER_LIFT), HAND_TWEEN_TIME)
    tween.tween_property(visual, "modulate:a", 1.0, HAND_TWEEN_TIME)
    visual.set_meta("tween", tween)


func _on_card_hover_exit(hit_area: Button, visual: Control) -> void:
    if not is_instance_valid(visual) or not is_instance_valid(hit_area):
        return
    hit_area.z_index = hit_area.get_meta("base_z")
    _kill_card_tween(visual)
    var base_alpha: float = visual.get_meta("base_alpha", 0.88)
    var tween := create_tween().set_parallel(true)
    tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tween.tween_property(visual, "rotation", 0.0, HAND_TWEEN_TIME)
    tween.tween_property(visual, "scale", Vector2.ONE, HAND_TWEEN_TIME)
    tween.tween_property(visual, "position", Vector2.ZERO, HAND_TWEEN_TIME)
    tween.tween_property(visual, "modulate:a", base_alpha, HAND_TWEEN_TIME)
    visual.set_meta("tween", tween)


func _kill_card_tween(visual: Control) -> void:
    if not visual.has_meta("tween"):
        return
    var old = visual.get_meta("tween")
    if old != null and old is Tween and old.is_valid():
        old.kill()


func _make_card_view(idx: int, card_inst: Dictionary, energy: int) -> Panel:
    # 비주얼 레이어만 만듦 — 클릭/호버는 부모(hit_area Button)가 담당.
    # 이 함수가 반환하는 Panel 은 mouse_filter IGNORE 이며, 호버 시 scale/rotate/translate 된다.
    var card_def: Dictionary = GameData.CARD_TEMPLATES[card_inst.card_id]
    var preview: Dictionary = BattleManager.get_card_preview(idx)
    var category: String = card_def.get("category", "attack")
    var side: String = card_inst.arm_side
    var affordable: bool = card_def.cost <= energy

    var visual := Panel.new()
    visual.custom_minimum_size = Vector2(CARD_W, CARD_H)
    visual.size = Vector2(CARD_W, CARD_H)
    visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
    visual.clip_contents = false

    var bg_col := COL_ATK_BG if category == "attack" else COL_DEF_BG
    var border_col := COL_ATK_BORDER if category == "attack" else COL_DEF_BORDER
    visual.add_theme_stylebox_override("panel", _make_panel_style(bg_col, border_col, 10, 2))

    # 기본 반투명 (호버 시 불투명으로 트윈).
    # 사용 불가(에너지 부족)일 땐 더 어둡게.
    var base_alpha: float = 0.55 if not affordable else 0.88
    visual.modulate = Color(1, 1, 1, base_alpha)
    visual.set_meta("base_alpha", base_alpha)

    # 코스트 구슬 (좌상단 외측, 36×36 원 — HUD 마나 오브와 동일 쉐이더)
    var orb := _make_orb(Vector2(36, 36))
    orb.position = Vector2(-10, -10)
    visual.add_child(orb)

    var cost_lbl := _make_label("%d" % card_def.cost, 16, Color.WHITE)
    cost_lbl.position = Vector2(0, 0)
    cost_lbl.size = Vector2(36, 36)
    cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    cost_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
    orb.add_child(cost_lbl)

    # 슬롯 뱃지 (우상단)
    var slot_col := Color(0.47, 0.71, 1.0) if side == "L" else Color(1.0, 0.55, 0.47)
    var slot_lbl := _make_label(side, 15, slot_col)
    slot_lbl.position = Vector2(CARD_W - 24, 6)
    slot_lbl.size = Vector2(18, 20)
    slot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    slot_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
    visual.add_child(slot_lbl)

    # 이름
    var name_lbl := _make_label(card_def.name, 15, Color.WHITE)
    name_lbl.position = Vector2(10, 32)
    name_lbl.size = Vector2(CARD_W - 20, 22)
    name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
    visual.add_child(name_lbl)

    # 아트 플레이스홀더
    var art := Panel.new()
    art.position = Vector2(10, 62)
    art.size = Vector2(CARD_W - 20, 102)
    art.mouse_filter = Control.MOUSE_FILTER_IGNORE
    art.add_theme_stylebox_override(
        "panel", _make_panel_style(COL_CARD_ART_BG, Color.TRANSPARENT, 4))
    visual.add_child(art)

    var art_lbl := _make_label("art", 11, Color(1, 1, 1, 0.28))
    art_lbl.position = Vector2(0, 0)
    art_lbl.size = art.size
    art_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    art_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    art_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
    art.add_child(art_lbl)

    # 효과 텍스트
    var eff_box := VBoxContainer.new()
    eff_box.position = Vector2(10, 170)
    eff_box.size = Vector2(CARD_W - 20, 38)
    eff_box.add_theme_constant_override("separation", 1)
    eff_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    visual.add_child(eff_box)

    var p_effects: Array = preview.get("effects", [])
    for eff in p_effects:
        var t: String = eff.type
        var v: int = eff.final_value
        var txt: String = ""
        var col: Color = Color.WHITE
        var fs: int = 11
        match t:
            "deal_damage":
                txt = "데미지 %d" % v
                col = COL_CARD_DMG
            "transfer_block":
                txt = "블록 %d" % v
                col = COL_CARD_BLK
            "damage_own_arm":
                txt = "반동 -%d" % v
                col = COL_CARD_SELF
                fs = 10
        if txt == "":
            continue
        var lbl := _make_label(txt, fs, col)
        lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
        eff_box.add_child(lbl)

    return visual


# ============================================================
# 공용 유틸
# ============================================================

func _make_label(text: String, fs: int, col: Color) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", fs)
    l.add_theme_color_override("font_color", col)
    return l


func _make_outlined_label(text: String, fs: int, col: Color, outline: int = 2) -> Label:
    var l := _make_label(text, fs, col)
    l.add_theme_color_override("font_outline_color", Color.BLACK)
    l.add_theme_constant_override("outline_size", outline)
    return l


# 8방향 오프셋 복제 + 본체 레이어링으로 외곽선 효과 (쉐이더 없이)
func _make_outlined_icon(tex: Texture2D, icon_size: Vector2, outline_color: Color, outline_w: int = 2) -> Control:
    var total := icon_size + Vector2(outline_w * 2, outline_w * 2)
    var root := Control.new()
    root.custom_minimum_size = total
    root.size = total
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if tex == null:
        return root

    var offsets := [
        Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1),
        Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1),
    ]
    for o in offsets:
        var sh := TextureRect.new()
        sh.texture = tex
        sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        sh.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        sh.size = icon_size
        sh.position = Vector2(outline_w, outline_w) + o * outline_w
        sh.modulate = outline_color
        sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
        root.add_child(sh)

    var real := TextureRect.new()
    real.texture = tex
    real.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    real.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    real.size = icon_size
    real.position = Vector2(outline_w, outline_w)
    real.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(real)
    return root


func _make_gradient_bar(fill_l: Color, fill_r: Color, border: Color, bar_size: Vector2) -> Control:
    # Control 루트 + 배경 Panel(테두리/어두운 바닥) + 전경 ColorRect(쉐이더 그라데이션).
    # _set_bar_value 로 fill_ratio 만 갱신.
    var root := Control.new()
    root.custom_minimum_size = bar_size
    root.size = bar_size
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var bg := Panel.new()
    bg.position = Vector2.ZERO
    bg.size = bar_size
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    bg.add_theme_stylebox_override("panel", _make_panel_style(COL_BAR_BG, border, 2, 1))
    root.add_child(bg)

    var fill := ColorRect.new()
    fill.position = Vector2.ZERO
    fill.size = bar_size
    fill.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var mat := ShaderMaterial.new()
    mat.shader = load(HP_BAR_SHADER_PATH)
    mat.set_shader_parameter("fill_left", fill_l)
    mat.set_shader_parameter("fill_right", fill_r)
    mat.set_shader_parameter("fill_ratio", 1.0)
    fill.material = mat

    root.add_child(fill)
    root.set_meta("fill_rect", fill)
    return root


func _set_bar_value(bar: Control, value: int, max_value: int) -> void:
    if not bar.has_meta("fill_rect"):
        return
    var ratio: float = 0.0
    if max_value > 0:
        ratio = clamp(float(value) / float(max_value), 0.0, 1.0)
    var fill: ColorRect = bar.get_meta("fill_rect")
    (fill.material as ShaderMaterial).set_shader_parameter("fill_ratio", ratio)


func _make_orb(orb_size: Vector2) -> ColorRect:
    # 방사 그라데이션 + 흰 림 구슬. 크기는 자유롭게, 원형 영역 외는 투명.
    var rect := ColorRect.new()
    rect.custom_minimum_size = orb_size
    rect.size = orb_size
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var mat := ShaderMaterial.new()
    mat.shader = load(ORB_SHADER_PATH)
    mat.set_shader_parameter("bright_color", COL_ORB_BRIGHT)
    mat.set_shader_parameter("deep_color", COL_ORB_DEEP)
    mat.set_shader_parameter("rim_color", COL_ORB_RIM)
    mat.set_shader_parameter("rim_width", 0.08)
    mat.set_shader_parameter("highlight_offset", Vector2(-0.15, -0.15))
    mat.set_shader_parameter("gradient_spread", 1.2)
    rect.material = mat
    return rect


func _make_panel_style(bg: Color, border: Color, radius: int = 2, border_width: int = 1) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = bg
    if border.a > 0.0:
        s.border_width_left = border_width
        s.border_width_right = border_width
        s.border_width_top = border_width
        s.border_width_bottom = border_width
        s.border_color = border
    if radius > 0:
        s.corner_radius_top_left = radius
        s.corner_radius_top_right = radius
        s.corner_radius_bottom_left = radius
        s.corner_radius_bottom_right = radius
    return s


func _append_log(msg: String) -> void:
    _log_label.text = msg


func _side_kor(side: String) -> String:
    return "좌팔" if side == "L" else "우팔"
