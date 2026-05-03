extends Node

# I-1 — 인벤토리 자료구조 자동 검증 (RPG 결).
# ITEMS 카탈로그 + 빈 dict 결로 시작 + 시점 복귀.

var _checks: Array = []


func _ready() -> void:
    print("=== I-1 인벤토리 schema (RPG 결) 자동 검증 시작 ===")
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

    # ============================================================
    # ITEMS 카탈로그 정합
    # ============================================================
    ok = _check("GameData.ITEMS 가 Dictionary",
        GameData.ITEMS is Dictionary) and ok
    ok = _check("ITEMS 5 종 (food/repair_kit/rare_part/scanner/key)",
        GameData.ITEMS.has("food")
        and GameData.ITEMS.has("repair_kit")
        and GameData.ITEMS.has("rare_part")
        and GameData.ITEMS.has("scanner")
        and GameData.ITEMS.has("key")) and ok
    ok = _check("repair_kit.name = '응급수리키트'",
        GameData.ITEMS["repair_kit"]["name"] == "응급수리키트") and ok
    ok = _check("repair_kit.use_event_id = 'use_repair_kit'",
        GameData.ITEMS["repair_kit"]["use_event_id"] == "use_repair_kit") and ok
    ok = _check("food.use_event_id = null (자원 결)",
        GameData.ITEMS["food"].get("use_event_id") == null) and ok
    ok = _check("key.scope = 'internal_run'",
        GameData.ITEMS["key"]["scope"] == "internal_run") and ok
    ok = _check("CATEGORY_NAMES 정합",
        GameData.CATEGORY_NAMES.get("consumable") == "소비"
        and GameData.CATEGORY_NAMES.get("material") == "재료"
        and GameData.CATEGORY_NAMES.get("quest") == "퀘스트") and ok

    # ============================================================
    # big_run_data["inventory"] = 빈 dict 결
    # ============================================================
    GameManager.start_run()
    await get_tree().process_frame
    await _consume_dialogues()

    ok = _check("big_run_data['inventory'] 박힘",
        RunManager.big_run_data.has("inventory")) and ok
    ok = _check("big_run_data['inventory'] = {} (빈 dict)",
        RunManager.big_run_data["inventory"].is_empty()) and ok

    # ============================================================
    # run_data["inventory"] / ["tools"]
    # ============================================================
    ok = _check("run_data['inventory'] 박힘",
        RunManager.run_data.has("inventory")) and ok
    ok = _check("run_data['inventory'] = {} (big 의 빈 사본)",
        RunManager.run_data["inventory"].is_empty()) and ok
    ok = _check("run_data['tools'] 박혔고 빈 dict",
        RunManager.run_data.has("tools") and RunManager.run_data["tools"].is_empty()) and ok

    # ============================================================
    # 회귀 시 시점 복귀 — big 의 사본 결
    # ============================================================
    # 회차 중 inventory 직접 변경 (시뮬)
    RunManager.run_data["inventory"]["food"] = 5
    RunManager.run_data["inventory"]["repair_kit"] = 2
    RunManager.run_data["tools"]["key"] = 1

    # 회귀
    RunManager.run_data["phase"] = "research"
    RunManager.leave_research()
    await get_tree().process_frame
    await _consume_dialogues()

    ok = _check("회귀 후 run_data['inventory'] = {} (시점 복귀, big 빈 결)",
        RunManager.run_data["inventory"].is_empty()) and ok
    ok = _check("회귀 후 run_data['tools'] 빔 (회차 한정)",
        RunManager.run_data["tools"].is_empty()) and ok
    ok = _check("회귀 후에도 big_run_data['inventory'] = {} (변경 X)",
        RunManager.big_run_data["inventory"].is_empty()) and ok

    return ok
