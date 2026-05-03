extends Node

# 그리드 리뉴얼 GR-1 ~ GR-5 통합 검증.
# 시뮬 단 (UI 무관). 자료구조 / 이동 / 진입 트리거 / 탐험 / 휴식 / combat / research.

var _checks: Array = []


func _ready() -> void:
    print("=== 그리드 리뉴얼 자동 검증 시작 ===")
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
    # GR-1: 자료구조 정합
    # ============================================================
    var start_map: Dictionary = GameData.MAPS[GameData.STARTING_MAP]
    ok = _check("MAPS terrain 12 행",
        start_map["terrain"].size() == 12) and ok
    ok = _check("MAPS terrain[0] 16 열",
        start_map["terrain"][0].length() == 16) and ok
    ok = _check("TERRAIN_RULES — G passable",
        GameData.TERRAIN_RULES["G"]["passable"] == true) and ok
    ok = _check("TERRAIN_RULES — F not passable",
        GameData.TERRAIN_RULES["F"]["passable"] == false) and ok
    ok = _check("MAPS spawn = (1, 6)",
        start_map["spawn"] == Vector2i(1, 6)) and ok
    ok = _check("ACTIONS_PER_DAY = 8",
        GameData.ACTIONS_PER_DAY == 8) and ok
    ok = _check("MAPS encounters 키 Vector2i",
        start_map["encounters"].has(Vector2i(3, 6))) and ok

    # ============================================================
    # GR-1: run_data 초기 필드
    # ============================================================
    GameManager.start_run()
    await get_tree().process_frame
    await _consume_dialogues()  # intro 소비

    var rd: Dictionary = RunManager.run_data
    var spawn: Vector2i = GameData.MAPS[GameData.STARTING_MAP]["spawn"]
    ok = _check("player_pos = SPAWN",
        rd.get("player_pos") == spawn) and ok
    ok = _check("current_map_id = STARTING_MAP",
        rd.get("current_map_id") == GameData.STARTING_MAP) and ok
    ok = _check("day = 1", rd.get("day") == 1) and ok
    ok = _check("actions_remaining = ACTIONS_PER_DAY",
        rd.get("actions_remaining") == GameData.ACTIONS_PER_DAY) and ok
    ok = _check("visited_by_map[STARTING][SPAWN] = true",
        rd.get("visited_by_map", {}).get(GameData.STARTING_MAP, {}).get(spawn, false)) and ok
    ok = _check("explored_by_map[STARTING] 비어있음",
        rd.get("explored_by_map", {}).get(GameData.STARTING_MAP, {}).is_empty()) and ok
    ok = _check("seen_this_run 비어있음",
        rd.get("seen_this_run", {}).is_empty()) and ok

    # ============================================================
    # GR-2: 이동 + 통과 검사
    # ============================================================
    var blocked: bool = RunManager.try_move(Vector2i(-1, 0))
    ok = _check("벽 (0,6) 방향 이동 거부",
        not blocked) and ok
    ok = _check("거부 후 위치 유지",
        RunManager.run_data["player_pos"] == spawn) and ok
    ok = _check("거부 후 actions 무변",
        RunManager.run_data["actions_remaining"] == GameData.ACTIONS_PER_DAY) and ok

    var moved_e: bool = RunManager.try_move(Vector2i(1, 0))
    ok = _check("동 1칸 이동 성공", moved_e) and ok
    ok = _check("위치 (2,6)",
        RunManager.run_data["player_pos"] == Vector2i(2, 6)) and ok
    ok = _check("actions_remaining 차감",
        RunManager.run_data["actions_remaining"] == GameData.ACTIONS_PER_DAY - 1) and ok
    ok = _check("visited_by_map[STARTING][(2,6)] = true",
        RunManager.run_data["visited_by_map"][GameData.STARTING_MAP].get(Vector2i(2, 6), false)) and ok

    # ============================================================
    # GR-3: 탐험 — (4,8) 의 explore 슬롯 발화
    # ============================================================
    # 회차 1 의 actions 를 보존하기 위해 직접 위치 세팅.
    RunManager.run_data["player_pos"] = Vector2i(4, 8)
    RunManager.run_data["visited_by_map"][GameData.STARTING_MAP][Vector2i(4, 8)] = true
    var explored: bool = RunManager.try_explore()
    ok = _check("(4,8) 탐험 시도 — true 반환", explored) and ok
    ok = _check("(4,8) 탐험 후 phase = 'event' (found_letter)",
        RunManager.run_data.get("phase") == "event") and ok
    ok = _check("event_id = 'found_letter'",
        EventManager.event_state.get("event_id") == "found_letter") and ok
    await _consume_dialogues()
    ok = _check("found_letter 소비 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok

    var explored2: bool = RunManager.try_explore()
    ok = _check("(4,8) 같은 회차 재탐험 거부",
        not explored2) and ok

    # ============================================================
    # GR-4: 휴식 + 일자 + rest 이벤트 회차 1회 정책
    # ============================================================
    var day_before: int = RunManager.run_data["day"]
    RunManager.run_data["actions_remaining"] = 5
    RunManager.rest()
    # rest_dream_1 발화 — 매 휴식마다 (once_per 없음).
    ok = _check("첫 휴식 — rest_dream_1 발화 (phase = 'event')",
        RunManager.run_data.get("phase") == "event"
        and EventManager.event_state.get("event_id") == "rest_dream_1") and ok
    await _consume_dialogues()
    ok = _check("rest 후 day +1",
        RunManager.run_data["day"] == day_before + 1) and ok
    ok = _check("rest 후 actions 리셋",
        RunManager.run_data["actions_remaining"] == GameData.ACTIONS_PER_DAY) and ok
    ok = _check("rest 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok

    # 같은 회차 두번째 휴식 — 매번 재발화 (반복 컷씬)
    var day_before2: int = RunManager.run_data["day"]
    RunManager.run_data["actions_remaining"] = 5
    RunManager.rest()
    ok = _check("같은 회차 2번째 휴식 — rest_dream_1 재발화",
        RunManager.run_data.get("phase") == "event"
        and EventManager.event_state.get("event_id") == "rest_dream_1") and ok
    await _consume_dialogues()
    ok = _check("2번째 휴식도 day +1",
        RunManager.run_data["day"] == day_before2 + 1) and ok

    # ============================================================
    # GR-5: combat — (4,4) 진입
    # ============================================================
    RunManager.run_data["player_pos"] = Vector2i(4, 5)
    RunManager.run_data["actions_remaining"] = 8
    var moved_combat: bool = RunManager.try_move(Vector2i(0, -1))
    ok = _check("(4,4) 이동 성공", moved_combat) and ok
    ok = _check("(4,4) 진입 — phase = 'battle_preview'",
        RunManager.run_data.get("phase") == "battle_preview") and ok
    var pending: Dictionary = RunManager.run_data.get("pending_combat", {})
    ok = _check("pending_combat.enemy_id = 'larva'",
        pending.get("enemy_id") == "larva") and ok
    ok = _check("pending_combat.encounter_id 박힘",
        pending.get("encounter_id") == "larva_combat_4_4") and ok
    ok = _check("seen_this_run[larva_combat_4_4] 박힘",
        RunManager.run_data["seen_this_run"].get("larva_combat_4_4", false)) and ok

    # 전투 모킹 — start_combat 호출하면 BattleManager 가 실 작동 (헤드리스에서도 OK).
    # 여기서는 phase = battle_preview 상태에서 직접 reset.
    RunManager.run_data["phase"] = "map"
    RunManager.run_data["pending_combat"] = {}

    # 같은 회차 재진입 — once_per: internal_run 으로 미발화
    RunManager.run_data["player_pos"] = Vector2i(4, 5)
    RunManager.try_move(Vector2i(0, -1))
    ok = _check("같은 회차 (4,4) 재진입 — phase = 'map' (combat 미발화)",
        RunManager.run_data.get("phase") == "map") and ok

    # ============================================================
    # GR-5: research 진입 — (7,6) on_enter kind = research
    # ============================================================
    RunManager.run_data["player_pos"] = Vector2i(6, 6)
    RunManager.run_data["actions_remaining"] = 8
    RunManager.try_move(Vector2i(1, 0))
    ok = _check("(7,6) 진입 — phase = 'research'",
        RunManager.run_data.get("phase") == "research") and ok
    ok = _check("research_offers 생성됨",
        RunManager.run_data.get("research_offers", []).size() > 0) and ok

    # leave_research → 회귀
    var big_run_count_before: int = RunManager.big_run_data["meta"]["big_run_count"]
    RunManager.leave_research()
    await get_tree().process_frame
    # 회귀 직후 _start_internal_run → run_start → intro 매 회차 발화. 소비.
    await _consume_dialogues()

    ok = _check("leave_research → big_run_count +1",
        RunManager.big_run_data["meta"]["big_run_count"] == big_run_count_before + 1) and ok
    ok = _check("회귀 후 player_pos = SPAWN",
        RunManager.run_data.get("player_pos") == GameData.MAPS[GameData.STARTING_MAP]["spawn"]) and ok
    ok = _check("회귀 후 day = 1 (리셋)",
        RunManager.run_data.get("day") == 1) and ok
    ok = _check("회귀 후 seen_this_run 비움",
        RunManager.run_data.get("seen_this_run", {}).is_empty()) and ok
    ok = _check("회귀 후 explored_by_map[STARTING] 비움",
        RunManager.run_data.get("explored_by_map", {}).get(GameData.STARTING_MAP, {}).is_empty()) and ok

    # 회귀 후 (3,6) 재진입 — regression 재발화 (슬롯 once_per: internal_run)
    RunManager.try_move(Vector2i(1, 0))   # (2,6)
    RunManager.try_move(Vector2i(1, 0))   # (3,6)
    ok = _check("회귀 후 (3,6) 진입 — regression 재발화",
        RunManager.run_data.get("phase") == "event"
        and EventManager.event_state.get("event_id") == "regression_speech") and ok
    await _consume_dialogues()

    # 회귀 후 (4,8) 탐험 — found_letter 재발화
    RunManager.run_data["player_pos"] = Vector2i(4, 8)
    RunManager.run_data["actions_remaining"] = 8
    var explore_again: bool = RunManager.try_explore()
    ok = _check("회귀 후 (4,8) 재탐험 — true 반환", explore_again) and ok
    ok = _check("회귀 후 (4,8) 재탐험 — found_letter 재발화",
        RunManager.run_data.get("phase") == "event"
        and EventManager.event_state.get("event_id") == "found_letter") and ok
    await _consume_dialogues()

    # 회귀 후 휴식 — rest_dream_1 재발화 (이전 회차 발화 무관, internal_run 결)
    RunManager.run_data["actions_remaining"] = 5
    RunManager.rest()
    ok = _check("회귀 후 휴식 — rest_dream_1 재발화",
        RunManager.run_data.get("phase") == "event"
        and EventManager.event_state.get("event_id") == "rest_dream_1") and ok

    return ok
