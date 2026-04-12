extends Node2D

signal state_changed

var run_data := {}

func _ready() -> void:
    init_run()

func init_run():
    run_data = GameData.starting_data.duplicate(true)
    run_data["deck"] = GameData.STARTING_DECK.duplicate()
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
    run_data["phase"] = "combat"
    state_changed.emit()

func return_to_title():
    init_run()
    run_data["phase"] = "title"
    state_changed.emit()
