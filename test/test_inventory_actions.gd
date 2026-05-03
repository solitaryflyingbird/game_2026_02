extends Node

# I-2 — 인벤토리 helper 자동 검증.
# _inventory_for_scope / add_item / _consume_item / use_item.
# 0 도달 시 erase (RPG 결의 핵심) 검증.
# use_item 의 정상 발화 결은 I-3 후 (use_repair_kit 박힌 후).

var _checks: Array = []


func _ready() -> void:
    print("=== I-2 인벤토리 actions 자동 검증 시작 ===")
    var ok := await _run_scenario()
    _print_summary()
    if ok:
        print("=== PASS ===")
        get_tree().quit(0)
    else:
        push_error("=== FAIL ===")
        get_tree().quit(1)


func _check(name: String, ok: bool, detail: String = "") -> bool:
    _checks.append({"name": name, "ok": ok, "detail": detail})
    if ok:
        print("[PASS] %s" % name)
    else:
        push_error("[FAIL] %s — %s" % [name, detail])
    return ok


func _print_summary() -> void:
    var p := 0
    var f := 0
    for c in _checks:
        if c.ok:
            p += 1
        else:
            f += 1
    print("---")
    print("총 %d 검증 — PASS %d / FAIL %d" % [_checks.size(), p, f])


func _consume_dialogues() -> void:
    while not EventManager.event_state.is_empty() and \
            EventManager.event_state.get("kind") == "dialogue":
        EventManager.advance_line()
    await get_tree().process_frame


func _run_scenario() -> bool:
    var ok := true

    GameManager.start_run()
    await get_tree().process_frame
    await _consume_dialogues()

    # ============================================================
    # _inventory_for_scope 분기
    # ============================================================
    var big_inv: Dictionary = RunManager._inventory_for_scope("big_run_default")
    var tools: Dictionary = RunManager._inventory_for_scope("internal_run")
    ok = _check("_inventory_for_scope('big_run_default') = run_data['inventory']",
        big_inv == RunManager.run_data["inventory"]) and ok
    ok = _check("_inventory_for_scope('internal_run') = run_data['tools']",
        tools == RunManager.run_data["tools"]) and ok

    # ============================================================
    # add_item — RPG 결로 카탈로그의 어떤 아이템이든 추가 가능
    # ============================================================
    ok = _check("초기 inventory 빈 dict",
        RunManager.run_data["inventory"].is_empty()) and ok

    var ok_food: bool = RunManager.add_item("food", 3)
    ok = _check("add_item('food', 3) = true", ok_food) and ok
    ok = _check("food 키 박힘 (count = 3)",
        RunManager.run_data["inventory"].get("food") == 3) and ok

    RunManager.add_item("repair_kit", 1)
    ok = _check("add_item('repair_kit', 1) — 다른 결도 자유 추가",
        RunManager.run_data["inventory"].get("repair_kit") == 1) and ok

    # stack_max cap (food stack_max = 99)
    RunManager.add_item("food", 200)
    ok = _check("food stack_max cap = 99",
        RunManager.run_data["inventory"]["food"] == 99) and ok

    # 알 수 없는 item_id → false (카탈로그에 없음)
    var ok_bad: bool = RunManager.add_item("unknown_item", 1)
    ok = _check("카탈로그에 없는 id 거부 → false", not ok_bad) and ok
    ok = _check("거부 후 unknown_item 박히지 않음",
        not RunManager.run_data["inventory"].has("unknown_item")) and ok

    # 회차 한정 (key) — tools 결로
    var ok_key: bool = RunManager.add_item("key", 2)
    ok = _check("add_item('key', 2) = true (internal_run scope)", ok_key) and ok
    ok = _check("tools['key'] = 2",
        RunManager.run_data["tools"].get("key") == 2) and ok
    ok = _check("inventory 에는 key 박히지 않음 (scope 분기)",
        not RunManager.run_data["inventory"].has("key")) and ok

    # ============================================================
    # _consume_item — 0 도달 시 erase (RPG 결의 핵심)
    # ============================================================
    var ok_cons: bool = RunManager._consume_item("repair_kit", 1)
    ok = _check("_consume_item('repair_kit', 1) = true", ok_cons) and ok
    ok = _check("repair_kit 0 도달 시 erase (키 자체 X)",
        not RunManager.run_data["inventory"].has("repair_kit")) and ok

    # 부족 시 false
    var ok_short: bool = RunManager._consume_item("repair_kit", 1)
    ok = _check("repair_kit 보유 0 → _consume_item false", not ok_short) and ok

    # 정상 -= (전체 소모 X)
    RunManager._consume_item("food", 5)
    ok = _check("food -= 5 (정상 결로 -=, 0 도달 X)",
        RunManager.run_data["inventory"]["food"] == 94) and ok

    # ============================================================
    # use_item — 거부 결 (정상 발화는 I-3 후)
    # ============================================================
    # use_event_id null (food) → 거부
    var ok_food_use: bool = RunManager.use_item("food")
    ok = _check("use_item('food') = false (use_event_id null)",
        not ok_food_use) and ok

    # 정의 X → 거부
    var ok_unknown_use: bool = RunManager.use_item("unknown_item")
    ok = _check("use_item('unknown') = false", not ok_unknown_use) and ok

    # 보유 0 → 거부 (repair_kit 0 일 때 사용)
    var ok_zero_use: bool = RunManager.use_item("repair_kit")
    ok = _check("use_item('repair_kit') = false (보유 0)", not ok_zero_use) and ok

    # phase != "map" 시 거부
    RunManager.add_item("repair_kit", 1)
    RunManager.run_data["phase"] = "event"
    var ok_phase_use: bool = RunManager.use_item("repair_kit")
    ok = _check("use_item('repair_kit') = false (phase != map)",
        not ok_phase_use) and ok
    ok = _check("phase != map 거부 시 repair_kit 변경 X",
        RunManager.run_data["inventory"]["repair_kit"] == 1) and ok
    RunManager.run_data["phase"] = "map"

    # ============================================================
    # I-3 — effect type
    # ============================================================
    # heal_body — body_hp += amount (max cap)
    RunManager.run_data["body_hp"] = 100
    RunManager.run_data["body_max_hp"] = 150
    RunManager.apply_event_action({"type": "heal_body", "params": {"amount": 25}})
    ok = _check("heal_body — body_hp 100+25 = 125",
        RunManager.run_data["body_hp"] == 125) and ok

    RunManager.apply_event_action({"type": "heal_body", "params": {"amount": 100}})
    ok = _check("heal_body — max cap (150)",
        RunManager.run_data["body_hp"] == 150) and ok

    # give_item / remove_item
    RunManager.apply_event_action({"type": "give_item", "params": {"item": "rare_part", "amount": 3}})
    ok = _check("give_item rare_part +3",
        RunManager.run_data["inventory"].get("rare_part") == 3) and ok

    RunManager.apply_event_action({"type": "remove_item", "params": {"item": "rare_part", "amount": 1}})
    ok = _check("remove_item rare_part -1 → 2",
        RunManager.run_data["inventory"].get("rare_part") == 2) and ok

    # bump_initial_item — big_run_data["inventory"] 변경
    var big_food_before: int = RunManager.big_run_data["inventory"].get("food", 0)
    RunManager.apply_event_action({"type": "bump_initial_item", "params": {"item": "food", "amount": 2}})
    ok = _check("bump_initial_item food +2 → big +2",
        RunManager.big_run_data["inventory"].get("food", 0) == big_food_before + 2) and ok

    # 회귀 시 새 초기치 반영
    RunManager.run_data["phase"] = "research"
    RunManager.leave_research()
    await get_tree().process_frame
    await _consume_dialogues()
    ok = _check("회귀 후 run[food] = 새 초기치 (= big +2)",
        RunManager.run_data["inventory"].get("food", 0) == big_food_before + 2) and ok

    # ============================================================
    # use_item 정상 발화 — use_repair_kit
    # ============================================================
    RunManager.run_data["body_hp"] = 100
    RunManager.run_data["body_max_hp"] = 150
    RunManager.add_item("repair_kit", 1)
    var ok_use_kit: bool = RunManager.use_item("repair_kit")
    ok = _check("use_item('repair_kit') = true (보유 1, phase=map)", ok_use_kit) and ok
    await get_tree().process_frame
    ok = _check("use_repair_kit 종료 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok
    ok = _check("use_repair_kit 효과 — body_hp 100+25 = 125",
        RunManager.run_data["body_hp"] == 125) and ok
    ok = _check("use_repair_kit 후 repair_kit 0 도달 → erase",
        not RunManager.run_data["inventory"].has("repair_kit")) and ok

    # use_scanner — dialogue kind
    RunManager.add_item("scanner", 1)
    var ok_use_scanner: bool = RunManager.use_item("scanner")
    ok = _check("use_item('scanner') = true", ok_use_scanner) and ok
    ok = _check("use_scanner 발화 — phase = 'event' / dialogue kind",
        RunManager.run_data.get("phase") == "event"
        and EventManager.event_state.get("kind") == "dialogue") and ok
    EventManager.advance_line()
    await get_tree().process_frame
    ok = _check("use_scanner 종료 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok
    ok = _check("use_scanner 후 scanner 0 도달 → erase",
        not RunManager.run_data["inventory"].has("scanner")) and ok

    return ok
