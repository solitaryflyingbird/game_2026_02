extends Control

signal combat_finished(result: Dictionary)

# --- UI 노드 ---
var hand_container: HBoxContainer
var enemy_container: HBoxContainer
var confirm_button: Button
var info_label: Label

# --- 상태 ---
var card_buttons: Array = []
var enemy_buttons: Array = []
var selected: Array = []  # 선택된 카드 인덱스
var waiting_for_target: bool = false

const TYPE_LABELS = { "attack": "ATK", "block": "BLK", "boost": "BST", "heal": "HEL" }
const TYPE_COLORS = {
    "attack": Color(0.89, 0.29, 0.29),
    "block": Color(0.09, 0.37, 0.65),
    "boost": Color(0.73, 0.46, 0.09),
    "heal": Color(0.39, 0.60, 0.13),
}

func _ready():
    # 적 컨테이너 (상단)
    enemy_container = HBoxContainer.new()
    enemy_container.position = Vector2(300, 120)
    enemy_container.add_theme_constant_override("separation", 24)
    add_child(enemy_container)

    # 핸드 컨테이너 (하단)
    hand_container = HBoxContainer.new()
    hand_container.position = Vector2(200, 500)
    hand_container.add_theme_constant_override("separation", 16)
    add_child(hand_container)

    # 확정 버튼
    confirm_button = Button.new()
    confirm_button.text = "3장 선택"
    confirm_button.position = Vector2(500, 620)
    confirm_button.custom_minimum_size = Vector2(120, 50)
    confirm_button.disabled = true
    confirm_button.pressed.connect(_on_confirm)
    add_child(confirm_button)

    # 안내 라벨
    info_label = Label.new()
    info_label.position = Vector2(300, 420)
    info_label.text = ""
    add_child(info_label)

    # stub 라벨 숨기기
    if has_node("stub_label"):
        $stub_label.visible = false
    if has_node("stub_result"):
        $stub_result.visible = false

    # signal 연결
    BattleManager.turn_started.connect(_on_turn_started)
    BattleManager.combo_resolved.connect(_on_combo_resolved)
    BattleManager.enemy_turn_done.connect(_on_enemy_turn_done)
    BattleManager.combat_ended.connect(_on_combat_ended)

func begin_combat():
    confirm_button.visible = true
    info_label.text = ""
    waiting_for_target = false

    var d = RunManager.run_data
    var enemies = BattleManager.spawn_enemies(d["floor"])
    BattleManager.init_combat(d["dice"], d["hp"], d["max_hp"], enemies)
    _build_enemy_ui()
    BattleManager.start_turn()


# ============================
# 적 표시
# ============================

func _build_enemy_ui():
    _clear_enemies()
    var enemies = BattleManager.combat_state["enemies"]
    for i in range(enemies.size()):
        var enemy = enemies[i]
        var btn = Button.new()
        btn.custom_minimum_size = Vector2(120, 100)
        btn.text = "%s\nHP %d/%d" % [enemy["name"], enemy["hp"], enemy["max_hp"]]
        btn.pressed.connect(_on_enemy_pressed.bind(i))
        enemy_container.add_child(btn)
        enemy_buttons.append(btn)

func _update_enemy_ui():
    var enemies = BattleManager.combat_state["enemies"]
    for i in range(enemy_buttons.size()):
        var enemy = enemies[i]
        var btn = enemy_buttons[i]
        if enemy["hp"] <= 0:
            btn.text = "%s\n사망" % enemy["name"]
            btn.disabled = true
            btn.modulate = Color(0.5, 0.5, 0.5)
        else:
            btn.text = "%s\nHP %d/%d" % [enemy["name"], enemy["hp"], enemy["max_hp"]]
            btn.disabled = not waiting_for_target
            btn.modulate = Color.WHITE

func _clear_enemies():
    for btn in enemy_buttons:
        btn.queue_free()
    enemy_buttons.clear()


# ============================
# 핸드 표시
# ============================

func _on_turn_started():
    _clear_hand()
    selected.clear()
    waiting_for_target = false
    confirm_button.disabled = true
    confirm_button.text = "3장 선택"
    info_label.text = "카드 3장을 선택하세요"

    # 상태 라벨 갱신
    _update_status_labels()
    _update_enemy_ui()

    var hand = BattleManager.combat_state["hand"]
    for i in range(hand.size()):
        var card = hand[i]
        var btn = Button.new()
        btn.custom_minimum_size = Vector2(100, 80)
        btn.text = "%s\n%d" % [TYPE_LABELS[card["type"]], card["value"]]
        btn.pressed.connect(_on_card_pressed.bind(i))
        hand_container.add_child(btn)
        card_buttons.append(btn)

func _clear_hand():
    for btn in card_buttons:
        btn.queue_free()
    card_buttons.clear()


# ============================
# 카드 선택
# ============================

func _on_card_pressed(index: int):
    if waiting_for_target:
        return

    if index in selected:
        selected.erase(index)
    else:
        if selected.size() >= 3:
            return
        selected.append(index)

    _update_card_visuals()
    _update_confirm_button()

func _update_card_visuals():
    var hand = BattleManager.combat_state["hand"]
    for i in range(card_buttons.size()):
        var btn = card_buttons[i]
        var card = hand[i]
        if i in selected:
            btn.modulate = TYPE_COLORS[card["type"]]
            btn.position.y = -10
        else:
            btn.modulate = Color.WHITE
            btn.position.y = 0

func _update_confirm_button():
    if selected.size() != 3:
        confirm_button.disabled = true
        confirm_button.text = "3장 선택"
        return

    var hand = BattleManager.combat_state["hand"]
    var cards = []
    for i in selected:
        cards.append(hand[i])

    if BattleManager.is_valid_combo(cards):
        confirm_button.disabled = false
        confirm_button.text = "확정"
    else:
        confirm_button.disabled = true
        confirm_button.text = "무효 조합"


# ============================
# 확정 + 타겟 선택
# ============================

func _on_confirm():
    var hand = BattleManager.combat_state["hand"]
    var cards = []
    for i in selected:
        cards.append(hand[i])

    BattleManager.submit_combo(cards)
    confirm_button.disabled = true

    # attack이 포함되어 있는지 확인
    var has_attack = false
    for card in cards:
        if card["type"] == "attack":
            has_attack = true
            break

    var alive = BattleManager.get_alive_enemies()

    if has_attack and alive.size() >= 2:
        # 타겟 선택 모드
        waiting_for_target = true
        info_label.text = "공격 대상을 선택하세요"
        _update_enemy_ui()  # 적 버튼 활성화
    else:
        # 자동 타겟 → 바로 resolve
        var target = alive[0] if alive.size() > 0 else 0
        _do_resolve(target)

func _on_enemy_pressed(index: int):
    if not waiting_for_target:
        return

    var enemies = BattleManager.combat_state["enemies"]
    if enemies[index]["hp"] <= 0:
        return

    waiting_for_target = false
    _do_resolve(index)

func _do_resolve(target_index: int):
    selected.clear()
    _update_card_visuals()
    info_label.text = ""

    var result = BattleManager.resolve(target_index)
    # resolve 안에서 combo_resolved, enemy_turn_done, combat_ended signal이 emit됨
    if result == "continue":
        BattleManager.start_turn()


# ============================
# signal 핸들러 (상태 갱신)
# ============================

func _on_combo_resolved():
    _update_enemy_ui()
    _update_status_labels()

func _on_enemy_turn_done():
    _update_enemy_ui()
    _update_status_labels()

func _on_combat_ended(result: Dictionary):
    _clear_hand()
    _clear_enemies()
    confirm_button.visible = false
    info_label.text = ""
    combat_finished.emit(result)

func _update_status_labels():
    var s = BattleManager.combat_state
    $floor_label.text = "FLOOR %02d" % RunManager.run_data["floor"]
    $hp_label.text = "HP %d/%d | Shield %d | Boost x%d" % [
        s["player_hp"], s["player_max_hp"], s["shield"], s["boost_multiplier"]
    ]
