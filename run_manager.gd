extends Node2D

signal state_changed

var run_data := {}

func _ready() -> void:
    init_run()

func init_run():
    run_data = GameData.starting_data.duplicate(true)
    run_data["deck"] = GameData.make_starting_deck()
    run_data["map"] = _generate_map()
    run_data["current_node_id"] = -1
    state_changed.emit()

# --- 맵 생성 (하드코딩 분기 맵) ---

func _generate_map() -> Array:
    # row 0: [0:전투]  [1:전투]
    #            ↘   ↙   ↘
    # row 1:  [2:엘리트] [3:전투]
    #             ↘       ↙
    # row 2:     [4:거점]
    #             ↙    ↘
    # row 3:  [5:전투] [6:전투]
    #             ↘    ↙
    # row 4:    [7:보스]
    return [
        {"id": 0, "row": 0, "col": 0, "type": "combat", "enemies": ["test_dummy"], "connections": [2, 3], "visited": false},
        {"id": 1, "row": 0, "col": 1, "type": "combat", "enemies": ["test_dummy"], "connections": [3], "visited": false},
        {"id": 2, "row": 1, "col": 0, "type": "elite", "enemies": ["test_dummy"], "connections": [4], "visited": false},
        {"id": 3, "row": 1, "col": 1, "type": "combat", "enemies": ["test_dummy"], "connections": [4, 5], "visited": false},
        {"id": 4, "row": 2, "col": 0, "type": "rest", "enemies": [], "connections": [5, 6], "visited": false},
        {"id": 5, "row": 3, "col": 0, "type": "combat", "enemies": ["test_dummy"], "connections": [7], "visited": false},
        {"id": 6, "row": 3, "col": 1, "type": "combat", "enemies": ["test_dummy"], "connections": [7], "visited": false},
        {"id": 7, "row": 4, "col": 0, "type": "boss", "enemies": ["test_dummy"], "connections": [], "visited": false},
    ]

func get_node_by_id(node_id: int) -> Dictionary:
    if node_id >= 0 and node_id < run_data["map"].size():
        return run_data["map"][node_id]
    return {}

func get_start_nodes() -> Array:
    var starts := []
    for node in run_data["map"]:
        if node["row"] == 0:
            starts.append(node["id"])
    return starts

func get_current_node() -> Dictionary:
    return get_node_by_id(run_data["current_node_id"])

func get_available_connections() -> Array:
    if run_data["current_node_id"] == -1:
        return get_start_nodes()
    var node = get_current_node()
    return node.get("connections", [])

# --- 맵 이동 ---

func move_to_node(node_id: int) -> bool:
    var available = get_available_connections()
    if node_id not in available:
        push_warning("move_to_node: %d is not in available connections %s" % [node_id, available])
        return false
    run_data["current_node_id"] = node_id
    run_data["map"][node_id]["visited"] = true
    _enter_node(node_id)
    return true

func _enter_node(node_id: int):
    var node = get_node_by_id(node_id)
    match node.get("type", ""):
        "combat", "elite", "boss":
            run_data["phase"] = "floor"
        "rest":
            run_data["phase"] = "rest"
        _:
            run_data["phase"] = "floor"
    state_changed.emit()

# --- 전투 결과 수신 ---

func _on_combat_finished(result: Dictionary):
    run_data["hp"] = result["hp"]
    if result["outcome"] == "lose":
        run_data["phase"] = "lose"
    else:
        var node = get_current_node()
        if node.get("type") == "boss":
            run_data["phase"] = "victory"
        else:
            run_data["phase"] = "reward"
    state_changed.emit()

# --- 전투 시작 ---

func start_combat():
    var node = get_current_node()
    var enemy_ids = node.get("enemies", ["test_dummy"])
    BattleManager.start_combat(run_data["deck"], run_data["hp"], run_data["max_hp"], enemy_ids)
    BattleManager.start_turn()
    run_data["phase"] = "combat"
    state_changed.emit()

# --- 거점 (임시수리) ---

func rest_heal_hp():
    run_data["hp"] = min(run_data["hp"] + 15, run_data["max_hp"])
    run_data["phase"] = "map"
    state_changed.emit()

# --- 버튼 핸들러 ---

func start_run():
    init_run()
    run_data["phase"] = "map"
    state_changed.emit()

func return_to_title():
    init_run()
    run_data["phase"] = "title"
    state_changed.emit()

# --- 디버그 ---

func _debug_print_map():
    print("=== MAP (%d nodes) ===" % run_data["map"].size())
    for node in run_data["map"]:
        var visited = "●" if node["visited"] else "○"
        print("  %s [%d] row:%d col:%d type:%s conn:%s" % [
            visited, node["id"], node["row"], node["col"], node["type"], node["connections"]])
    print("  current_node_id: %d" % run_data["current_node_id"])
    print("  available: %s" % get_available_connections())
