extends Node2D

@onready var screens = {
    "title": $title_screen,
    "floor": $floor_screen,
    "combat": $combat_screen,
    "reward": $reward_screen,
    "lose": $result_screen,
    "victory": $result_screen,
}

func _ready():
    RunManager.state_changed.connect(_on_state_changed)

    # 타이틀
    $title_screen/Button.pressed.connect(RunManager.start_run)

    # 플로어
    $floor_screen/battle_start_button.pressed.connect(RunManager.start_combat)

    # 전투 → 결과 수신
    $combat_screen.combat_finished.connect(RunManager._on_combat_finished)

    # 보상 — 메인 3종
    $reward_screen/heal_button.pressed.connect(RunManager.finish_reward_heal)
    $reward_screen/maxhp_button.pressed.connect(RunManager.finish_reward_maxhp)
    $reward_screen/upgrade_button.pressed.connect(_on_upgrade_button)

    # 보상 — 강화 서브패널 4종
    $reward_screen/dice_select_panel/attack_button.pressed.connect(
        RunManager.finish_reward_upgrade.bind("attack"))
    $reward_screen/dice_select_panel/block_button.pressed.connect(
        RunManager.finish_reward_upgrade.bind("block"))
    $reward_screen/dice_select_panel/boost_button.pressed.connect(
        RunManager.finish_reward_upgrade.bind("boost"))
    $reward_screen/dice_select_panel/heal_dice_button.pressed.connect(
        RunManager.finish_reward_upgrade.bind("heal"))

    # 결과
    $result_screen/title_button.pressed.connect(RunManager.return_to_title)

    _on_state_changed()

# --- 화면 전환 ---

func _on_state_changed():
    var phase = RunManager.run_data["phase"]
    show_phase(phase)
    update_labels()

    # combat 화면이 보이면 전투 시작
    if phase == "combat":
        $combat_screen.begin_combat()

func show_phase(phase: String):
    for screen in screens.values():
        screen.visible = false
    if phase in screens:
        screens[phase].visible = true
    # 보상 화면 진입 시 서브패널 닫기
    if phase != "reward":
        $reward_screen/dice_select_panel.visible = false

# --- 라벨 갱신 ---

func update_labels():
    var d = RunManager.run_data
    var floor_str = "%02d" % d["floor"]
    var hp_str = "%d / %d" % [d["hp"], d["max_hp"]]

    # 플로어 화면
    $floor_screen/floor_label.text = "FLOOR %s" % floor_str
    $floor_screen/hp_label.text = "HP %s" % hp_str
    _update_enemy_preview()

    # 전투 화면
    $combat_screen/floor_label.text = "FLOOR %s" % floor_str
    $combat_screen/hp_label.text = "HP %s" % hp_str

    # 보상 화면
    $reward_screen/info_label.text = "FLOOR %s CLEAR | HP %s" % [floor_str, hp_str]
    _update_dice_buttons()

    # 결과 화면
    match d["phase"]:
        "victory":
            $result_screen/result_label.text = "임무 완료\n폐기 철회. 은퇴 승인."
        "lose":
            $result_screen/result_label.text = "대파\n회수 불가. 폐기 집행."

# --- 보상: 강화 서브패널 ---

func _on_upgrade_button():
    $reward_screen/dice_select_panel.visible = true
    _update_dice_buttons()

func _update_dice_buttons():
    var dice = RunManager.run_data["dice"]
    var panel = $reward_screen/dice_select_panel
    var mapping = {
        "attack": panel.get_node("attack_button"),
        "block": panel.get_node("block_button"),
        "boost": panel.get_node("boost_button"),
        "heal": panel.get_node("heal_dice_button"),
    }
    var labels = { "attack": "ATK", "block": "BLK", "boost": "BST", "heal": "HEL" }

    for type in mapping:
        var btn = mapping[type]
        var grade = dice[type]["grade"]
        var exp = dice[type]["grade_exp"]
        if grade >= len(GameData.GRADE_FACES):
            btn.text = "%s\n등급 MAX" % labels[type]
            btn.disabled = true
        else:
            btn.text = "%s\n등급 %d (%d/%d)" % [labels[type], grade, exp, grade]
            btn.disabled = false

# --- 적 프리뷰 ---

func _update_enemy_preview():
    var floor_num = RunManager.run_data["floor"]
    if floor_num not in GameData.FLOOR_ENCOUNTERS:
        $floor_screen/enemy_label.text = ""
        return
    var encounter = GameData.FLOOR_ENCOUNTERS[floor_num]
    var parts = []
    for key in encounter:
        var enemy = GameData.ENEMIES[key]
        parts.append("%s (HP %d)" % [enemy["name"], enemy["hp"]])
    $floor_screen/enemy_label.text = "적 프리뷰: %s" % " / ".join(parts)
