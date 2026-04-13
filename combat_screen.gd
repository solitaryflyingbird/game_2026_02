extends Control

signal combat_finished(result: Dictionary)

# ============================================================
# UI 노드 (코드에서 생성 — 안1 클래식 좌우 대치 레이아웃)
# ============================================================

# 상단 HUD
var hud_panel: Panel
var hud_hp_bar: ProgressBar
var hud_hp_label: Label
var hud_energy_label: Label
var hud_turn_label: Label
var hud_deck_label: Label

# 주인공 영역 (좌측)
var player_area: Control
var player_sprite: AnimatedSprite2D
var player_hp_bar: ProgressBar
var player_hp_label: Label
var player_block_label: Label

# 적 스프라이트 텍스처
var enemy_textures: Array = []

# 적 영역 (우측)
var enemy_container: HBoxContainer

# 핸드 (하단)
var hand_container: HBoxContainer

# 턴 종료 버튼
var end_turn_button: Button

# 로그
var log_label: Label

# 배경
var bg_texture: TextureRect

# 상태
var enemy_panels: Array = []
var card_buttons: Array = []
var waiting_for_target: bool = false
var pending_card_index: int = -1

func _ready():
    # 기존 deck_label 숨기기
    if has_node("deck_label"):
        $deck_label.visible = false

    _build_bg()
    _build_hud()
    _build_player_area()
    _build_enemy_area()
    _build_hand_area()
    _build_end_turn()
    _build_log()

# ============================================================
# UI 빌드
# ============================================================

func _build_bg():
    bg_texture = TextureRect.new()
    bg_texture.position = Vector2(0, 0)
    bg_texture.size = Vector2(1280, 720)
    bg_texture.expand_mode = 1
    bg_texture.stretch_mode = 6  # STRETCH_KEEP_ASPECT_COVERED
    bg_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg_texture)

func _set_bg_for_node():
    var node = RunManager.get_current_node()
    var node_type = node.get("type", "combat")
    match node_type:
        "boss":
            bg_texture.texture = load("res://에셋/배틀 리소스/배경/배경2.png")
        _:
            bg_texture.texture = load("res://에셋/배틀 리소스/배경/배경1.png")

func _build_hud():
    hud_panel = Panel.new()
    hud_panel.position = Vector2(0, 0)
    hud_panel.size = Vector2(1280, 56)
    add_child(hud_panel)

    # HP 바
    hud_hp_bar = ProgressBar.new()
    hud_hp_bar.position = Vector2(20, 14)
    hud_hp_bar.size = Vector2(280, 28)
    hud_hp_bar.max_value = 50
    hud_hp_bar.value = 50
    hud_hp_bar.show_percentage = false
    hud_panel.add_child(hud_hp_bar)

    hud_hp_label = Label.new()
    hud_hp_label.position = Vector2(24, 16)
    hud_hp_label.size = Vector2(272, 28)
    hud_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hud_hp_label.add_theme_font_size_override("font_size", 14)
    hud_panel.add_child(hud_hp_label)

    # 에너지
    hud_energy_label = Label.new()
    hud_energy_label.position = Vector2(320, 16)
    hud_energy_label.add_theme_font_size_override("font_size", 16)
    hud_panel.add_child(hud_energy_label)

    # 턴
    hud_turn_label = Label.new()
    hud_turn_label.position = Vector2(580, 16)
    hud_turn_label.size = Vector2(120, 28)
    hud_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hud_turn_label.add_theme_font_size_override("font_size", 14)
    hud_panel.add_child(hud_turn_label)

    # 덱/버림 카운터
    hud_deck_label = Label.new()
    hud_deck_label.position = Vector2(1000, 16)
    hud_deck_label.size = Vector2(260, 28)
    hud_deck_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    hud_deck_label.add_theme_font_size_override("font_size", 13)
    hud_panel.add_child(hud_deck_label)

func _build_player_area():
    # 주인공 영역 (좌측) — Panel 없이 직접 배치
    player_area = Control.new()
    player_area.position = Vector2(40, 120)
    player_area.size = Vector2(200, 300)
    add_child(player_area)

    # AnimatedSprite2D로 idle 4프레임
    player_sprite = AnimatedSprite2D.new()
    var frames = SpriteFrames.new()
    frames.add_animation("idle")
    frames.set_animation_speed("idle", 4)
    frames.set_animation_loop("idle", true)
    for i in range(4):
        var tex = load("res://에셋/배틀 리소스/주인공/frame_%d.png" % i)
        frames.add_frame("idle", tex)
    player_sprite.sprite_frames = frames
    player_sprite.animation = "idle"
    player_sprite.autoplay = "idle"
    player_sprite.position = Vector2(100, 100)
    player_sprite.scale = Vector2(0.38, 0.38)
    player_area.add_child(player_sprite)

    # HP 바 (적과 동일한 custom_minimum_size 방식)
    var hp_container = VBoxContainer.new()
    hp_container.position = Vector2(30, 210)
    hp_container.add_theme_constant_override("separation", 4)
    player_area.add_child(hp_container)

    player_hp_bar = ProgressBar.new()
    player_hp_bar.custom_minimum_size = Vector2(140, 12)
    player_hp_bar.max_value = 50
    player_hp_bar.value = 50
    player_hp_bar.show_percentage = false
    hp_container.add_child(player_hp_bar)

    player_hp_label = Label.new()
    player_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    player_hp_label.add_theme_font_size_override("font_size", 12)
    hp_container.add_child(player_hp_label)

    player_block_label = Label.new()
    player_block_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    player_block_label.add_theme_font_size_override("font_size", 12)
    hp_container.add_child(player_block_label)

func _build_enemy_area():
    enemy_container = HBoxContainer.new()
    enemy_container.position = Vector2(650, 120)
    enemy_container.add_theme_constant_override("separation", 24)
    add_child(enemy_container)

    # 적 텍스처 로드
    enemy_textures = [
        load("res://에셋/배틀 리소스/예시 적/1.png"),
        load("res://에셋/배틀 리소스/예시 적/2.png"),
    ]

func _build_hand_area():
    hand_container = HBoxContainer.new()
    hand_container.position = Vector2(200, 580)
    hand_container.add_theme_constant_override("separation", 14)
    add_child(hand_container)

func _build_end_turn():
    end_turn_button = Button.new()
    end_turn_button.text = "턴 종료"
    end_turn_button.position = Vector2(1080, 460)
    end_turn_button.custom_minimum_size = Vector2(140, 50)
    end_turn_button.pressed.connect(_on_end_turn)
    add_child(end_turn_button)

func _build_log():
    log_label = Label.new()
    log_label.position = Vector2(300, 470)
    log_label.size = Vector2(500, 60)
    log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    log_label.add_theme_font_size_override("font_size", 15)
    add_child(log_label)

# ============================================================
# 전투 시작
# ============================================================

func begin_combat():
    waiting_for_target = false
    pending_card_index = -1
    log_label.text = ""
    end_turn_button.visible = true
    _set_bg_for_node()
    _refresh_ui()

# ============================================================
# UI 갱신
# ============================================================

func _refresh_ui():
    _refresh_hud()
    _refresh_player()
    _refresh_enemies()
    _refresh_hand()
    _check_combat_end()

func _refresh_hud():
    var p = BattleManager.player
    # HP 바
    hud_hp_bar.max_value = p["max_hp"]
    hud_hp_bar.value = p["hp"]
    hud_hp_label.text = "HP %d / %d" % [p["hp"], p["max_hp"]]
    # 에너지
    hud_energy_label.text = "에너지 %d / %d" % [p["energy"], p["energy_max"]]
    # 턴
    hud_turn_label.text = "TURN %d" % BattleManager.turn
    # 덱/버림
    hud_deck_label.text = "덱 %d | 버림 %d" % [
        BattleManager.draw_pile.size(),
        BattleManager.discard_pile.size()]

func _refresh_player():
    var p = BattleManager.player
    player_hp_bar.max_value = p["max_hp"]
    player_hp_bar.value = p["hp"]
    player_hp_label.text = "HP %d / %d" % [p["hp"], p["max_hp"]]
    if p["block"] > 0:
        player_block_label.text = "방어 %d" % p["block"]
    else:
        player_block_label.text = ""

func _refresh_enemies():
    for panel in enemy_panels:
        panel.queue_free()
    enemy_panels.clear()

    for i in range(BattleManager.enemies.size()):
        var e = BattleManager.enemies[i]

        var panel = VBoxContainer.new()
        panel.custom_minimum_size = Vector2(150, 220)
        panel.add_theme_constant_override("separation", 6)

        # 의도
        var intent_label = Label.new()
        intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        intent_label.add_theme_font_size_override("font_size", 13)
        if e["hp"] > 0:
            intent_label.text = "[%s]" % _intent_to_string(e["intent"])
        else:
            intent_label.text = ""
        panel.add_child(intent_label)

        # 적 스프라이트 + 클릭 영역
        var sprite_container = Control.new()
        sprite_container.custom_minimum_size = Vector2(180, 120)

        # 스프라이트 이미지
        var tex_rect = TextureRect.new()
        if enemy_textures.size() > 0:
            tex_rect.texture = enemy_textures[0]
        tex_rect.expand_mode = 1
        tex_rect.stretch_mode = 5
        tex_rect.size = Vector2(180, 112)
        if e["hp"] <= 0:
            tex_rect.modulate = Color(0.3, 0.3, 0.3, 0.5)
        sprite_container.add_child(tex_rect)

        # 클릭 가능 투명 버튼 (스프라이트 위에)
        var sprite_btn = Button.new()
        sprite_btn.flat = true
        sprite_btn.size = Vector2(180, 112)
        sprite_btn.mouse_filter = Control.MOUSE_FILTER_STOP
        if e["hp"] <= 0:
            sprite_btn.disabled = true
        else:
            sprite_btn.disabled = not waiting_for_target
            sprite_btn.pressed.connect(_on_enemy_clicked.bind(i))
        sprite_container.add_child(sprite_btn)

        # 사망 라벨
        if e["hp"] <= 0:
            var dead_label = Label.new()
            dead_label.text = "사망"
            dead_label.size = Vector2(180, 112)
            dead_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            dead_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
            dead_label.add_theme_font_size_override("font_size", 20)
            sprite_container.add_child(dead_label)

        panel.add_child(sprite_container)

        # HP 바
        var hp_bar = ProgressBar.new()
        hp_bar.custom_minimum_size = Vector2(140, 12)
        hp_bar.max_value = e["max_hp"]
        hp_bar.value = max(0, e["hp"])
        hp_bar.show_percentage = false
        panel.add_child(hp_bar)

        # HP 텍스트 + 블록
        var hp_label = Label.new()
        hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        hp_label.add_theme_font_size_override("font_size", 12)
        var hp_text = "HP %d/%d" % [max(0, e["hp"]), e["max_hp"]]
        if e["block"] > 0:
            hp_text += " | 방어 %d" % e["block"]
        hp_label.text = hp_text
        panel.add_child(hp_label)

        enemy_container.add_child(panel)
        enemy_panels.append(panel)

func _refresh_hand():
    for btn in card_buttons:
        btn.queue_free()
    card_buttons.clear()

    for i in range(BattleManager.hand.size()):
        var card_inst = BattleManager.hand[i]
        var stats = GameData.get_card_stats(card_inst)

        var btn = Button.new()
        btn.custom_minimum_size = Vector2(130, 160)

        # 카드 텍스트
        var lines := []
        lines.append(stats["name"])
        lines.append("코스트 %d" % stats["cost"])
        if stats["damage"] > 0:
            lines.append("DMG %d" % stats["damage"])
        if stats["block"] > 0:
            lines.append("BLK %d" % stats["block"])
        btn.text = "\n".join(lines)

        var can_play = BattleManager.can_play_card(i)
        btn.disabled = not can_play or waiting_for_target
        btn.pressed.connect(_on_card_clicked.bind(i))
        hand_container.add_child(btn)
        card_buttons.append(btn)

    end_turn_button.disabled = waiting_for_target

# ============================================================
# 입력 처리
# ============================================================

func _on_card_clicked(hand_index: int):
    if waiting_for_target:
        pending_card_index = hand_index
        var stats = GameData.get_card_stats(BattleManager.hand[hand_index])
        if stats["type"] != "ATTACK":
            waiting_for_target = false
            pending_card_index = -1
            log_label.text = ""
            _execute_card(hand_index, -1)
        else:
            log_label.text = "공격 대상을 선택하세요"
            _refresh_hand()
        return

    var card_inst = BattleManager.hand[hand_index]
    var stats = GameData.get_card_stats(card_inst)

    if stats["type"] == "ATTACK":
        var alive = BattleManager._get_alive_enemies()
        if alive.size() == 1:
            _execute_card(hand_index, alive[0])
        elif alive.size() > 1:
            waiting_for_target = true
            pending_card_index = hand_index
            log_label.text = "공격 대상을 선택하세요"
            _refresh_enemies()
            _refresh_hand()
        return

    _execute_card(hand_index, -1)

func _on_enemy_clicked(enemy_index: int):
    if not waiting_for_target:
        return
    if BattleManager.enemies[enemy_index]["hp"] <= 0:
        return

    var idx = pending_card_index
    waiting_for_target = false
    pending_card_index = -1
    log_label.text = ""
    _execute_card(idx, enemy_index)

func _execute_card(hand_index: int, target_index: int):
    var card_inst = BattleManager.hand[hand_index]
    var stats = GameData.get_card_stats(card_inst)

    BattleManager.play_card(hand_index, target_index)

    if stats["damage"] > 0 and target_index >= 0:
        var ename = BattleManager.enemies[target_index]["name"]
        log_label.text = "%s → %s에게 %d 데미지" % [stats["name"], ename, stats["damage"]]
    elif stats["block"] > 0:
        log_label.text = "%s → 방어 %d" % [stats["name"], stats["block"]]

    _refresh_ui()

func _on_end_turn():
    if waiting_for_target:
        return

    BattleManager.end_turn()
    BattleManager.enemy_turn()

    var log_lines := PackedStringArray()
    for e in BattleManager.enemies:
        if e["hp"] > 0 and e["intent"].get("kind") == "attack":
            log_lines.append("%s → %d 데미지" % [e["name"], e["intent"]["value"]])
    if log_lines.size() > 0:
        log_label.text = "\n".join(log_lines)

    if _check_combat_end():
        return

    BattleManager.start_turn()
    _refresh_ui()

# ============================================================
# 전투 종료
# ============================================================

func _check_combat_end() -> bool:
    var result = BattleManager.is_combat_over()
    if result == "":
        return false

    for btn in card_buttons:
        btn.queue_free()
    card_buttons.clear()
    for panel in enemy_panels:
        panel.queue_free()
    enemy_panels.clear()
    end_turn_button.visible = false

    var r = BattleManager.get_result()
    combat_finished.emit(r)
    return true

# ============================================================
# 유틸
# ============================================================

func _intent_to_string(intent: Dictionary) -> String:
    match intent.get("kind", ""):
        "attack":
            return "공격 %d" % intent["value"]
        "block":
            return "방어 %d" % intent["value"]
        _:
            return "?"
