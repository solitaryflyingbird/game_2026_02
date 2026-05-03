extends Node

# M-2 — 다중 맵 + transition 시뮬 자동 검증.
# 시나리오: field (1,6) → 동 13칸 → (14,6) 진입 → ruin (0,5) 도착 →
#   ruin 탐색 → ruin (0,5) 재진입 → field (14,6) 복귀 → 회귀 → field 복귀

var _checks: Array = []


func _ready() -> void:
    print("=== M-2 다중 맵 + transition 자동 검증 시작 ===")
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
    # ruin_01 정의 정합 검증
    # ============================================================
    ok = _check("MAPS 에 ruin_01 존재",
        GameData.MAPS.has("ruin_01")) and ok
    var ruin: Dictionary = GameData.MAPS["ruin_01"]
    ok = _check("ruin_01 spawn = (0, 5)",
        ruin["spawn"] == Vector2i(0, 5)) and ok
    ok = _check("ruin_01 의 (0, 5) 에 transition 슬롯",
        ruin["encounters"].get(Vector2i(0, 5), {}).get("on_enter", {}).get("kind") == "transition") and ok
    ok = _check("ruin_01 의 (0, 5) transition 이 field_01 (14, 6) 향함",
        ruin["encounters"][Vector2i(0, 5)]["on_enter"].get("target_map") == "field_01"
        and ruin["encounters"][Vector2i(0, 5)]["on_enter"].get("target_pos") == Vector2i(14, 6),
        "target_pos = %s" % str(ruin["encounters"][Vector2i(0, 5)]["on_enter"].get("target_pos"))) and ok

    # field_01 의 (14, 6) 에 transition 박힘
    var field: Dictionary = GameData.MAPS["field_01"]
    ok = _check("field_01 의 (14, 6) 에 transition 슬롯",
        field["encounters"].get(Vector2i(14, 6), {}).get("on_enter", {}).get("kind") == "transition") and ok
    ok = _check("field_01 의 (14, 6) transition 이 ruin_01 (0, 5) 향함",
        field["encounters"][Vector2i(14, 6)]["on_enter"].get("target_map") == "ruin_01"
        and field["encounters"][Vector2i(14, 6)]["on_enter"].get("target_pos") == Vector2i(0, 5)) and ok

    # ============================================================
    # 시나리오 — 시작 + intro 소비
    # ============================================================
    GameManager.start_run()
    await _consume_dialogues()
    ok = _check("시작 — current_map_id == field_01",
        RunManager.run_data.get("current_map_id") == "field_01") and ok

    # ============================================================
    # field (1, 6) → (14, 6) 까지 동 이동 13 회 (regression / repair / research / combat 우회)
    # actions_remaining 부족 회피 — 직접 player_pos 박기
    # ============================================================
    RunManager.run_data["player_pos"] = Vector2i(14, 6)
    # 실제 transition 트리거 = try_move 결로 들어가야 — (13, 6) 에 위치 박고 동쪽 이동.
    RunManager.run_data["player_pos"] = Vector2i(13, 6)
    RunManager.run_data["actions_remaining"] = 8
    var moved: bool = RunManager.try_move(Vector2i(1, 0))
    ok = _check("(14, 6) 진입 시도 성공", moved) and ok
    ok = _check("진입 후 current_map_id == ruin_01",
        RunManager.run_data.get("current_map_id") == "ruin_01") and ok
    ok = _check("진입 후 player_pos == (0, 5)",
        RunManager.run_data.get("player_pos") == Vector2i(0, 5)) and ok
    ok = _check("진입 후 visited_by_map 에 ruin_01 키",
        RunManager.run_data.get("visited_by_map", {}).has("ruin_01")) and ok
    ok = _check("진입 후 visited_by_map[ruin_01][(0,5)] = true",
        RunManager.run_data["visited_by_map"]["ruin_01"].get(Vector2i(0, 5), false)) and ok
    ok = _check("도착지 슬롯 자동 평가 X — phase = 'map' 유지 (transition 슬롯 자동 발화 X)",
        RunManager.run_data.get("phase") == "map") and ok

    # ============================================================
    # ruin 안 이동 + ruin event 발화
    # ============================================================
    # (0, 5) → (1, 5) 동 이동 (passable 인지 확인 필요 — terrain 결로 P 또는 G)
    RunManager.run_data["player_pos"] = Vector2i(3, 4)   # 직접 박기
    RunManager.run_data["actions_remaining"] = 8
    var moved2: bool = RunManager.try_move(Vector2i(1, 0))   # → (4, 4) ruin_dust
    ok = _check("ruin_01 (4, 4) 진입 — ruin_dust 발화",
        RunManager.run_data.get("phase") == "event"
        and EventManager.event_state.get("event_id") == "ruin_dust") and ok
    await _consume_dialogues()
    ok = _check("ruin_dust 소비 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok
    ok = _check("ruin_dust 가 ruin_01 의 visited_by_map 에 박힘",
        RunManager.run_data["visited_by_map"]["ruin_01"].get(Vector2i(4, 4), false)) and ok

    # ============================================================
    # 복귀 — ruin (0, 5) 재진입 → field (14, 6) 복귀
    # ============================================================
    RunManager.run_data["player_pos"] = Vector2i(1, 5)
    RunManager.run_data["actions_remaining"] = 8
    var moved3: bool = RunManager.try_move(Vector2i(-1, 0))   # → (0, 5)
    ok = _check("ruin (0, 5) 재진입 → field 복귀 (current_map_id)",
        RunManager.run_data.get("current_map_id") == "field_01") and ok
    ok = _check("복귀 후 player_pos == (14, 6)",
        RunManager.run_data.get("player_pos") == Vector2i(14, 6)) and ok

    # ============================================================
    # 회귀 — research_node 진입 후 leave_research → 시작 맵 자동 복귀
    # ============================================================
    RunManager.run_data["player_pos"] = Vector2i(7, 6)   # research_node_main
    RunManager.run_data["phase"] = "research"
    RunManager.leave_research()
    await get_tree().process_frame
    await _consume_dialogues()  # intro 매 회차 발화
    ok = _check("회귀 후 current_map_id = STARTING_MAP",
        RunManager.run_data.get("current_map_id") == GameData.STARTING_MAP) and ok
    ok = _check("회귀 후 player_pos = field 의 spawn",
        RunManager.run_data.get("player_pos") == GameData.MAPS[GameData.STARTING_MAP]["spawn"]) and ok
    ok = _check("회귀 후 visited_by_map 가 시작 맵 + spawn 만",
        RunManager.run_data["visited_by_map"].size() == 1
        and RunManager.run_data["visited_by_map"][GameData.STARTING_MAP].size() == 1) and ok

    return ok
