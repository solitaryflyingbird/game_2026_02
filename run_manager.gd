extends Node2D

signal state_changed

var run_data := {}

func _ready() -> void:
    init_run()

func init_run():
    run_data = GameData.starting_data.duplicate(true)
    run_data["deck"] = GameData.make_starting_deck()
    state_changed.emit()

# --- 전투 결과 수신 ---

func _on_combat_finished(result: Dictionary):
    run_data["hp"] = result["hp"]
    if result["outcome"] == "lose":
        run_data["phase"] = "lose"
    elif run_data["floor"] >= 6:
        run_data["phase"] = "victory"
    else:
        run_data["phase"] = "reward"
    state_changed.emit()

# --- 층 진행 ---

func advance_floor():
    run_data["floor"] += 1
    run_data["phase"] = "floor"
    state_changed.emit()

# --- 버튼 핸들러 ---

func start_run():
    init_run()
    run_data["phase"] = "floor"
    state_changed.emit()

func start_combat():
    var enemy_ids = _get_enemies_for_floor(run_data["floor"])
    BattleManager.start_combat(run_data["deck"], run_data["hp"], run_data["max_hp"], enemy_ids)
    BattleManager.start_turn()
    run_data["phase"] = "combat"
    state_changed.emit()

func _get_enemies_for_floor(_floor: int) -> Array:
    # 추후 층 데이터에서 조회. 지금은 하드코딩.
    return ["test_dummy"]

func return_to_title():
    init_run()
    run_data["phase"] = "title"
    state_changed.emit()
