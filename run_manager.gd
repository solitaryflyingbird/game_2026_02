extends Node2D

signal state_changed
signal internal_run_ended(result: String)
signal internal_run_started

# 큰 런 마스터 데이터. 세이브/로드 대상. run_data 와 동일 스키마.
var big_run_data: Dictionary = {}
# 현재 내부 런 작업 사본. big_run_data.duplicate(true) 로 생성.
var run_data: Dictionary = {}

func _ready() -> void:
    BattleManager.battle_ended.connect(_on_battle_ended)
    _register_console_commands()

# GameManager.start_run() 이 호출한다.
func init_run():
    _new_big_run()
    _start_internal_run()


# --- 큰 런 초기화 (새 게임·로드 시 1회) -----------------------------------

func _new_big_run() -> void:
    var body_max: int = GameData.INITIAL_BODY.max_hp
    big_run_data = {
        "phase": "map",

        # 히로인 상태
        "body_hp": body_max,
        "body_max_hp": body_max,

        # 팔 인스턴스 데이터베이스
        "arm_instances": {},
        "equipped_arms": { "L": null, "R": null },
        "next_arm_instance_id": 1,
        "arm_inventory_max": 6,

        # 맵 그래프. big 쪽 맵은 _start_internal_run 에서 어차피 덮어씌워지지만
        # 스키마 일관성을 위해 여기서도 초기화해둔다.
        "map": _build_initial_map(),
        "current_node_id": 1,

        # 큰 런 메타. 회귀 횟수 등 내부 런 경계를 넘어 지속되는 상태.
        "meta": {
            "big_run_count": 0,
        },

        # 화폐 — 적 처치 드롭 누적. 회귀 시 유지, reset() 시 소멸.
        "research_data": 0,
    }
    _setup_initial_arms_in(big_run_data)


# --- 내부 런 시작 (큰 런 진입 직후·매 내부 런 종료 후) ----------------------

func _start_internal_run() -> void:
    run_data = big_run_data.duplicate(true)
    # 맵·현재 노드는 내부 런 고유. 복제 후 덮어쓴다.
    run_data["map"] = _build_initial_map()
    run_data["current_node_id"] = 1
    run_data["phase"] = "map"
    if run_data["map"].has(run_data["current_node_id"]):
        run_data["map"][run_data["current_node_id"]]["visited"] = true
    state_changed.emit()


# GameManager.return_to_title() 이 호출한다.
func reset() -> void:
    big_run_data = {}
    run_data = {}
    state_changed.emit()


# --- 초기 팔 구성 ---------------------------------------------------------

func _setup_initial_arms_in(target: Dictionary) -> void:
    var l_id: int = _create_arm_instance_in(target, "left_arm_module")
    var r_id: int = _create_arm_instance_in(target, "right_arm_module")
    _equip_arm_in(target, "L", l_id)
    _equip_arm_in(target, "R", r_id)
    _create_arm_instance_in(target, "degraded_arm_module")  # 스페어


# --- 카드 / 팔 인스턴스 생성자 ----------------------------------------------

# 카드 모델의 원자 단위. CARD_TEMPLATES 의 한 항목을 deep copy 하고 id 키를 박아둠.
# 팔의 카드 배열 외에도 향후 보상·이벤트·인벤토리 등 다른 출처에서도 동일하게 호출.
func _build_card(card_id: String) -> Dictionary:
    var def: Dictionary = GameData.CARD_TEMPLATES[card_id].duplicate(true)
    def["id"] = card_id
    return def


func _create_arm_instance_in(target: Dictionary, template_id: String) -> int:
    var template: Dictionary = GameData.ARM_MODULES[template_id]
    var id: int = target["next_arm_instance_id"]
    target["next_arm_instance_id"] = id + 1
    var cards: Array = []
    for cid in template.card_ids:
        cards.append(_build_card(cid))
    target["arm_instances"][id] = {
        "instance_id": id,
        "template_id": template_id,
        "name": template.name,
        "slot_type": template.slot_type,
        "max_hp": template.max_hp,
        "hp": template.max_hp,
        "cards": cards,
        "degradation": template.degradation.duplicate(true),
        # 주인공의 연구 (arm_attack_boost) 로 누적되는 항구적 공격력 보너스.
        # ※ Step 2 에서 cards[*].effects[*].value 직접 변경으로 환원하면서 제거 예정.
        "attack_bonus": 0,
    }
    return id


# --- 장비 슬롯 ------------------------------------------------------------

# 내부용 (init 중 state_changed 따로 안 발신).
func _equip_arm_in(target: Dictionary, side: String, instance_id: int) -> void:
    target["equipped_arms"][side] = instance_id


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

# BattleManager.battle_ended 시그널의 유일한 수신 진입점. run_data 의
# body_hp·팔 인스턴스·phase 갱신을 전부 여기서 수행. result 스키마:
#   { "result": "victory" | "defeat",
#     "body_hp": int,
#     "arm_l": {"instance_id": int, "hp": int} | null,
#     "arm_r": {"instance_id": int, "hp": int} | null }
func _on_battle_ended(result: Dictionary) -> void:
    run_data["body_hp"] = result.get("body_hp", run_data.get("body_hp", 0))
    _apply_arm_result("L", result.get("arm_l"))
    _apply_arm_result("R", result.get("arm_r"))

    if result.get("result") == "defeat":
        run_data["phase"] = "lose"
    else:
        # 승리 — 드롭 가산
        big_run_data["research_data"] += result.get("drop", 0)
        # 현재 노드의 적 제거
        var current_id = run_data.get("current_node_id")
        if current_id != null and run_data.get("map", {}).has(current_id):
            run_data["map"][current_id]["enemy_id"] = null
        run_data["phase"] = "reward"

    state_changed.emit()


func _apply_arm_result(side: String, arm_result) -> void:
    if arm_result == null:
        return
    var id: int = arm_result["instance_id"]
    var hp: int = arm_result["hp"]
    var instances: Dictionary = run_data["arm_instances"]
    var equipped: Dictionary = run_data["equipped_arms"]
    # HP 0 → 인스턴스 삭제 + 슬롯 해제. 살아있으면 hp 갱신만.
    if hp <= 0:
        instances.erase(id)
        equipped[side] = null
    elif instances.has(id):
        instances[id]["hp"] = hp


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
# 이동 후 대상 노드에 enemy_id 가 있으면 phase 를 "battle_preview" 로 전환.
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

    # 연구 노드 진입 — 회귀 직전 주인공의 연구 페이즈로 전환.
    # phase = "research", run_data["research_offers"] 에 무작위 2개 옵션 생성.
    # (휴면 중인 type "boss" 는 진 엔딩 결전 도입 시 부활 — 별도 분기로 갈 예정.)
    if target.get("type") == "research":
        _enter_research()
        return true

    # 적이 점거한 노드면 전투 프리뷰로 전환
    if target.get("enemy_id") != null:
        run_data["phase"] = "battle_preview"

    state_changed.emit()
    return true


# --- 전투 진입 (battle_preview 에서 "전투 시작" 버튼이 호출) ---

func start_combat() -> void:
    var current: Dictionary = get_current_node()
    var enemy_id = current.get("enemy_id")
    if enemy_id == null:
        push_warning("start_combat: 현재 노드에 enemy_id 없음")
        return
    BattleManager.begin_battle({
        "enemy_id": enemy_id,
        "body_hp": run_data["body_hp"],
        "body_max_hp": run_data["body_max_hp"],
        "arm_l": get_equipped_arm("L"),
        "arm_r": get_equipped_arm("R"),
    })
    run_data["phase"] = "combat"
    state_changed.emit()


# --- 맵으로 복귀 (reward 에서 "맵으로" 버튼이 호출) ---

func return_to_map() -> void:
    run_data["phase"] = "map"
    state_changed.emit()


# ============================================================
# 주인공의 연구 (회귀 직전 강화 페이즈)
# ============================================================
# 풀: GameData.RESEARCH_OPTIONS (3종)
# 진입: move_to_node 가 type "research" 노드에서 호출
# 흐름: _enter_research → (UI 가 purchase 호출 0~2회) → leave_research → 회귀
# 영속 상태 변경 단일 출처는 RunManager. UI 는 명령만 보냄.

func _enter_research() -> void:
    run_data["research_offers"] = _generate_research_offers()
    run_data["phase"] = "research"
    state_changed.emit()


# RESEARCH_OPTIONS 키를 셔플해 앞 2개를 ResearchOfferEntry 로 포장.
# 동일 옵션 중복 없음. 풀 크기가 2 미만이면 가능한 만큼만 반환.
func _generate_research_offers() -> Array:
    var ids: Array = GameData.RESEARCH_OPTIONS.keys()
    ids.shuffle()
    var picks: Array = ids.slice(0, 2)
    var result: Array = []
    for id in picks:
        var opt: Dictionary = GameData.RESEARCH_OPTIONS[id]
        result.append({
            "item_id": id,
            "price": opt.get("base_price", 0),
            "applied": false,
        })
    return result


# 연구 종료 → 회귀. 옵션 적용 여부와 무관하게 호출 가능.
func leave_research() -> void:
    if run_data.get("phase") != "research":
        push_warning("leave_research: phase != 'research' (현재: %s)" % run_data.get("phase"))
        return
    end_internal_run("cleared")


# 연구 옵션 적용 시도. 성공 시 효과 적용 + 잔액 차감 + applied = true + emit.
# 실패 조건: phase 불일치 / idx 범위 밖 / 이미 applied / 잔액 부족 / item_id 미정의 /
# 효과 적용 실패. 어느 단계든 실패 시 잔액·applied 무변.
func purchase(offer_idx: int) -> bool:
    if run_data.get("phase") != "research":
        push_warning("purchase: phase != 'research' (현재: %s)" % run_data.get("phase"))
        return false
    var offers: Array = run_data.get("research_offers", [])
    if offer_idx < 0 or offer_idx >= offers.size():
        push_warning("purchase: offer_idx %d 범위 밖 (size %d)" % [offer_idx, offers.size()])
        return false
    var entry: Dictionary = offers[offer_idx]
    if entry.get("applied", false):
        return false
    var price: int = entry.get("price", 0)
    if big_run_data.get("research_data", 0) < price:
        return false
    var option: Dictionary = GameData.RESEARCH_OPTIONS.get(entry.get("item_id", ""), {})
    if option.is_empty():
        push_warning("purchase: 알 수 없는 item_id '%s'" % entry.get("item_id"))
        return false

    if not _apply_research_effect(option):
        return false

    big_run_data["research_data"] -= price
    entry["applied"] = true
    state_changed.emit()
    return true


# 효과 타입 디스패처. 새 효과 추가 시 여기에 분기 한 줄 + _apply_<type> 함수 추가.
func _apply_research_effect(option: Dictionary) -> bool:
    match option.get("type", ""):
        "body_boost":
            return _apply_body_boost(option.get("params", {}))
        "arm_attack_boost":
            return _apply_arm_attack_boost(option.get("params", {}))
        "arm_durability_boost":
            return _apply_arm_durability_boost(option.get("params", {}))
        _:
            push_warning("_apply_research_effect: 알 수 없는 type '%s'" % option.get("type"))
            return false


# 영속 상태 변경 단일 출처. big_run_data 가 회귀를 통과하는 진짜 저장소,
# run_data 측은 UI 즉시 반영을 위한 동기 사본 (회귀 시 어차피 _start_internal_run 이
# duplicate(true) 로 다시 빌드).

func _apply_body_boost(params: Dictionary) -> bool:
    var amount: int = params.get("amount", 0)
    big_run_data["body_max_hp"] = big_run_data.get("body_max_hp", 0) + amount
    big_run_data["body_hp"] = big_run_data.get("body_hp", 0) + amount
    run_data["body_max_hp"] = run_data.get("body_max_hp", 0) + amount
    run_data["body_hp"] = run_data.get("body_hp", 0) + amount
    return true


# 보유한 모든 팔 인스턴스(L·R 장착 + 스페어) 의 attack_bonus 일괄 += amount.
# 새로 획득되는 팔은 이 보너스를 받지 않음 (각자 따로 연구 필요).
func _apply_arm_attack_boost(params: Dictionary) -> bool:
    var amount: int = params.get("amount", 1)
    for arm in big_run_data.get("arm_instances", {}).values():
        arm["attack_bonus"] = arm.get("attack_bonus", 0) + amount
    for arm in run_data.get("arm_instances", {}).values():
        arm["attack_bonus"] = arm.get("attack_bonus", 0) + amount
    return true


# 보유한 모든 팔 인스턴스의 max_hp / hp 일괄 += amount. 현재 HP 도 함께 증가
# (회복 효과 겸함). 회귀 후엔 어차피 max_hp 까지 채워서 시작하므로 hp 증가는
# 본 페이즈 화면에서의 시각 정합용.
func _apply_arm_durability_boost(params: Dictionary) -> bool:
    var amount: int = params.get("amount", 0)
    for arm in big_run_data.get("arm_instances", {}).values():
        arm["max_hp"] = arm.get("max_hp", 0) + amount
        arm["hp"] = arm.get("hp", 0) + amount
    for arm in run_data.get("arm_instances", {}).values():
        arm["max_hp"] = arm.get("max_hp", 0) + amount
        arm["hp"] = arm.get("hp", 0) + amount
    return true


# ============================================================
# 내부 런 종료 · 역류
# ============================================================

# 내부 런 종료. 덱·장착 상태를 big_run_data 로 역류시킨 뒤 새 내부 런 시작.
# 전투 중 호출 금지 — battle_manager 가 battle_state 참조 상태이므로 먼저 종료 필요.
func end_internal_run(result: String) -> void:
    if run_data.get("phase") == "combat":
        push_warning("end_internal_run: 전투 중 회귀 불가. 먼저 전투를 종료하세요.")
        return
    if big_run_data.is_empty():
        push_warning("end_internal_run: big_run_data 없음 (런이 시작되지 않음)")
        return

    # 역류: 각 팔 인스턴스의 cards (같은 instance_id 기준 매칭).
    # cards 는 dict 배열이므로 deep duplicate.
    var run_arms: Dictionary = run_data.get("arm_instances", {})
    var big_arms: Dictionary = big_run_data["arm_instances"]
    for id in run_arms.keys():
        if big_arms.has(id):
            big_arms[id]["cards"] = run_arms[id]["cards"].duplicate(true)

    # 역류: 장착 상태
    big_run_data["equipped_arms"] = run_data.get("equipped_arms", {}).duplicate()

    # 메타 갱신
    big_run_data["meta"]["big_run_count"] = big_run_data["meta"].get("big_run_count", 0) + 1

    run_data = {}
    internal_run_ended.emit(result)
    _start_internal_run()
    internal_run_started.emit()


# --- 변경자 — 덱 조작 (디버그·보상 공용) --------------------------------

func upgrade_card(instance_id: int, index: int, new_card_id: String) -> bool:
    var instances: Dictionary = run_data.get("arm_instances", {})
    if not instances.has(instance_id):
        push_warning("upgrade_card: instance_id %d 없음" % instance_id)
        return false
    var cards: Array = instances[instance_id]["cards"]
    if index < 0 or index >= cards.size():
        push_warning("upgrade_card: index %d 범위 밖 (크기 %d)" % [index, cards.size()])
        return false
    if not GameData.CARD_TEMPLATES.has(new_card_id):
        push_warning("upgrade_card: 알 수 없는 card_id '%s'" % new_card_id)
        return false
    cards[index] = _build_card(new_card_id)
    state_changed.emit()
    return true


# ============================================================
# LimboConsole 명령
# ============================================================

func _register_console_commands() -> void:
    LimboConsole.register_command(_cmd_show_run, "show_run", "현재 내부 런 덤프")
    LimboConsole.register_command(_cmd_show_big_run, "show_big_run", "큰 런 (big_run_data) 덤프")
    LimboConsole.register_command(_cmd_end_run, "end_run", "내부 런 강제 종료. 인자: failed|cleared")
    LimboConsole.register_command(_cmd_upgrade_card, "upgrade_card",
        "팔 카드 교체. 인자: <instance_id> <index> <card_id>")
    LimboConsole.register_command(_cmd_leave_research, "leave_research", "연구 페이즈 종료 (회귀)")
    LimboConsole.register_command(_cmd_purchase, "purchase", "연구 옵션 적용. 인자: <offer_idx>")


func _cmd_show_run() -> void:
    LimboConsole.info(JSON.stringify(run_data, "  "))


func _cmd_show_big_run() -> void:
    LimboConsole.info(JSON.stringify(big_run_data, "  "))


func _cmd_end_run(result: String = "failed") -> void:
    end_internal_run(result)
    LimboConsole.info("end_internal_run(%s) 완료. big_run_count=%d" % [
        result, big_run_data["meta"]["big_run_count"]])


func _cmd_upgrade_card(instance_id: int, index: int, card_id: String) -> void:
    if upgrade_card(instance_id, index, card_id):
        LimboConsole.info("upgrade_card: 성공")
    else:
        LimboConsole.error("upgrade_card: 실패 (경고 로그 확인)")


func _cmd_leave_research() -> void:
    leave_research()


func _cmd_purchase(idx: int) -> void:
    if purchase(idx):
        LimboConsole.info("purchase(%d): 성공" % idx)
    else:
        LimboConsole.error("purchase(%d): 실패 (경고 로그 확인)" % idx)
