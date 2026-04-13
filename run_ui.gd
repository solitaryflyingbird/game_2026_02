extends Node2D

@onready var screens = {
    "title": $title_screen,
    "map": $floor_screen,
    "floor": $floor_screen,
    "combat": $combat_screen,
    "reward": $reward_screen,
    "rest": $rest_screen,
    "lose": $result_screen,
    "victory": $result_screen,
}

# 맵 노드 선택 버튼 (동적 생성)
var map_buttons: Array = []

func _ready():
    RunManager.state_changed.connect(_on_state_changed)

    # 타이틀
    $title_screen/start_button.pressed.connect(RunManager.start_run)
    $title_screen/load_button.pressed.connect(_on_load_pressed)
    $title_screen/settings_button.pressed.connect(_on_settings_pressed)
    $title_screen/quit_button.pressed.connect(_on_quit_pressed)

    # 플로어 (전투 대기) — 전투 개시 버튼
    $floor_screen/battle_start_button.pressed.connect(RunManager.start_combat)

    # 전투 → 결과 수신
    $combat_screen.combat_finished.connect(RunManager._on_combat_finished)

    # 보상 — "맵으로" 버튼
    $reward_screen/next_floor_button.pressed.connect(_on_return_to_map)

    # 거점
    $rest_screen/heal_hp_button.pressed.connect(RunManager.rest_heal_hp)
    $rest_screen/skip_button.pressed.connect(_on_rest_skip)

    # 결과
    $result_screen/title_button.pressed.connect(RunManager.return_to_title)

    _on_state_changed()

# --- 화면 전환 ---

func _on_state_changed():
    var phase = RunManager.run_data["phase"]
    show_phase(phase)
    update_labels()

    if phase == "combat":
        $combat_screen.begin_combat()
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
    var hp_str = "%d / %d" % [RunManager.run_data["hp"], RunManager.run_data["max_hp"]]
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
    RunManager.run_data["phase"] = "map"
    RunManager.state_changed.emit()

func _on_rest_skip():
    RunManager.run_data["phase"] = "map"
    RunManager.state_changed.emit()

# --- 라벨 갱신 ---

func update_labels():
    var d = RunManager.run_data
    var hp_str = "%d / %d" % [d["hp"], d["max_hp"]]

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
    $rest_screen/rest_info.text = "HP %s  |  덱 %d장" % [hp_str, d["deck"].size()]

    # 결과 화면
    match d["phase"]:
        "victory":
            $result_screen/result_label.text = "임무 완료\n낙원 도달."
        "lose":
            $result_screen/result_label.text = "기동 정지\n임무 실패."

# --- 타이틀 버튼 ---

func _on_load_pressed():
    print("[title] 불러오기: 아직 구현되지 않음")

func _on_settings_pressed():
    print("[title] 설정: 아직 구현되지 않음")

func _on_quit_pressed():
    get_tree().quit()
