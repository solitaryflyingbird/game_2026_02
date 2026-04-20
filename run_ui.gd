extends Node2D

# ============================================================
# 런 진행 중 UI. RunManager.state_changed 구독 후 화면 갱신.
# 맵 시스템은 레거시 제거됨 — phase "map" 일 때 플로어 스크린을
# 임시 전투 진입점으로 재활용 (맵 재구축 후 교체 예정).
# ============================================================

@onready var screens = {
    "combat":  $battle_ui,
    "reward":  $reward_screen,
    "lose":    $result_screen,
    "victory": $result_screen,
}

# --- 팔 인스펙터 (자료구조 확인용 + 장착 조작) ---
var _btn_show_equipped: Button
var _btn_show_spare: Button
var _arm_inspector_panel: Panel
var _arm_inspector_container: VBoxContainer
var _arm_inspect_mode: String = ""  # "" | "equipped" | "spare"

# --- 맵 디스플레이 ---
const MAP_ORIGIN: Vector2 = Vector2(180, 90)
const MAP_SIZE: Vector2 = Vector2(880, 500)
var _map_root: Control
var _node_buttons: Dictionary = {}   # id: int → Button

# --- 전투 프리뷰 ---
var _battle_preview_root: Control
var _preview_enemy_name_label: Label
var _preview_enemy_hp_label: Label
var _preview_intents_label: Label

# --- 회귀 카운트 (맵 화면 우측 상단, 검증용 임시 라벨) ---
var _recurrence_label: Label


func _ready():
    RunManager.state_changed.connect(_on_state_changed)

    # 보상 — 맵으로 복귀 (적 제거된 상태로)
    $reward_screen/next_floor_button.pressed.connect(RunManager.return_to_map)
    # 결과 (승리·패배 공용) — 타이틀로
    $result_screen/title_button.pressed.connect(GameManager.return_to_title)

    _build_arm_inspector()
    _build_map_display()
    _build_battle_preview()
    _build_recurrence_label()


# --- 화면 전환 ---

func _on_state_changed():
    if RunManager.run_data.is_empty():
        _arm_inspector_panel.visible = false
        _btn_show_equipped.visible = false
        _btn_show_spare.visible = false
        if _map_root != null:
            _map_root.visible = false
        if _battle_preview_root != null:
            _battle_preview_root.visible = false
        if _recurrence_label != null:
            _recurrence_label.visible = false
        return

    var phase = RunManager.run_data["phase"]

    var in_combat: bool = phase == "combat"
    _btn_show_equipped.visible = not in_combat
    _btn_show_spare.visible = not in_combat
    if in_combat:
        _arm_inspector_panel.visible = false
        _arm_inspect_mode = ""

    show_phase(phase)
    update_labels()
    _refresh_arm_inspector()
    _refresh_map_display()
    _refresh_battle_preview()
    _refresh_recurrence_label(phase)

    if phase == "combat":
        $battle_ui.begin_combat()


func show_phase(phase: String):
    for screen in screens.values():
        screen.visible = false
    if phase in screens:
        screens[phase].visible = true
    if _map_root != null:
        _map_root.visible = phase == "map"
    if _battle_preview_root != null:
        _battle_preview_root.visible = phase == "battle_preview"


func update_labels():
    var d = RunManager.run_data
    if d.is_empty():
        return

    match d["phase"]:
        "victory":
            $result_screen/result_label.text = "임무 완료"
        "lose":
            $result_screen/result_label.text = "기동 정지"


# ============================================================
# 팔 인스펙터 (자료구조 확인용 + 장착 조작)
# ============================================================

func _build_arm_inspector():
    _btn_show_equipped = Button.new()
    _btn_show_equipped.text = "장착된 팔"
    _btn_show_equipped.position = Vector2(1100, 60)
    _btn_show_equipped.custom_minimum_size = Vector2(140, 32)
    _btn_show_equipped.pressed.connect(_on_show_equipped_pressed)
    _btn_show_equipped.visible = false
    add_child(_btn_show_equipped)

    _btn_show_spare = Button.new()
    _btn_show_spare.text = "스페어 팔"
    _btn_show_spare.position = Vector2(1100, 98)
    _btn_show_spare.custom_minimum_size = Vector2(140, 32)
    _btn_show_spare.pressed.connect(_on_show_spare_pressed)
    _btn_show_spare.visible = false
    add_child(_btn_show_spare)

    _arm_inspector_panel = Panel.new()
    _arm_inspector_panel.position = Vector2(900, 140)
    _arm_inspector_panel.size = Vector2(340, 420)
    _arm_inspector_panel.visible = false
    add_child(_arm_inspector_panel)

    _arm_inspector_container = VBoxContainer.new()
    _arm_inspector_container.position = Vector2(12, 12)
    _arm_inspector_container.size = Vector2(316, 396)
    _arm_inspector_container.add_theme_constant_override("separation", 6)
    _arm_inspector_panel.add_child(_arm_inspector_container)


func _on_show_equipped_pressed():
    if _arm_inspect_mode == "equipped":
        _arm_inspect_mode = ""
        _arm_inspector_panel.visible = false
    else:
        _arm_inspect_mode = "equipped"
        _arm_inspector_panel.visible = true
        _refresh_arm_inspector()


func _on_show_spare_pressed():
    if _arm_inspect_mode == "spare":
        _arm_inspect_mode = ""
        _arm_inspector_panel.visible = false
    else:
        _arm_inspect_mode = "spare"
        _arm_inspector_panel.visible = true
        _refresh_arm_inspector()


func _refresh_arm_inspector():
    if not _arm_inspector_panel.visible:
        return
    _clear_inspector_container()

    var data: Dictionary = RunManager.run_data
    if data.is_empty():
        return

    var instances: Dictionary = data.get("arm_instances", {})
    var equipped: Dictionary = data.get("equipped_arms", {"L": null, "R": null})

    if _arm_inspect_mode == "equipped":
        _build_equipped_view(instances, equipped)
    elif _arm_inspect_mode == "spare":
        var cap: int = data.get("arm_inventory_max", 6)
        _build_spare_view(instances, equipped, cap)


func _clear_inspector_container():
    for child in _arm_inspector_container.get_children():
        child.queue_free()


func _build_equipped_view(instances: Dictionary, equipped: Dictionary):
    _arm_inspector_container.add_child(_make_label("=== 장착된 팔 ===", 13))
    for side in ["L", "R"]:
        _arm_inspector_container.add_child(_make_label("[%s]" % side, 12))
        var id = equipped.get(side, null)
        if id == null:
            _arm_inspector_container.add_child(_make_label("  (빈 슬롯)", 11))
        else:
            var arm: Dictionary = instances.get(id, {})
            _arm_inspector_container.add_child(_make_label(_format_arm_text(arm), 11))


func _build_spare_view(instances: Dictionary, equipped: Dictionary, cap: int):
    var equipped_ids := [equipped.get("L"), equipped.get("R")]
    var spare_ids: Array = []
    for id in instances.keys():
        if id not in equipped_ids:
            spare_ids.append(id)

    _arm_inspector_container.add_child(
        _make_label("=== 스페어 팔 (%d / %d) ===" % [spare_ids.size(), cap], 13))

    if spare_ids.is_empty():
        _arm_inspector_container.add_child(_make_label("(비어있음)", 11))
        return

    for id in spare_ids:
        var arm: Dictionary = instances.get(id, {})
        _arm_inspector_container.add_child(_make_spare_entry(arm))


func _make_spare_entry(arm: Dictionary) -> Control:
    var entry = VBoxContainer.new()
    entry.add_theme_constant_override("separation", 2)

    entry.add_child(_make_label(_format_arm_text(arm), 11))

    var slot_type: String = arm.get("slot_type", "")
    var instance_id: int = arm.get("instance_id", 0)
    var can_l: bool = slot_type == "any" or slot_type == "left_arm"
    var can_r: bool = slot_type == "any" or slot_type == "right_arm"

    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 6)

    var btn_l = Button.new()
    btn_l.text = "L 장착"
    btn_l.custom_minimum_size = Vector2(80, 24)
    btn_l.disabled = not can_l
    btn_l.pressed.connect(_on_equip_pressed.bind("L", instance_id))
    row.add_child(btn_l)

    var btn_r = Button.new()
    btn_r.text = "R 장착"
    btn_r.custom_minimum_size = Vector2(80, 24)
    btn_r.disabled = not can_r
    btn_r.pressed.connect(_on_equip_pressed.bind("R", instance_id))
    row.add_child(btn_r)

    entry.add_child(row)
    return entry


func _on_equip_pressed(side: String, instance_id: int):
    RunManager.equip_arm(side, instance_id)


func _make_label(text: String, font_size: int) -> Label:
    var lbl = Label.new()
    lbl.text = text
    lbl.add_theme_font_size_override("font_size", font_size)
    return lbl


func _format_arm_text(arm: Dictionary) -> String:
    if arm.is_empty():
        return "  (데이터 없음)"
    return "  #%d %s (%s)\n  HP: %d / %d" % [
        arm.get("instance_id", 0),
        arm.get("name", "?"),
        arm.get("slot_type", "?"),
        arm.get("hp", 0),
        arm.get("max_hp", 0),
    ]


# ============================================================
# 맵 디스플레이 — TEST_MAP_GRAPH 기반 노드 그래프 + 이동
# ============================================================

func _build_map_display():
    _map_root = Control.new()
    _map_root.position = MAP_ORIGIN
    _map_root.size = MAP_SIZE
    _map_root.visible = false
    add_child(_map_root)

    # 엣지 (Line2D, 양방향 중 한 번만 그림)
    var drawn_edges: Dictionary = {}
    for id in GameData.TEST_MAP_GRAPH.keys():
        var node: Dictionary = GameData.TEST_MAP_GRAPH[id]
        for conn_id in node.connections:
            var a: int = min(id, conn_id)
            var b: int = max(id, conn_id)
            var key: String = "%d-%d" % [a, b]
            if drawn_edges.has(key):
                continue
            drawn_edges[key] = true

            var line := Line2D.new()
            line.points = PackedVector2Array([_node_position(id), _node_position(conn_id)])
            line.width = 3.0
            line.default_color = Color(0.5, 0.5, 0.55)
            _map_root.add_child(line)

    # 노드 버튼
    for id in GameData.TEST_MAP_GRAPH.keys():
        var btn := Button.new()
        var pos: Vector2 = _node_position(id)
        btn.custom_minimum_size = Vector2(80, 80)
        btn.position = pos - Vector2(40, 40)
        btn.text = "%d" % id
        btn.add_theme_font_size_override("font_size", 22)
        btn.pressed.connect(_on_map_node_pressed.bind(id))
        _map_root.add_child(btn)
        _node_buttons[id] = btn


func _node_position(id: int) -> Vector2:
    var node: Dictionary = GameData.TEST_MAP_GRAPH[id]
    var pos: Array = node.get("position", [0.5, 0.5])
    return Vector2(pos[0] * MAP_SIZE.x, pos[1] * MAP_SIZE.y)


func _on_map_node_pressed(id: int):
    RunManager.move_to_node(id)


func _refresh_map_display():
    if _map_root == null or not _map_root.visible:
        return
    var current_id = RunManager.run_data.get("current_node_id")
    var current_node: Dictionary = RunManager.get_current_node()
    var adjacent_ids: Array = current_node.get("connections", [])

    for id in _node_buttons.keys():
        var btn: Button = _node_buttons[id]
        var node: Dictionary = RunManager.get_node_by_id(id)
        var is_current: bool = id == current_id
        var is_visited: bool = node.get("visited", false)
        var is_adjacent: bool = id in adjacent_ids

        if is_current:
            btn.modulate = Color(1.0, 0.85, 0.3)     # 노랑 — 현재 위치
            btn.disabled = true
        elif is_adjacent:
            btn.modulate = Color(0.5, 1.0, 0.6)      # 초록 — 이동 가능
            btn.disabled = false
        elif is_visited:
            btn.modulate = Color(0.55, 0.55, 0.55)   # 회색 — 방문함
            btn.disabled = true
        else:
            btn.modulate = Color(0.85, 0.85, 0.85)   # 옅은 — 미방문/비인접
            btn.disabled = true


# ============================================================
# 전투 프리뷰 — enemy_id 있는 노드 진입 시 표시. "전투 시작" 버튼으로 진입.
# ============================================================

func _build_battle_preview():
    _battle_preview_root = Control.new()
    _battle_preview_root.position = Vector2(340, 180)
    _battle_preview_root.size = Vector2(600, 360)
    _battle_preview_root.visible = false
    add_child(_battle_preview_root)

    var panel = Panel.new()
    panel.size = Vector2(600, 360)
    _battle_preview_root.add_child(panel)

    var title = Label.new()
    title.text = "조우"
    title.position = Vector2(20, 16)
    title.add_theme_font_size_override("font_size", 16)
    _battle_preview_root.add_child(title)

    _preview_enemy_name_label = Label.new()
    _preview_enemy_name_label.position = Vector2(20, 56)
    _preview_enemy_name_label.size = Vector2(560, 36)
    _preview_enemy_name_label.add_theme_font_size_override("font_size", 24)
    _battle_preview_root.add_child(_preview_enemy_name_label)

    _preview_enemy_hp_label = Label.new()
    _preview_enemy_hp_label.position = Vector2(20, 110)
    _preview_enemy_hp_label.size = Vector2(560, 28)
    _preview_enemy_hp_label.add_theme_font_size_override("font_size", 14)
    _battle_preview_root.add_child(_preview_enemy_hp_label)

    _preview_intents_label = Label.new()
    _preview_intents_label.position = Vector2(20, 150)
    _preview_intents_label.size = Vector2(560, 28)
    _preview_intents_label.add_theme_font_size_override("font_size", 14)
    _battle_preview_root.add_child(_preview_intents_label)

    var start_btn = Button.new()
    start_btn.text = "전투 시작"
    start_btn.position = Vector2(230, 280)
    start_btn.custom_minimum_size = Vector2(140, 48)
    start_btn.pressed.connect(_on_preview_start_pressed)
    _battle_preview_root.add_child(start_btn)


func _on_preview_start_pressed():
    RunManager.start_combat()


func _refresh_battle_preview():
    if _battle_preview_root == null or not _battle_preview_root.visible:
        return
    var current: Dictionary = RunManager.get_current_node()
    var enemy_id = current.get("enemy_id")
    if enemy_id == null or not GameData.ENEMIES.has(enemy_id):
        _preview_enemy_name_label.text = "(enemy 없음)"
        _preview_enemy_hp_label.text = ""
        _preview_intents_label.text = ""
        return

    var enemy: Dictionary = GameData.ENEMIES[enemy_id]
    _preview_enemy_name_label.text = enemy.get("name", "?")
    _preview_enemy_hp_label.text = "HP %d" % enemy.get("max_hp", 0)

    var intents: Array = enemy.get("intents", [])
    var parts: Array = []
    for v in intents:
        parts.append(str(v))
    _preview_intents_label.text = "공격 패턴: %s (순환)" % " → ".join(parts)


# ============================================================
# 회귀 카운트 라벨 (임시 검증용. 맵 화면에서만 표시)
# ============================================================

func _build_recurrence_label() -> void:
    _recurrence_label = Label.new()
    _recurrence_label.position = Vector2(1080, 18)
    _recurrence_label.size = Vector2(180, 28)
    _recurrence_label.add_theme_font_size_override("font_size", 18)
    _recurrence_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _recurrence_label.visible = false
    add_child(_recurrence_label)


func _refresh_recurrence_label(phase: String) -> void:
    if _recurrence_label == null:
        return
    var show: bool = phase == "map"
    _recurrence_label.visible = show
    if not show:
        return
    var count: int = RunManager.big_run_data.get("meta", {}).get("big_run_count", 0)
    _recurrence_label.text = "회귀 %d 회" % count
