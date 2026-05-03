extends Node

# 슬롯 결의 아이템 획득 검증.
# (3, 6) regression_speech → dialogue → regression_grant (effect) → repair_kit +1.

var _checks: Array = []


func _ready() -> void:
    print("=== 슬롯 결 아이템 획득 자동 검증 시작 ===")
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

    # 시작 — inventory 비어있음
    ok = _check("시작 — inventory 비어있음",
        RunManager.run_data["inventory"].is_empty()) and ok

    # field (1,6) → (2,6) → (3,6)
    RunManager.try_move(Vector2i(1, 0))
    RunManager.try_move(Vector2i(1, 0))
    ok = _check("(3,6) 진입 — phase = 'event'",
        RunManager.run_data.get("phase") == "event") and ok
    ok = _check("event_id = 'regression_speech' (chain root)",
        EventManager.event_state.get("event_id") == "regression_speech"
        and EventManager.event_state.get("chain_root_id") == "regression_speech") and ok
    ok = _check("event_state.kind = 'dialogue' (대사 결)",
        EventManager.event_state.get("kind") == "dialogue") and ok

    # advance → chain 진행 → effect 즉시 적용 → chain 종료
    EventManager.advance_line()
    await get_tree().process_frame

    ok = _check("advance 후 chain 종료 — event_state = {}",
        EventManager.event_state.is_empty()) and ok
    ok = _check("chain 종료 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok
    ok = _check("inventory['repair_kit'] = 1 (effect 결로 +1)",
        RunManager.run_data["inventory"].get("repair_kit") == 1) and ok
    ok = _check("seen_events[regression_speech] = 1 (chain root 만)",
        RunManager.big_run_data["seen_events"].get("regression_speech") == 1) and ok
    ok = _check("seen_events[regression_grant] 미존재 (chain 결로 카운트 안 됨)",
        RunManager.big_run_data["seen_events"].get("regression_grant", 0) == 0) and ok

    # 같은 회차 재진입 — once_per: internal_run 결로 미발화
    RunManager.try_move(Vector2i(-1, 0))   # (2,6)
    RunManager.try_move(Vector2i(1, 0))    # (3,6) 재진입
    ok = _check("같은 회차 재진입 — phase = 'map' (미발화)",
        RunManager.run_data.get("phase") == "map") and ok
    ok = _check("재진입 시 inventory['repair_kit'] = 1 그대로 (한 번만 획득)",
        RunManager.run_data["inventory"].get("repair_kit") == 1) and ok

    # 회귀 후 — 시점 복귀 (inventory 빈 결로) + 슬롯 재발화 가능
    RunManager.run_data["phase"] = "research"
    RunManager.leave_research()
    await get_tree().process_frame
    await _consume_dialogues()

    ok = _check("회귀 후 inventory 비어있음 (시점 복귀)",
        RunManager.run_data["inventory"].is_empty()) and ok

    # 회귀 후 (3, 6) 재진입 → 다시 획득
    RunManager.try_move(Vector2i(1, 0))
    RunManager.try_move(Vector2i(1, 0))
    ok = _check("회귀 후 재발화 — phase = 'event'",
        RunManager.run_data.get("phase") == "event") and ok
    EventManager.advance_line()
    await get_tree().process_frame
    ok = _check("회귀 후 다시 repair_kit +1",
        RunManager.run_data["inventory"].get("repair_kit") == 1) and ok

    return ok
