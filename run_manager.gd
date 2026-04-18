extends Node2D

signal state_changed

var run_data: Dictionary = {}

func _ready() -> void:
    # 런은 GameManager.start_run() 이 호출하는 init_run() 으로 개시된다.
    # 부팅 시점의 run_data 는 비어있고, 타이틀 상태는 GameManager 가 관리한다.
    pass

# GameManager.start_run() 이 호출한다.
func init_run():
    var body_max: int = GameData.INITIAL_BODY.max_hp
    run_data = {
        "phase": "map",
        "body_hp": body_max,
        "body_max_hp": body_max,
        "arm_modules": {
            "L": _make_arm_state("left_arm_module"),
            "R": _make_arm_state("right_arm_module"),
        },
        "current_floor": 1,
        "map": _generate_map(),
        "current_node_id": -1,
    }
    state_changed.emit()

# GameManager.return_to_title() 이 호출한다.
func reset() -> void:
    run_data = {}
    state_changed.emit()

func _make_arm_state(module_id: String) -> Dictionary:
    var module: Dictionary = GameData.ARM_MODULES[module_id]
    return {
        "module_id": module_id,
        "hp": module.max_hp,
    }

# --- 팔 상태 접근 API (side: "L" | "R") --------------------------------------

func get_arm_state(side: String) -> Dictionary:
    return run_data.get("arm_modules", {}).get(side, {})

func get_arm_card_ids(side: String) -> Array:
    var arm: Dictionary = get_arm_state(side)
    if arm.is_empty():
        return []
    var module_id: String = arm.get("module_id", "")
    if module_id == "" or not GameData.ARM_MODULES.has(module_id):
        return []
    return GameData.ARM_MODULES[module_id].card_ids

func get_arm_card_stats(side: String, idx: int) -> Dictionary:
    var card_ids: Array = get_arm_card_ids(side)
    if idx < 0 or idx >= card_ids.size():
        return {}
    var card_id: String = card_ids[idx]
    if not GameData.CARD_TEMPLATES.has(card_id):
        return {}
    return GameData.CARD_TEMPLATES[card_id]

# --- 맵 생성 (하드코딩 분기 맵) ---

func _generate_map() -> Array:
    # 테스트용 최소 맵: 일반 → 정비 → 보스
    return [
        {"id": 0, "row": 0, "col": 0, "type": "combat", "enemies": ["test_dummy"], "connections": [1], "visited": false},
        {"id": 1, "row": 1, "col": 0, "type": "rest", "enemies": [], "connections": [2], "visited": false},
        {"id": 2, "row": 2, "col": 0, "type": "boss", "enemies": ["test_dummy"], "connections": [], "visited": false},
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

func return_to_map():
    run_data["phase"] = "map"
    state_changed.emit()

# --- 전투 결과 수신 (5단계에서 새 battle_ended 시그널로 재배선 예정) ---

func _on_combat_finished(result: Dictionary):
    run_data["body_hp"] = result["body_hp"]
    if result["outcome"] == "lose":
        run_data["phase"] = "lose"
    else:
        var node = get_current_node()
        if node.get("type") == "boss":
            run_data["phase"] = "victory"
        else:
            run_data["phase"] = "reward"
    state_changed.emit()

# --- 전투 시작 (5단계에서 BattleManager.begin_battle 로 교체 예정) ---

func start_combat():
    # TODO(5단계): BattleManager.begin_battle(current_floor) 로 교체
    run_data["phase"] = "combat"
    state_changed.emit()

# --- 거점 (임시수리) ---

func rest_heal_hp():
    run_data["body_hp"] = min(run_data["body_hp"] + 15, run_data["body_max_hp"])
    run_data["phase"] = "map"
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
