extends Node2D

signal state_changed

var run_data: Dictionary = {}

func _ready() -> void:
    # 런은 GameManager.start_run() 이 호출하는 init_run() 으로 개시된다.
    # 부팅 시점의 run_data 는 비어있고, 타이틀 상태는 GameManager 가 관리한다.
    pass

# GameManager.start_run() 이 호출한다.
# ============================================================
# ArmInstance 스키마 — GameData.ARM_MODULES 템플릿의 복제본 + 런타임 상태.
# 각 팔은 장비 아이템 인스턴스로 취급되며 고유 instance_id 로 식별.
#
# {
#     "instance_id": int,          # 순차 증가 고유 ID (UI 노출 안 됨)
#     "template_id": String,       # GameData.ARM_MODULES 의 키 (유래 추적용)
#     "name": String,              # 템플릿에서 복제
#     "slot_type": String,         # "left_arm" | "right_arm" | "any"
#     "max_hp": int,               # 템플릿에서 복제
#     "hp": int,                   # 런타임 상태. 초기값 = max_hp
#     "card_ids": Array,           # 템플릿에서 복제 (개별 수정 가능)
#     "degradation": Dictionary,   # 템플릿에서 복제
# }
#
# 저장 위치: run_data["arm_instances"][instance_id] = ArmInstance
# 장비 여부: run_data["equipped_arms"]["L"|"R"] 에 instance_id 가 있으면 장착 중.
#           null 이면 빈 슬롯.
# ============================================================

func init_run():
    var body_max: int = GameData.INITIAL_BODY.max_hp
    run_data = {
        "phase": "map",
        "body_hp": body_max,
        "body_max_hp": body_max,

        # 팔 인스턴스 데이터베이스
        "arm_instances": {},                            # { instance_id: ArmInstance }
        "equipped_arms": { "L": null, "R": null },     # instance_id 또는 null (빈 슬롯 허용)
        "next_arm_instance_id": 1,                      # 순차 증가 ID 발급용
        "arm_inventory_max": 6,                         # 스페어(비장착) 최대 보관 개수

        "current_floor": 1,
        "map": _generate_map(),
        "current_node_id": -1,
    }
    _setup_initial_arms()
    state_changed.emit()

# GameManager.return_to_title() 이 호출한다.
func reset() -> void:
    run_data = {}
    state_changed.emit()

# --- 초기 팔 구성 ---------------------------------------------------------
# 좌·우 슬롯에 원본 팔 2개 장착, 스페어로 열화 팔 1개.

func _setup_initial_arms() -> void:
    var l_id: int = _create_arm_instance("left_arm_module")
    var r_id: int = _create_arm_instance("right_arm_module")
    _equip_arm("L", l_id)
    _equip_arm("R", r_id)
    _create_arm_instance("degraded_arm_module")  # 스페어 (비장착)

# --- 팔 인스턴스 생성자 -------------------------------------------------------
# 템플릿 복제 + ID 할당 + arm_instances 데이터베이스에 등록.
# 반환: 생성된 instance_id.

func _create_arm_instance(template_id: String) -> int:
    var template: Dictionary = GameData.ARM_MODULES[template_id]
    var id: int = run_data["next_arm_instance_id"]
    run_data["next_arm_instance_id"] = id + 1
    run_data["arm_instances"][id] = {
        "instance_id": id,
        "template_id": template_id,
        "name": template.name,
        "slot_type": template.slot_type,
        "max_hp": template.max_hp,
        "hp": template.max_hp,
        "card_ids": template.card_ids.duplicate(),
        "degradation": template.degradation.duplicate(true),
    }
    return id

# --- 장비 슬롯 할당 ---------------------------------------------------------

# 내부용 (init 중 state_changed 를 따로 안 발신).
func _equip_arm(side: String, instance_id: int) -> void:
    run_data["equipped_arms"][side] = instance_id

# 공용 장착 함수.
# - side: "L" | "R"
# - instance_id: run_data["arm_instances"] 에 등록된 팔의 ID
#
# 검사:
#   1) 인스턴스가 실제로 존재하는가
#   2) 인스턴스의 slot_type 이 해당 슬롯에 호환되는가
#      ("any" 는 아무 슬롯 가능, 그 외는 슬롯과 일치해야 함)
#
# 부수효과:
#   - 같은 인스턴스가 다른 슬롯에 장착 중이면 먼저 해제
#   - 대상 슬롯에 있던 기존 팔은 자동으로 스페어가 됨 (arm_instances 에 남음)
#   - 성공 시 state_changed 발신
#
# 반환: 장착 성공 여부.
func equip_arm(side: String, instance_id: int) -> bool:
    var instances: Dictionary = run_data.get("arm_instances", {})
    if not instances.has(instance_id):
        push_warning("equip_arm: instance_id %d 가 arm_instances 에 없음" % instance_id)
        return false

    var required_slot_type: String = _slot_type_for_side(side)
    if required_slot_type == "":
        push_warning("equip_arm: 알 수 없는 side '%s'" % side)
        return false

    var arm: Dictionary = instances[instance_id]
    var slot_type: String = arm.get("slot_type", "")
    if slot_type != "any" and slot_type != required_slot_type:
        push_warning("equip_arm: slot_type '%s' 는 '%s' 슬롯에 장착 불가" % [slot_type, side])
        return false

    var equipped: Dictionary = run_data["equipped_arms"]
    if equipped.get(side) == instance_id:
        return true  # 이미 장착됨, no-op

    # 같은 인스턴스가 다른 슬롯에 있으면 그 슬롯을 먼저 비움
    for other_side in equipped.keys():
        if other_side != side and equipped[other_side] == instance_id:
            equipped[other_side] = null

    equipped[side] = instance_id
    state_changed.emit()
    return true

func _slot_type_for_side(side: String) -> String:
    match side:
        "L":
            return "left_arm"
        "R":
            return "right_arm"
        _:
            return ""

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
