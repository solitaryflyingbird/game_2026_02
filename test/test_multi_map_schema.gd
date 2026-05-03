extends Node

# M-1 — 다중 맵 schema 자동 검증.
# MAPS / STARTING_MAP / run_data 의 신규 필드 정합 + 옛 결 미참조.

var _checks: Array = []


func _ready() -> void:
    print("=== M-1 다중 맵 schema 자동 검증 시작 ===")
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


func _run_scenario() -> bool:
    var ok := true

    # ============================================================
    # MAPS const 정합
    # ============================================================
    ok = _check("GameData.MAPS 가 Dictionary",
        GameData.MAPS is Dictionary) and ok
    ok = _check("STARTING_MAP 이 MAPS 의 키",
        GameData.MAPS.has(GameData.STARTING_MAP)) and ok
    ok = _check("STARTING_MAP == 'field_01'",
        GameData.STARTING_MAP == "field_01") and ok

    var start_map: Dictionary = GameData.MAPS[GameData.STARTING_MAP]
    ok = _check("MAPS[STARTING] 에 name 필드",
        start_map.has("name") and start_map["name"] is String) and ok
    ok = _check("MAPS[STARTING] 에 terrain 필드 (Array)",
        start_map.has("terrain") and start_map["terrain"] is Array) and ok
    ok = _check("MAPS[STARTING] 에 spawn 필드 (Vector2i)",
        start_map.has("spawn") and start_map["spawn"] is Vector2i) and ok
    ok = _check("MAPS[STARTING] 에 encounters 필드 (Dictionary)",
        start_map.has("encounters") and start_map["encounters"] is Dictionary) and ok

    # 지형 결 정합
    ok = _check("MAPS[STARTING].terrain 12 행",
        start_map["terrain"].size() == 12) and ok
    ok = _check("MAPS[STARTING].terrain[0] 16 열",
        start_map["terrain"][0].length() == 16) and ok
    ok = _check("MAPS[STARTING].spawn = (1, 6)",
        start_map["spawn"] == Vector2i(1, 6)) and ok
    ok = _check("MAPS[STARTING].encounters >= 5 슬롯",
        start_map["encounters"].size() >= 5) and ok

    # ============================================================
    # 옛 const 폐기 검증
    # ============================================================
    ok = _check("옛 SPAWN_POS const 폐기",
        not ("SPAWN_POS" in GameData)) and ok
    ok = _check("옛 WORLD_TERRAIN const 폐기",
        not ("WORLD_TERRAIN" in GameData)) and ok
    ok = _check("옛 TILE_ENCOUNTERS const 폐기",
        not ("TILE_ENCOUNTERS" in GameData)) and ok

    # ============================================================
    # run_data 신규 필드 정합 (회차 시작 + intro 소비)
    # ============================================================
    GameManager.start_run()
    await get_tree().process_frame
    while not EventManager.event_state.is_empty():
        EventManager.advance_line()
    await get_tree().process_frame

    var rd: Dictionary = RunManager.run_data
    ok = _check("run_data.current_map_id == STARTING_MAP",
        rd.get("current_map_id") == GameData.STARTING_MAP) and ok
    ok = _check("run_data.player_pos == spawn",
        rd.get("player_pos") == start_map["spawn"]) and ok
    ok = _check("run_data.visited_by_map 가 Dictionary",
        rd.get("visited_by_map") is Dictionary) and ok
    ok = _check("visited_by_map[STARTING] 에 spawn 박힘",
        rd["visited_by_map"][GameData.STARTING_MAP].get(start_map["spawn"], false)) and ok
    ok = _check("run_data.explored_by_map[STARTING] 비어있음",
        rd["explored_by_map"][GameData.STARTING_MAP].is_empty()) and ok
    ok = _check("run_data 에 옛 visited_tiles 키 없음",
        not rd.has("visited_tiles")) and ok
    ok = _check("run_data 에 옛 explored_tiles 키 없음",
        not rd.has("explored_tiles")) and ok

    # ============================================================
    # 회귀 후 자동 리셋
    # ============================================================
    # 동 2칸 + 탐험 후 회귀 → visited_by_map / explored_by_map 빔 (spawn 외)
    RunManager.try_move(Vector2i(1, 0))
    RunManager.try_move(Vector2i(1, 0))
    # (3, 6) 진입 시 regression_speech 발화 → 소비
    while not EventManager.event_state.is_empty():
        EventManager.advance_line()
    await get_tree().process_frame
    RunManager.run_data["player_pos"] = Vector2i(4, 8)
    RunManager.try_explore()
    while not EventManager.event_state.is_empty():
        EventManager.advance_line()
    await get_tree().process_frame

    # 회귀
    RunManager.run_data["phase"] = "research"
    RunManager.leave_research()
    await get_tree().process_frame
    while not EventManager.event_state.is_empty():
        EventManager.advance_line()
    await get_tree().process_frame

    var rd2: Dictionary = RunManager.run_data
    ok = _check("회귀 후 current_map_id = STARTING",
        rd2.get("current_map_id") == GameData.STARTING_MAP) and ok
    ok = _check("회귀 후 visited_by_map[STARTING] 에 spawn 만",
        rd2["visited_by_map"][GameData.STARTING_MAP].size() == 1) and ok
    ok = _check("회귀 후 explored_by_map[STARTING] 비움",
        rd2["explored_by_map"][GameData.STARTING_MAP].is_empty()) and ok

    return ok
