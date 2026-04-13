extends Node2D

@onready var screens = {
    "title": $title_screen,
    "floor": $floor_screen,
    "combat": $combat_screen,
    "reward": $reward_screen,
    "rest": $rest_screen,
    "lose": $result_screen,
    "victory": $result_screen,
}

func _ready():
    RunManager.state_changed.connect(_on_state_changed)

    # 타이틀
    $title_screen/start_button.pressed.connect(RunManager.start_run)
    $title_screen/load_button.pressed.connect(_on_load_pressed)
    $title_screen/settings_button.pressed.connect(_on_settings_pressed)
    $title_screen/quit_button.pressed.connect(_on_quit_pressed)

    # 플로어
    $floor_screen/battle_start_button.pressed.connect(RunManager.start_combat)

    # 전투 → 결과 수신
    $combat_screen.combat_finished.connect(RunManager._on_combat_finished)

    # 보상 — "다음 층" 버튼
    $reward_screen/next_floor_button.pressed.connect(RunManager.advance_floor)

    # 거점
    $rest_screen/heal_hp_button.pressed.connect(RunManager.rest_heal_hp)
    $rest_screen/skip_button.pressed.connect(RunManager.advance_floor)

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

func show_phase(phase: String):
    for screen in screens.values():
        screen.visible = false
    if phase in screens:
        screens[phase].visible = true

# --- 라벨 갱신 ---

func update_labels():
    var d = RunManager.run_data
    var floor_idx = d["floor"]
    var floor_display = floor_idx + 1
    var hp_str = "%d / %d" % [d["hp"], d["max_hp"]]

    # 플로어 화면
    $floor_screen/floor_label.text = "FLOOR %02d" % floor_display
    $floor_screen/hp_label.text = "HP %s" % hp_str

    # 맵 노드 정보 표시
    var node = RunManager._get_current_node()
    var node_type = node.get("type", "?")
    var next_info = ""
    match node_type:
        "combat":
            var enemies = node.get("enemies", [])
            next_info = "전투: %s" % ", ".join(enemies)
        "boss":
            var enemies = node.get("enemies", [])
            next_info = "보스: %s" % ", ".join(enemies)
        "rest":
            next_info = "거점 (수습소)"
    $floor_screen/enemy_label.text = next_info

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
