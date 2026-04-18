extends Control

# ============================================================
# battle_ui — BattleManager.get_snapshot() 을 렌더하고
#             BattleManager.play_card / end_turn 으로 명령을 보낸다.
#
# 단방향 흐름:
#   - 상태 읽기: BattleManager.get_snapshot() + get_card_preview()
#   - 명령: play_card(idx), end_turn()
#   - 시그널 구독으로 애니메이션 · 로그 · 종료 처리
#   - 상태 직접 수정 금지
# ============================================================


# --- UI 노드 ---
var _bg: TextureRect
var _hud_panel: Panel
var _body_hp_bar: ProgressBar
var _body_hp_label: Label
var _energy_label: Label
var _turn_label: Label
var _deck_label: Label

var _player_sprite: AnimatedSprite2D
var _arm_l_hp_bar: ProgressBar
var _arm_l_hp_label: Label
var _arm_l_block_label: Label
var _arm_r_hp_bar: ProgressBar
var _arm_r_hp_label: Label
var _arm_r_block_label: Label

var _enemy_sprite: TextureRect
var _enemy_name_label: Label
var _enemy_hp_bar: ProgressBar
var _enemy_hp_label: Label
var _enemy_intent_label: Label

var _hand_container: HBoxContainer
var _card_buttons: Array = []

var _end_turn_button: Button
var _log_label: Label

# 적 스프라이트 후보 (MVP: 고정 텍스처 사용)
var _enemy_textures: Array = []

# --- 상수 ---
const CARD_SIZE: Vector2 = Vector2(132, 168)
const CARD_COLOR_L: Color = Color(0.55, 0.75, 1.0, 1.0)   # 좌팔 = 푸른빛
const CARD_COLOR_R: Color = Color(1.0, 0.65, 0.55, 1.0)   # 우팔 = 붉은빛


# ============================================================
# 초기화
# ============================================================

func _ready() -> void:
    _build_ui()
    _connect_signals()


func _build_ui() -> void:
    _build_bg()
    _build_hud()
    _build_player_area()
    _build_enemy_area()
    _build_hand_area()
    _build_end_turn()
    _build_log()


func _build_bg() -> void:
    _bg = TextureRect.new()
    _bg.position = Vector2(0, 0)
    _bg.size = Vector2(1280, 720)
    _bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    _bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var tex: Texture2D = load("res://에셋/배틀 리소스/배경/배경1.png")
    if tex != null:
        _bg.texture = tex
    add_child(_bg)


func _build_hud() -> void:
    _hud_panel = Panel.new()
    _hud_panel.position = Vector2(0, 0)
    _hud_panel.size = Vector2(1280, 56)
    add_child(_hud_panel)

    _body_hp_bar = ProgressBar.new()
    _body_hp_bar.position = Vector2(20, 14)
    _body_hp_bar.size = Vector2(300, 28)
    _body_hp_bar.max_value = 150
    _body_hp_bar.show_percentage = false
    _hud_panel.add_child(_body_hp_bar)

    _body_hp_label = Label.new()
    _body_hp_label.position = Vector2(24, 16)
    _body_hp_label.size = Vector2(292, 28)
    _body_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _body_hp_label.add_theme_font_size_override("font_size", 14)
    _hud_panel.add_child(_body_hp_label)

    _energy_label = Label.new()
    _energy_label.position = Vector2(340, 16)
    _energy_label.size = Vector2(140, 28)
    _energy_label.add_theme_font_size_override("font_size", 16)
    _hud_panel.add_child(_energy_label)

    _turn_label = Label.new()
    _turn_label.position = Vector2(580, 16)
    _turn_label.size = Vector2(120, 28)
    _turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _turn_label.add_theme_font_size_override("font_size", 14)
    _hud_panel.add_child(_turn_label)

    _deck_label = Label.new()
    _deck_label.position = Vector2(940, 16)
    _deck_label.size = Vector2(320, 28)
    _deck_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _deck_label.add_theme_font_size_override("font_size", 13)
    _hud_panel.add_child(_deck_label)


func _build_player_area() -> void:
    # 주인공 스프라이트 (idle 루프 + attack 1회)
    _player_sprite = AnimatedSprite2D.new()
    var frames := SpriteFrames.new()

    frames.add_animation("idle")
    frames.set_animation_speed("idle", 4)
    frames.set_animation_loop("idle", true)
    for i in range(4):
        var f: Texture2D = load("res://에셋/배틀 리소스/주인공/idle/frame_%d.png" % i)
        if f != null:
            frames.add_frame("idle", f)

    frames.add_animation("attack")
    frames.set_animation_speed("attack", 10)
    frames.set_animation_loop("attack", false)
    for i in range(5):
        var f: Texture2D = load("res://에셋/배틀 리소스/주인공/공격모션/frame_%d.png" % i)
        if f != null:
            frames.add_frame("attack", f)

    _player_sprite.sprite_frames = frames
    _player_sprite.animation = "idle"
    _player_sprite.autoplay = "idle"
    _player_sprite.position = Vector2(220, 280)
    _player_sprite.scale = Vector2(0.42, 0.42)
    _player_sprite.animation_finished.connect(_on_player_anim_finished)
    add_child(_player_sprite)

    # 양팔 HP + 블록 패널
    _make_arm_panel("L", Vector2(60, 400))
    _make_arm_panel("R", Vector2(240, 400))


func _make_arm_panel(side: String, pos: Vector2) -> void:
    var c := VBoxContainer.new()
    c.position = pos
    c.size = Vector2(160, 100)
    c.add_theme_constant_override("separation", 3)

    var title := Label.new()
    title.text = ("좌팔" if side == "L" else "우팔")
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 13)
    c.add_child(title)

    var hp_bar := ProgressBar.new()
    hp_bar.custom_minimum_size = Vector2(150, 14)
    hp_bar.max_value = 120
    hp_bar.show_percentage = false
    c.add_child(hp_bar)

    var hp_label := Label.new()
    hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hp_label.add_theme_font_size_override("font_size", 12)
    c.add_child(hp_label)

    var block_label := Label.new()
    block_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    block_label.add_theme_font_size_override("font_size", 12)
    c.add_child(block_label)

    if side == "L":
        _arm_l_hp_bar = hp_bar
        _arm_l_hp_label = hp_label
        _arm_l_block_label = block_label
    else:
        _arm_r_hp_bar = hp_bar
        _arm_r_hp_label = hp_label
        _arm_r_block_label = block_label

    add_child(c)


func _build_enemy_area() -> void:
    _enemy_textures = [
        load("res://에셋/배틀 리소스/예시 적/1.png"),
        load("res://에셋/배틀 리소스/예시 적/2.png"),
    ]

    _enemy_name_label = Label.new()
    _enemy_name_label.position = Vector2(860, 140)
    _enemy_name_label.size = Vector2(280, 28)
    _enemy_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _enemy_name_label.add_theme_font_size_override("font_size", 16)
    add_child(_enemy_name_label)

    _enemy_sprite = TextureRect.new()
    _enemy_sprite.position = Vector2(860, 175)
    _enemy_sprite.size = Vector2(280, 200)
    _enemy_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _enemy_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    if _enemy_textures.size() > 0 and _enemy_textures[0] != null:
        _enemy_sprite.texture = _enemy_textures[0]
    add_child(_enemy_sprite)

    _enemy_hp_bar = ProgressBar.new()
    _enemy_hp_bar.position = Vector2(860, 390)
    _enemy_hp_bar.size = Vector2(280, 18)
    _enemy_hp_bar.show_percentage = false
    add_child(_enemy_hp_bar)

    _enemy_hp_label = Label.new()
    _enemy_hp_label.position = Vector2(860, 390)
    _enemy_hp_label.size = Vector2(280, 18)
    _enemy_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _enemy_hp_label.add_theme_font_size_override("font_size", 12)
    add_child(_enemy_hp_label)

    _enemy_intent_label = Label.new()
    _enemy_intent_label.position = Vector2(860, 418)
    _enemy_intent_label.size = Vector2(280, 24)
    _enemy_intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _enemy_intent_label.add_theme_font_size_override("font_size", 14)
    add_child(_enemy_intent_label)


func _build_hand_area() -> void:
    _hand_container = HBoxContainer.new()
    _hand_container.position = Vector2(140, 540)
    _hand_container.add_theme_constant_override("separation", 10)
    add_child(_hand_container)


func _build_end_turn() -> void:
    _end_turn_button = Button.new()
    _end_turn_button.text = "턴 종료"
    _end_turn_button.position = Vector2(1100, 485)
    _end_turn_button.custom_minimum_size = Vector2(140, 48)
    _end_turn_button.pressed.connect(_on_end_turn_pressed)
    add_child(_end_turn_button)


func _build_log() -> void:
    _log_label = Label.new()
    _log_label.position = Vector2(300, 490)
    _log_label.size = Vector2(760, 40)
    _log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _log_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _log_label.add_theme_font_size_override("font_size", 14)
    add_child(_log_label)


# ============================================================
# BattleManager 시그널 구독
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


# ============================================================
# run_ui 에서 호출 (phase "combat" 진입 시)
# ============================================================

func begin_combat() -> void:
    _log_label.text = ""
    _end_turn_button.disabled = false
    _refresh_from_snapshot()


# ============================================================
# 시그널 핸들러
# ============================================================

func _on_battle_state_changed() -> void:
    _refresh_from_snapshot()


func _on_damage_dealt(amount: int) -> void:
    _player_sprite.play("attack")
    _append_log("적에게 %d 피해" % amount)


func _on_block_added(side: String, amount: int) -> void:
    _append_log("%s 블록 +%d" % [_side_kor(side), amount])


func _on_block_absorbed(side: String, amount: int) -> void:
    _append_log("%s 블록이 피해 %d 흡수" % [_side_kor(side), amount])


func _on_body_damaged(amount: int) -> void:
    _append_log("몸 피해 %d" % amount)


func _on_arm_self_damaged(side: String, amount: int) -> void:
    _append_log("%s 자해 -%d" % [_side_kor(side), amount])


func _on_arm_destroyed(side: String) -> void:
    _append_log("%s 파괴됨" % _side_kor(side))


func _on_battle_ended(result: String) -> void:
    _end_turn_button.disabled = true
    for btn in _card_buttons:
        btn.disabled = true
    var msg: String = ("승리" if result == "victory" else "패배")
    _append_log("전투 종료 — %s" % msg)


func _on_play_failed(reason: String) -> void:
    match reason:
        "energy_insufficient":
            _append_log("에너지 부족")
        _:
            _append_log("사용 불가 (%s)" % reason)


func _on_player_anim_finished() -> void:
    _player_sprite.play("idle")


# ============================================================
# 입력 핸들러
# ============================================================

func _on_end_turn_pressed() -> void:
    BattleManager.end_turn()


func _on_card_pressed(hand_idx: int) -> void:
    BattleManager.play_card(hand_idx)


# ============================================================
# 스냅샷 → 화면
# ============================================================

func _refresh_from_snapshot() -> void:
    var snap: Dictionary = BattleManager.get_snapshot()
    if snap.is_empty():
        return
    _refresh_hud(snap)
    _refresh_arms(snap)
    _refresh_enemy(snap)
    _refresh_hand(snap)


func _refresh_hud(snap: Dictionary) -> void:
    _body_hp_bar.max_value = max(1, snap.body_max_hp)
    _body_hp_bar.value = snap.body_hp
    _body_hp_label.text = "HP %d / %d" % [snap.body_hp, snap.body_max_hp]
    _energy_label.text = "에너지 %d" % snap.energy
    _turn_label.text = "TURN %d" % snap.turn
    _deck_label.text = "덱 %d  |  버림 %d  |  손 %d" % [snap.deck_size, snap.discard_size, snap.hand_size]


func _refresh_arms(snap: Dictionary) -> void:
    _refresh_arm("L", snap.arm_l_hp, snap.arm_l_max_hp, snap.arm_l_alive, snap.block_l)
    _refresh_arm("R", snap.arm_r_hp, snap.arm_r_max_hp, snap.arm_r_alive, snap.block_r)


func _refresh_arm(side: String, hp: int, max_hp: int, alive: bool, block: int) -> void:
    var bar: ProgressBar = (_arm_l_hp_bar if side == "L" else _arm_r_hp_bar)
    var hp_lbl: Label = (_arm_l_hp_label if side == "L" else _arm_r_hp_label)
    var blk_lbl: Label = (_arm_l_block_label if side == "L" else _arm_r_block_label)

    bar.max_value = max(1, max_hp)
    bar.value = hp

    if max_hp == 0:
        hp_lbl.text = "(빈 슬롯)"
    elif alive:
        hp_lbl.text = "HP %d / %d" % [hp, max_hp]
    else:
        hp_lbl.text = "파괴됨"

    blk_lbl.text = ("블록 %d" % block) if block > 0 else ""


func _refresh_enemy(snap: Dictionary) -> void:
    _enemy_name_label.text = snap.enemy_name
    _enemy_hp_bar.max_value = max(1, snap.enemy_max_hp)
    _enemy_hp_bar.value = snap.enemy_hp
    _enemy_hp_label.text = "HP %d / %d" % [snap.enemy_hp, snap.enemy_max_hp]

    if snap.enemy_hp > 0:
        _enemy_intent_label.text = "다음 공격: %d" % snap.next_intent
    else:
        _enemy_intent_label.text = ""


func _refresh_hand(snap: Dictionary) -> void:
    for btn in _card_buttons:
        btn.queue_free()
    _card_buttons.clear()

    var hand: Array = snap.hand
    for i in range(hand.size()):
        var card_inst: Dictionary = hand[i]
        var btn: Button = _make_card_button(i, card_inst, snap.energy)
        _hand_container.add_child(btn)
        _card_buttons.append(btn)


func _make_card_button(idx: int, card_inst: Dictionary, energy: int) -> Button:
    var card_def: Dictionary = GameData.CARD_TEMPLATES[card_inst.card_id]
    var preview: Dictionary = BattleManager.get_card_preview(idx)

    var btn := Button.new()
    btn.custom_minimum_size = CARD_SIZE

    var side: String = card_inst.arm_side
    btn.modulate = (CARD_COLOR_L if side == "L" else CARD_COLOR_R)

    var lines: Array = []
    lines.append("%s [%s]" % [card_def.name, side])
    lines.append("코스트 %d" % card_def.cost)
    for eff in preview.get("effects", []):
        match eff.type:
            "deal_damage":
                lines.append("딜 %d" % eff.final_value)
            "transfer_block":
                lines.append("블록 %d" % eff.final_value)
            "damage_own_arm":
                lines.append("자해 %d" % eff.final_value)
    btn.text = "\n".join(lines)
    btn.add_theme_font_size_override("font_size", 12)

    btn.disabled = (card_def.cost > energy)
    btn.pressed.connect(_on_card_pressed.bind(idx))
    return btn


# ============================================================
# 로그 · 유틸
# ============================================================

func _append_log(msg: String) -> void:
    _log_label.text = msg


func _side_kor(side: String) -> String:
    return "좌팔" if side == "L" else "우팔"
