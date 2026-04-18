extends Node2D

# ============================================================
# 런 진행 중 UI. RunManager.state_changed 를 구독해 화면을 갱신한다.
# 타이틀·설정 등 앱 레벨 UI 는 game_ui.gd 소관.
# ============================================================

@onready var screens = {
    "map": $floor_screen,
    "floor": $floor_screen,
    "combat": $battle_ui,
    "reward": $reward_screen,
    "rest": $rest_screen,
    "lose": $result_screen,
    "victory": $result_screen,
}

# 맵 노드 선택 버튼 (동적 생성)
var map_buttons: Array = []

# --- 팔 인스펙터 (자료구조 확인용 디버그 UI) ---
var _btn_show_equipped: Button
var _btn_show_spare: Button
var _arm_inspector_panel: Panel
var _arm_inspector_container: VBoxContainer
var _arm_inspect_mode: String = ""  # "" | "equipped" | "spare"

func _ready():
    RunManager.state_changed.connect(_on_state_changed)

    # 플로어 (전투 대기) — 전투 개시 버튼
    $floor_screen/battle_start_button.pressed.connect(RunManager.start_combat)

    # 보상 — "맵으로" 버튼
    $reward_screen/next_floor_button.pressed.connect(_on_return_to_map)

    # 거점
    $rest_screen/heal_hp_button.pressed.connect(RunManager.rest_heal_hp)
    $rest_screen/skip_button.pressed.connect(_on_rest_skip)

    # 결과 — "타이틀로" (앱 레벨 전환이므로 GameManager 경유)
    $result_screen/title_button.pressed.connect(GameManager.return_to_title)

    _build_arm_inspector()

# --- 화면 전환 ---

func _on_state_changed():
    if RunManager.run_data.is_empty():
        _arm_inspector_panel.visible = false
        _btn_show_equipped.visible = false
        _btn_show_spare.visible = false
        return

    var phase = RunManager.run_data["phase"]

    # 전투 중에는 팔 인스펙터(장착 조작) 숨김 — 배틀 중 교체 불가.
    var in_combat: bool = phase == "combat"
    _btn_show_equipped.visible = not in_combat
    _btn_show_spare.visible = not in_combat
    if in_combat:
        _arm_inspector_panel.visible = false
        _arm_inspect_mode = ""

    show_phase(phase)
    update_labels()
    _refresh_arm_inspector()

    if phase == "combat":
        $battle_ui.begin_combat()
    elif phase == "map":
        _build_map_ui()

func show_phase(phase: String):
    for screen in screens.values():
        screen.visible = false
    if phase in screens:
        screens[phase].visible = true

# --- 맵 UI (floor_screen을 재활용) ---

func _build_map_ui():
    # 기존 맵 버튼 제거
    for btn in map_buttons:
        btn.queue_free()
    map_buttons.clear()

    # 상태 표시
    var hp_str = "%d / %d" % [RunManager.run_data["body_hp"], RunManager.run_data["body_max_hp"]]
    $floor_screen/floor_label.text = "=== MAP ==="
    $floor_screen/hp_label.text = "HP %s" % hp_str

    # 전투 개시 버튼 숨김 (맵에서는 노드 선택으로 진행)
    $floor_screen/battle_start_button.visible = false

    # 갈 수 있는 노드 표시
    var available = RunManager.get_available_connections()
    var info_lines := PackedStringArray()

    for node_id in available:
        var node = RunManager.get_node_by_id(node_id)
        var type_str = node.get("type", "?")
        var label = "[%d] %s" % [node_id, type_str]
        if node.get("enemies", []).size() > 0:
            label += " (%s)" % ", ".join(node["enemies"])

        var btn = Button.new()
        btn.text = label
        btn.custom_minimum_size = Vector2(300, 40)
        btn.pressed.connect(_on_map_node_selected.bind(node_id))
        $floor_screen.add_child(btn)
        btn.position = Vector2(80, 250 + map_buttons.size() * 50)
        map_buttons.append(btn)

    # 방문 기록 표시
    info_lines.append("현재 위치: %d" % RunManager.run_data["current_node_id"])
    info_lines.append("선택 가능: %s" % str(available))
    $floor_screen/enemy_label.text = "\n".join(info_lines)

    # 디버그 출력
    RunManager._debug_print_map()

func _on_map_node_selected(node_id: int):
    RunManager.move_to_node(node_id)

# --- 보상/거점 → 맵 복귀 ---

func _on_return_to_map():
    RunManager.return_to_map()

func _on_rest_skip():
    RunManager.return_to_map()

# --- 라벨 갱신 ---

func update_labels():
    var d = RunManager.run_data
    if d.is_empty():
        return
    var hp_str = "%d / %d" % [d["body_hp"], d["body_max_hp"]]

    # 플로어 화면 (전투 대기)
    if d["phase"] == "floor":
        var node = RunManager.get_current_node()
        var type_str = node.get("type", "?")
        $floor_screen/floor_label.text = "%s 노드" % type_str.to_upper()
        $floor_screen/hp_label.text = "HP %s" % hp_str
        $floor_screen/battle_start_button.visible = true
        var enemies = node.get("enemies", [])
        $floor_screen/enemy_label.text = "적: %s" % ", ".join(enemies)

    # 거점 화면
    $rest_screen/rest_info.text = "HP %s" % hp_str

    # 결과 화면
    match d["phase"]:
        "victory":
            $result_screen/result_label.text = "임무 완료\n낙원 도달."
        "lose":
            $result_screen/result_label.text = "기동 정지\n임무 실패."

# --- 팔 인스펙터 (자료구조 확인용 + 장착 조작) ---

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
    # equip_arm 성공 시 state_changed 발신 → _on_state_changed → _refresh_arm_inspector 자동 갱신

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
