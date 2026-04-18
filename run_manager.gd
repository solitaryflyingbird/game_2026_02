extends Node2D

signal state_changed

var run_data: Dictionary = {}

func _ready() -> void:
    # 런은 GameManager.start_run() 이 호출하는 init_run() 으로 개시된다.
    # 맵 시스템은 레거시 제거됨 — 노드 그래프 기반 재구현 대기 중.
    BattleManager.battle_ended.connect(_on_battle_ended)


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


# GameManager.start_run() 이 호출한다.
func init_run():
    var body_max: int = GameData.INITIAL_BODY.max_hp
    run_data = {
        "phase": "map",

        # 히로인 상태
        "body_hp": body_max,
        "body_max_hp": body_max,

        # 팔 인스턴스 데이터베이스
        "arm_instances": {},
        "equipped_arms": { "L": null, "R": null },
        "next_arm_instance_id": 1,
        "arm_inventory_max": 6,

        # 맵 그래프 (GameData.TEST_MAP_GRAPH 의 인스턴스 복제 + visited 상태)
        "map": _build_initial_map(),
        "current_node_id": 1,   # 시작 노드
    }
    _setup_initial_arms()
    # 시작 노드 방문 처리
    if run_data["map"].has(run_data["current_node_id"]):
        run_data["map"][run_data["current_node_id"]]["visited"] = true
    state_changed.emit()


# GameManager.return_to_title() 이 호출한다.
func reset() -> void:
    run_data = {}
    state_changed.emit()


# --- 초기 팔 구성 ---------------------------------------------------------

func _setup_initial_arms() -> void:
    var l_id: int = _create_arm_instance("left_arm_module")
    var r_id: int = _create_arm_instance("right_arm_module")
    _equip_arm("L", l_id)
    _equip_arm("R", r_id)
    _create_arm_instance("degraded_arm_module")  # 스페어


# --- 팔 인스턴스 생성자 ----------------------------------------------------

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


# --- 장비 슬롯 ------------------------------------------------------------

# 내부용 (init 중 state_changed 따로 안 발신).
func _equip_arm(side: String, instance_id: int) -> void:
    run_data["equipped_arms"][side] = instance_id


# 공용 장착 함수. slot_type 호환 검사 포함.
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
        return true

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


# --- 장착 조회 (BattleManager 가 전투 시작 시 복제용으로 사용) -----------------

func get_equipped_arm(side: String) -> Dictionary:
    var equipped_id = run_data.get("equipped_arms", {}).get(side)
    if equipped_id == null:
        return {}
    return run_data.get("arm_instances", {}).get(equipped_id, {})


# --- 전투 결과 수신 ---------------------------------------------------------
# 맵 재구축 전까지 전투 진입 경로 없음. 훅만 유지해 둠.
# BattleManager 가 body_hp / arm.hp 동기화는 이미 완료.

func _on_battle_ended(result: String) -> void:
    if result == "defeat":
        run_data["phase"] = "lose"
    else:
        run_data["phase"] = "reward"
    state_changed.emit()


# ============================================================
# 맵 그래프
# ============================================================

# 템플릿(GameData.TEST_MAP_GRAPH) 을 깊은 복제하여 런타임 맵 객체로 만든다.
# 각 노드에 visited = false 를 부여.
func _build_initial_map() -> Dictionary:
    var result: Dictionary = {}
    for id in GameData.TEST_MAP_GRAPH.keys():
        var node: Dictionary = GameData.TEST_MAP_GRAPH[id].duplicate(true)
        node["visited"] = false
        result[id] = node
    return result


# --- 조회자 ---

func get_current_node() -> Dictionary:
    var id = run_data.get("current_node_id")
    if id == null:
        return {}
    return run_data.get("map", {}).get(id, {})


func get_node_by_id(id: int) -> Dictionary:
    return run_data.get("map", {}).get(id, {})


# --- 이동 ---

# 현재 노드의 인접(connections) 중 하나로 이동. 유효성 검사 포함.
# 반환: 이동 성공 여부.
func move_to_node(target_id: int) -> bool:
    var current: Dictionary = get_current_node()
    if current.is_empty():
        push_warning("move_to_node: 현재 노드 없음")
        return false

    var connections: Array = current.get("connections", [])
    if target_id not in connections:
        push_warning("move_to_node: %d 는 현재 노드(%d) 의 인접이 아님. 인접: %s" % [
            target_id, current.get("id", -1), connections])
        return false

    run_data["current_node_id"] = target_id
    var target: Dictionary = run_data["map"].get(target_id, {})
    if not target.is_empty():
        target["visited"] = true

    state_changed.emit()
    return true
