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
    EventManager.event_resolved.connect(_on_event_resolved)
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

        # 큰 런 메타. 회귀 횟수 등 내부 런 경계를 넘어 지속되는 상태.
        "meta": {
            "big_run_count": 0,
        },

        # 화폐 — 적 처치 드롭 누적. 회귀 시 유지, reset() 시 소멸.
        "research_data": 0,

        # 이벤트 발생 이력. 키 = event_id (또는 chain_root_id), 값 = 발생 횟수.
        # once_per "big_run" 필터의 단일 출처. 회귀 통과해 유지, reset() 시 소멸.
        "seen_events": {},

        # 인벤토리 초기치. 회차 동안 X 변경 (RESEARCH 의 bump_initial_item 만 변경).
        # _start_internal_run 결로 매 회차 시작 시 run["inventory"] 가 본 결의 사본 결.
        # RPG 결로 빈 dict 결로 시작 — 게임 진행 결로 add_item 결로 박힘.
        "inventory": {},
    }
    _setup_initial_arms_in(big_run_data)


# --- 내부 런 시작 (큰 런 진입 직후·매 내부 런 종료 후) ----------------------

func _start_internal_run() -> void:
    run_data = big_run_data.duplicate(true)
    # 그리드 회차 상태는 내부 런 고유. 복제 후 덮어쓴다.
    var start_map: String = GameData.STARTING_MAP
    var spawn: Vector2i = GameData.MAPS[start_map]["spawn"]
    run_data["current_map_id"] = start_map
    run_data["player_pos"] = spawn
    run_data["day"] = 1
    run_data["day_max"] = GameData.DAY_MAX
    run_data["actions_per_day"] = GameData.ACTIONS_PER_DAY
    run_data["actions_remaining"] = GameData.ACTIONS_PER_DAY
    run_data["visited_by_map"] = { start_map: { spawn: true } }
    run_data["explored_by_map"] = { start_map: {} }
    run_data["seen_this_run"] = {}
    run_data["pending_combat"] = {}
    run_data["phase"] = "map"
    # 자원 시점 복귀 — big_run_data["inventory"] 의 사본 결.
    run_data["inventory"] = big_run_data.get("inventory", {}).duplicate()
    # 회차 한정 자원 — 매 회차 빔.
    run_data["tools"] = {}

    state_changed.emit()
    # run_start 트리거 평가 — 매치 시 phase = "event" 전이.
    var run_start_event_id: String = EventManager.resolve_event("run_start", {})
    if run_start_event_id != "":
        _begin_event_phase(run_start_event_id)


# 이벤트 진입 — phase 전이 + EventManager 위임 + state_changed.
# 타일 슬롯 / run_start / on_rest 트리거 공용.
func _begin_event_phase(event_id: String) -> void:
    run_data["phase"] = "event"
    EventManager.begin_event(event_id, {})
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
        # 승리 — 드롭 가산 + 조우 슬롯 소비 기록 (once_per: internal_run).
        big_run_data["research_data"] += result.get("drop", 0)
        var pending: Dictionary = run_data.get("pending_combat", {})
        var encounter_id: String = pending.get("encounter_id", "")
        if encounter_id != "":
            run_data["seen_this_run"][encounter_id] = true
        run_data["pending_combat"] = {}
        run_data["phase"] = "reward"

    state_changed.emit()


# --- 이벤트 결과 수신 -------------------------------------------------------

# EventManager.event_resolved 시그널의 유일한 수신 진입점.
# seen_events 카운트 갱신 + phase = "map" 복귀.
# result 스키마: { "event_id": String }  — chain_root_id 가 박혀있음 (안 4 §3-3).
func _on_event_resolved(result: Dictionary) -> void:
    var event_id: String = result.get("event_id", "")
    if event_id == "":
        push_warning("_on_event_resolved: 빈 event_id")
        return
    # 큰 런 통계 카운터 — 회귀 통과해 누적.
    var seen: Dictionary = big_run_data.get("seen_events", {})
    seen[event_id] = seen.get(event_id, 0) + 1
    big_run_data["seen_events"] = seen
    # 글로벌 트리거 이벤트가 once_per: "internal_run" 이면 회차 카운터도 박음
    # (resolve_event 가 같은 회차 재발화를 필터). 슬롯 트리거는 _check_on_enter 가
    # 이미 사전에 박았으므로 여기 갱신은 사실상 글로벌 트리거 (run_start / on_rest) 용.
    var def: Dictionary = GameData.EVENTS.get(event_id, {})
    if def.get("once_per", "") == "internal_run":
        run_data.get("seen_this_run", {})[event_id] = true
    # 휴식 중 발화한 이벤트면 종료 후 휴식 마무리.
    if run_data.get("rest_pending", false):
        run_data["rest_pending"] = false
        _finalize_rest()
    else:
        run_data["phase"] = "map"
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
# 그리드 — 지형 / 통과
# ============================================================

func _current_map() -> Dictionary:
    var map_id: String = run_data.get("current_map_id", GameData.STARTING_MAP)
    return GameData.MAPS.get(map_id, {})


func _get_terrain_at(pos: Vector2i) -> String:
    var rows: Array = _current_map().get("terrain", [])
    if pos.y < 0 or pos.y >= rows.size():
        return ""
    var row: String = rows[pos.y]
    if pos.x < 0 or pos.x >= row.length():
        return ""
    return row[pos.x]


func _is_passable(pos: Vector2i) -> bool:
    var t: String = _get_terrain_at(pos)
    if t == "":
        return false
    return GameData.TERRAIN_RULES.get(t, {}).get("passable", false)


# --- 조회자 ---

func get_terrain_name(pos: Vector2i) -> String:
    return GameData.TERRAIN_RULES.get(_get_terrain_at(pos), {}).get("name", "")


func get_tile_encounter(pos: Vector2i) -> Dictionary:
    return _current_map().get("encounters", {}).get(pos, {})


func get_current_map_name() -> String:
    return _current_map().get("name", "")


# 슬롯 once_per 필터. 통과(발화 가능) → true.
func _slot_passes_filters(slot: Dictionary) -> bool:
    var op: String = slot.get("once_per", "")
    if op == "":
        return true
    var key: String = slot.get("id", "")
    if key == "":
        return true
    match op:
        "internal_run":
            return not run_data.get("seen_this_run", {}).get(key, false)
        "big_run":
            return big_run_data.get("seen_events", {}).get(key, 0) <= 0
        _:
            push_warning("_slot_passes_filters: 알 수 없는 once_per '%s'" % op)
            return true


# 진입 슬롯 디스패처. on_enter 슬롯 평가 + 필터 통과 시 kind 별 분기.
func _check_on_enter(pos: Vector2i) -> void:
    var enc: Dictionary = get_tile_encounter(pos)
    if enc.is_empty():
        return
    var slot: Dictionary = enc.get("on_enter", {})
    if slot.is_empty():
        return
    if not _slot_passes_filters(slot):
        return
    var kind: String = slot.get("kind", "")
    match kind:
        "event":
            run_data["seen_this_run"][slot.get("id", "")] = true
            _begin_event_phase(slot.get("event_id", ""))
        "combat":
            run_data["seen_this_run"][slot.get("id", "")] = true
            run_data["pending_combat"] = {
                "enemy_id": slot.get("enemy_id", ""),
                "encounter_id": slot.get("id", ""),
            }
            run_data["phase"] = "battle_preview"
        "research":
            run_data["seen_this_run"][slot.get("id", "")] = true
            _enter_research()
        "transition":
            _do_transition(slot)
        _:
            push_warning("_check_on_enter: 미지원 kind '%s'" % kind)


# 맵 간 전이. 슬롯의 target_map / target_pos 결로 current_map_id + player_pos 갱신.
# 도착지 visited_by_map / explored_by_map 자동 신설.
# 주의: 도착지 슬롯 자동 평가 X — 양 끝의 transition 슬롯끼리 무한 루프 회피.
# 도착지에 event/combat 슬롯이 있어도 발화 X (사용자가 다시 칸 떠나고 돌아와야 발화).
func _do_transition(slot: Dictionary) -> void:
    var target_map: String = slot.get("target_map", "")
    var target_pos: Vector2i = slot.get("target_pos", Vector2i.ZERO)
    if not GameData.MAPS.has(target_map):
        push_warning("_do_transition: 알 수 없는 target_map '%s'" % target_map)
        return
    run_data["seen_this_run"][slot.get("id", "")] = true
    run_data["current_map_id"] = target_map
    run_data["player_pos"] = target_pos
    if not run_data["visited_by_map"].has(target_map):
        run_data["visited_by_map"][target_map] = {}
    if not run_data["explored_by_map"].has(target_map):
        run_data["explored_by_map"][target_map] = {}
    run_data["visited_by_map"][target_map][target_pos] = true


# 탐험 슬롯 디스패처. explore 슬롯 평가 + 필터 통과 시 kind 별 분기.
# 현재는 event kind 만. (탐험 기반 combat / research 도 같은 골격으로 확장 가능.)
func _check_on_explore(pos: Vector2i) -> bool:
    var enc: Dictionary = get_tile_encounter(pos)
    if enc.is_empty():
        return false
    var slot: Dictionary = enc.get("explore", {})
    if slot.is_empty():
        return false
    if not _slot_passes_filters(slot):
        return false
    var kind: String = slot.get("kind", "")
    match kind:
        "event":
            run_data["seen_this_run"][slot.get("id", "")] = true
            _begin_event_phase(slot.get("event_id", ""))
            return true
        _:
            push_warning("_check_on_explore: 미지원 kind '%s'" % kind)
            return false


# --- 행동: 이동 / 탐험 / 휴식 -----------------------------------------------

# 4방향 이동. dir ∈ {(±1,0),(0,±1)}. 통과 가능 + 행동 충분 시 이동.
# 이동 후 on_enter 슬롯 평가. 행동 0 도달 시 자동 휴식.
func try_move(dir: Vector2i) -> bool:
    if run_data.get("phase") != "map":
        return false
    if run_data.get("actions_remaining", 0) < 1:
        return false
    var target: Vector2i = run_data["player_pos"] + dir
    if not _is_passable(target):
        return false

    run_data["player_pos"] = target
    run_data["actions_remaining"] -= 1
    var map_id: String = run_data.get("current_map_id", GameData.STARTING_MAP)
    if not run_data.get("visited_by_map", {}).has(map_id):
        run_data["visited_by_map"][map_id] = {}
    run_data["visited_by_map"][map_id][target] = true

    _check_on_enter(target)

    # 진입 트리거가 phase 를 바꿨으면 그쪽 흐름 우선. map 에 그대로면 0 액션 체크.
    if run_data.get("phase") == "map" and run_data["actions_remaining"] <= 0:
        rest()

    state_changed.emit()
    return true


# 현재 칸 탐험. 같은 회차 1회 한정 (explored_tiles 영속).
func try_explore() -> bool:
    if run_data.get("phase") != "map":
        return false
    if run_data.get("actions_remaining", 0) < 1:
        return false
    var pos: Vector2i = run_data["player_pos"]
    var map_id: String = run_data.get("current_map_id", GameData.STARTING_MAP)
    if not run_data.get("explored_by_map", {}).has(map_id):
        run_data["explored_by_map"][map_id] = {}
    if run_data["explored_by_map"][map_id].get(pos, false):
        return false

    run_data["explored_by_map"][map_id][pos] = true
    run_data["actions_remaining"] -= 1
    _check_on_explore(pos)

    if run_data.get("phase") == "map" and run_data["actions_remaining"] <= 0:
        rest()

    state_changed.emit()
    return true


# 휴식. 어느 칸이든 호출 가능. 일자 +1 + 행동 리셋 + on_rest 이벤트 추첨.
# 이벤트 발화 시 chain 종료 후 _finalize_rest 가 일자/행동 갱신.
func rest() -> void:
    if run_data.get("phase") != "map":
        return
    var rest_event_id: String = EventManager.resolve_event("on_rest", {})
    if rest_event_id != "":
        run_data["rest_pending"] = true
        _begin_event_phase(rest_event_id)
        return
    _finalize_rest()


func _finalize_rest() -> void:
    run_data["day"] = run_data.get("day", 1) + 1
    run_data["actions_remaining"] = run_data.get("actions_per_day", GameData.ACTIONS_PER_DAY)
    run_data["phase"] = "map"
    state_changed.emit()


# --- 전투 진입 (battle_preview 에서 "전투 시작" 버튼이 호출) ---

func start_combat() -> void:
    var pending: Dictionary = run_data.get("pending_combat", {})
    var enemy_id = pending.get("enemy_id", "")
    if enemy_id == "":
        push_warning("start_combat: pending_combat 없음")
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
# 진입: _check_on_enter 의 kind "research" 분기
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


# Type 1 이벤트 액션 디스패처. EventManager._dispatch_effect 가 호출.
# 안 4 §0-E — escape 없음. 신규 효과 = match 분기 + _apply_<type> 신설 강제.
func apply_event_action(action: Dictionary) -> bool:
    var type_name: String = action.get("type", "")
    var params: Dictionary = action.get("params", {})
    match type_name:
        "body_boost":
            return _apply_body_boost(params)
        "arm_attack_boost":
            return _apply_arm_attack_boost(params)
        "arm_durability_boost":
            return _apply_arm_durability_boost(params)
        "heal_body":
            return _apply_heal_body(params)
        "give_item":
            return _apply_give_item(params)
        "remove_item":
            return _apply_remove_item(params)
        "bump_initial_item":
            return _apply_bump_initial_item(params)
        _:
            push_warning("apply_event_action: 알 수 없는 type '%s'" % type_name)
            return false


# 본체 회복. params: { amount }. body_hp += amount, max cap.
func _apply_heal_body(params: Dictionary) -> bool:
    var amount: int = params.get("amount", 0)
    var max_hp: int = run_data.get("body_max_hp", 0)
    run_data["body_hp"] = min(max_hp, run_data.get("body_hp", 0) + amount)
    big_run_data["body_hp"] = run_data["body_hp"]
    return true


# 아이템 획득. params: { item, amount }.
func _apply_give_item(params: Dictionary) -> bool:
    var item_id: String = params.get("item", "")
    var amount: int = params.get("amount", 1)
    return add_item(item_id, amount)


# 아이템 소모. params: { item, amount }.
func _apply_remove_item(params: Dictionary) -> bool:
    var item_id: String = params.get("item", "")
    var amount: int = params.get("amount", 1)
    return _consume_item(item_id, amount)


# RESEARCH 의 초기치 강화. params: { item, amount }.
# big_run_data["inventory"][item] += amount. 다음 회차 _start_internal_run 의
# duplicate 결로 자동 반영.
func _apply_bump_initial_item(params: Dictionary) -> bool:
    var item_id: String = params.get("item", "")
    var amount: int = params.get("amount", 1)
    if not GameData.ITEMS.has(item_id):
        push_warning("_apply_bump_initial_item: 알 수 없는 item '%s'" % item_id)
        return false
    var inv: Dictionary = big_run_data.get("inventory", {})
    inv[item_id] = inv.get(item_id, 0) + amount
    big_run_data["inventory"] = inv
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


# 보유한 모든 팔 인스턴스(L·R 장착 + 스페어) 의 공격 카드 데미지 일괄 += amount.
# arm.cards[*].effects[*] 의 deal_damage value 만 직접 변경.
# 새로 획득되는 팔은 이 강화 미적용 (각자 따로 연구 필요).
func _apply_arm_attack_boost(params: Dictionary) -> bool:
    var amount: int = params.get("amount", 1)
    for arm in big_run_data.get("arm_instances", {}).values():
        _bump_attack_cards(arm.get("cards", []), amount)
    for arm in run_data.get("arm_instances", {}).values():
        _bump_attack_cards(arm.get("cards", []), amount)
    return true


# 카드 배열 안의 deal_damage 효과들에 += amount. damage_own_arm 같은 다른 효과는 제외.
func _bump_attack_cards(cards: Array, amount: int) -> void:
    for card in cards:
        for eff in card.get("effects", []):
            if eff.get("type", "") == "deal_damage":
                eff["value"] = int(eff.get("value", 0)) + amount


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


# ============================================================
# 인벤토리 (자원 / 도구) — RPG 결의 dict 컨테이너
# ============================================================
# 카탈로그 = GameData.ITEMS (정의 결).
# 보유 결 = run_data["inventory"] (시점 복귀) 또는 run_data["tools"] (회차 한정).
# scope 결로 컨테이너 분기.
# count 0 도달 = key 자체 erase (보유 X = 키 없음).

func _inventory_for_scope(scope: String) -> Dictionary:
    match scope:
        "big_run_default":
            if not run_data.has("inventory"): run_data["inventory"] = {}
            return run_data["inventory"]
        "internal_run":
            if not run_data.has("tools"): run_data["tools"] = {}
            return run_data["tools"]
        _:
            push_warning("_inventory_for_scope: 알 수 없는 scope '%s'" % scope)
            return {}


# 카탈로그 결의 어떤 아이템이든 추가 가능. stack_max cap 적용.
# 알 수 없는 item_id (= ITEMS 에 없는) → false.
func add_item(item_id: String, amount: int = 1) -> bool:
    var def: Dictionary = GameData.ITEMS.get(item_id, {})
    if def.is_empty():
        push_warning("add_item: 알 수 없는 item_id '%s'" % item_id)
        return false
    var inv: Dictionary = _inventory_for_scope(def.get("scope", "big_run_default"))
    var stack_max: int = def.get("stack_max", 99)
    inv[item_id] = min(inv.get(item_id, 0) + amount, stack_max)
    state_changed.emit()
    return true


# 부족 시 false (-= X). 0 도달 시 key erase (RPG 결).
func _consume_item(item_id: String, amount: int = 1) -> bool:
    var def: Dictionary = GameData.ITEMS.get(item_id, {})
    if def.is_empty(): return false
    var inv: Dictionary = _inventory_for_scope(def.get("scope", "big_run_default"))
    if inv.get(item_id, 0) < amount: return false
    inv[item_id] -= amount
    if inv[item_id] <= 0:
        inv.erase(item_id)
    return true


# 명시 사용. ITEMS.use_event_id 결로 이벤트 발화 (-1 후).
# phase != "map" / 정의 X / use_event_id null / 보유 0 → false.
func use_item(item_id: String) -> bool:
    if run_data.get("phase") != "map": return false
    var def: Dictionary = GameData.ITEMS.get(item_id, {})
    if def.is_empty(): return false
    var event_id = def.get("use_event_id", null)
    if event_id == null or event_id == "": return false
    if not _consume_item(item_id, 1): return false
    _begin_event_phase(event_id)
    state_changed.emit()
    return true


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
    LimboConsole.register_command(_cmd_move, "move",
        "그리드 이동. 인자: <dx> <dy> (예: move 1 0 = 동쪽)")
    LimboConsole.register_command(_cmd_explore, "explore", "현재 칸 탐험")
    LimboConsole.register_command(_cmd_rest, "rest", "휴식 — 일자 +1, 행동 리셋")


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


func _cmd_move(dx: int, dy: int) -> void:
    if try_move(Vector2i(dx, dy)):
        LimboConsole.info("이동 → %s, 행동 %d" % [
            run_data["player_pos"], run_data["actions_remaining"]])
    else:
        LimboConsole.error("이동 실패")


func _cmd_explore() -> void:
    if try_explore():
        LimboConsole.info("탐험 완료")
    else:
        LimboConsole.error("탐험 실패")


func _cmd_rest() -> void:
    rest()
