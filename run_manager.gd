extends Node2D

signal state_changed

var run_data := {}

func _ready() -> void:
    init_run()

func init_run():
    run_data = GameData.starting_data.duplicate(true)
    run_data["deck"] = GameData.make_starting_deck()
    run_data["map"] = _generate_map()
    run_data["floor"] = 0
    state_changed.emit()

# --- 맵 생성 ---

func _generate_map() -> Array:
    # 추후 에피소드 매니저로 분리. 지금은 하드코딩.
    return [
        {"type": "combat", "enemies": ["test_dummy"]},
        {"type": "combat", "enemies": ["test_dummy"]},
        {"type": "rest"},
        {"type": "combat", "enemies": ["test_dummy"]},
        {"type": "combat", "enemies": ["test_dummy"]},
        {"type": "boss", "enemies": ["test_dummy"]},
    ]

func _get_current_node() -> Dictionary:
    var floor_idx = run_data["floor"]
    if floor_idx >= 0 and floor_idx < run_data["map"].size():
        return run_data["map"][floor_idx]
    return {}

# --- 전투 결과 수신 ---

func _on_combat_finished(result: Dictionary):
    run_data["hp"] = result["hp"]
    if result["outcome"] == "lose":
        run_data["phase"] = "lose"
    elif run_data["floor"] >= run_data["map"].size() - 1:
        run_data["phase"] = "victory"
    else:
        run_data["phase"] = "reward"
    state_changed.emit()

# --- 층 진행 ---

func advance_floor():
    run_data["floor"] += 1
    _enter_current_node()

func _enter_current_node():
    var node = _get_current_node()
    match node.get("type", ""):
        "combat", "boss":
            run_data["phase"] = "floor"
        "rest":
            run_data["phase"] = "rest"
        _:
            run_data["phase"] = "floor"
    state_changed.emit()

# --- 전투 시작 ---

func start_combat():
    var node = _get_current_node()
    var enemy_ids = node.get("enemies", ["test_dummy"])
    BattleManager.start_combat(run_data["deck"], run_data["hp"], run_data["max_hp"], enemy_ids)
    BattleManager.start_turn()
    run_data["phase"] = "combat"
    state_changed.emit()

# --- 거점 (임시수리) ---

func rest_heal_hp():
    run_data["hp"] = min(run_data["hp"] + 15, run_data["max_hp"])
    advance_floor()

# --- 버튼 핸들러 ---

func start_run():
    init_run()
    run_data["floor"] = 0
    _enter_current_node()

func return_to_title():
    init_run()
    run_data["phase"] = "title"
    state_changed.emit()
