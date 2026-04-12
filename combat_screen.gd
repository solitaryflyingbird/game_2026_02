extends Control

signal combat_finished(result: Dictionary)

# --- UI 노드 (코드에서 생성) ---
var status_label: Label
var enemy_container: VBoxContainer
var hand_container: HBoxContainer
var end_turn_button: Button
var log_label: Label

var enemy_labels: Array = []
var card_buttons: Array = []
var waiting_for_target: bool = false
var pending_card_index: int = -1

func _ready():
    # 상태 표시
    status_label = Label.new()
    status_label.position = Vector2(80, 30)
    add_child(status_label)

    # 적 표시
    enemy_container = VBoxContainer.new()
    enemy_container.position = Vector2(80, 80)
    enemy_container.add_theme_constant_override("separation", 8)
    add_child(enemy_container)

    # 핸드
    hand_container = HBoxContainer.new()
    hand_container.position = Vector2(80, 480)
    hand_container.add_theme_constant_override("separation", 12)
    add_child(hand_container)

    # 턴 종료 버튼
    end_turn_button = Button.new()
    end_turn_button.text = "턴 종료"
    end_turn_button.position = Vector2(1050, 500)
    end_turn_button.custom_minimum_size = Vector2(140, 50)
    end_turn_button.pressed.connect(_on_end_turn)
    add_child(end_turn_button)

    # 로그
    log_label = Label.new()
    log_label.position = Vector2(80, 400)
    log_label.add_theme_font_size_override("font_size", 14)
    add_child(log_label)

    # 기존 deck_label 숨기기
    if has_node("deck_label"):
        $deck_label.visible = false

func begin_combat():
    waiting_for_target = false
    pending_card_index = -1
    log_label.text = ""
    end_turn_button.visible = true

    var d = RunManager.run_data
    BattleManager.start_combat(d["deck"], d["hp"], d["max_hp"], ["test_dummy"])
    BattleManager.start_turn()
    _refresh_ui()

# ============================================================
# UI 갱신
# ============================================================

func _refresh_ui():
    _refresh_status()
    _refresh_enemies()
    _refresh_hand()
    _check_combat_end()

func _refresh_status():
    var p = BattleManager.player
    status_label.text = "턴 %d  |  HP %d/%d  |  방어 %d  |  에너지 %d/%d  |  드로우 %d  |  버림 %d" % [
        BattleManager.turn,
        p["hp"], p["max_hp"], p["block"],
        p["energy"], p["energy_max"],
        BattleManager.draw_pile.size(),
        BattleManager.discard_pile.size(),
    ]

func _refresh_enemies():
    for lbl in enemy_labels:
        lbl.queue_free()
    enemy_labels.clear()

    for i in range(BattleManager.enemies.size()):
        var e = BattleManager.enemies[i]
        var btn = Button.new()
        btn.custom_minimum_size = Vector2(400, 50)
        if e["hp"] <= 0:
            btn.text = "%s  [사망]" % e["name"]
            btn.disabled = true
        else:
            var intent_str = _intent_to_string(e["intent"])
            btn.text = "%s  HP %d/%d  방어 %d  [예고: %s]" % [
                e["name"], e["hp"], e["max_hp"], e["block"], intent_str]
            btn.disabled = not waiting_for_target
            btn.pressed.connect(_on_enemy_clicked.bind(i))
        enemy_container.add_child(btn)
        enemy_labels.append(btn)

func _refresh_hand():
    for btn in card_buttons:
        btn.queue_free()
    card_buttons.clear()

    for i in range(BattleManager.hand.size()):
        var card_inst = BattleManager.hand[i]
        var stats = GameData.get_card_stats(card_inst)
        var btn = Button.new()
        btn.custom_minimum_size = Vector2(140, 80)

        var label_parts := []
        label_parts.append("[%s]" % stats["type"])
        label_parts.append(stats["name"])
        label_parts.append("코스트 %d" % stats["cost"])
        if stats["damage"] > 0:
            label_parts.append("데미지 %d" % stats["damage"])
        if stats["block"] > 0:
            label_parts.append("방어 %d" % stats["block"])
        btn.text = "\n".join(label_parts)

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

    # BLOCK 등 자기 대상 카드
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

    # 로그
    if stats["damage"] > 0 and target_index >= 0:
        var ename = BattleManager.enemies[target_index]["name"]
        log_label.text = "%s 사용 → %s에게 %d 데미지" % [stats["name"], ename, stats["damage"]]
    elif stats["block"] > 0:
        log_label.text = "%s 사용 → 방어 %d 획득" % [stats["name"], stats["block"]]

    _refresh_ui()

func _on_end_turn():
    if waiting_for_target:
        return

    BattleManager.end_turn()
    BattleManager.enemy_turn()

    # 적 턴 로그
    var log_lines := PackedStringArray()
    for e in BattleManager.enemies:
        if e["hp"] > 0 and e["intent"].get("kind") == "attack":
            log_lines.append("%s의 공격 → %d 데미지" % [e["name"], e["intent"]["value"]])
    if log_lines.size() > 0:
        log_label.text = "\n".join(log_lines)

    if _check_combat_end():
        return

    BattleManager.start_turn()
    _refresh_ui()

# ============================================================
# 전투 종료 확인
# ============================================================

func _check_combat_end() -> bool:
    var result = BattleManager.is_combat_over()
    if result == "":
        return false

    # UI 정리
    for btn in card_buttons:
        btn.queue_free()
    card_buttons.clear()
    for lbl in enemy_labels:
        lbl.queue_free()
    enemy_labels.clear()
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
