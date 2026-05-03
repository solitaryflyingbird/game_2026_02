extends Node

# Stage 1A — EventManager + dialogue 시뮬 자동 검증 (그리드 리뉴얼 결).
# 시나리오: spawn (1,6) → 동쪽 2칸 → 타일 (3,6) on_enter 의 regression_speech.
# 종료 코드: 0 = PASS, 1 = FAIL.

var _checks: Array = []


func _ready() -> void:
    print("=== Stage 1A 자동 검증 시작 (그리드) ===")
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
    var pass_count: int = 0
    var fail_count: int = 0
    for c in _checks:
        if c.ok:
            pass_count += 1
        else:
            fail_count += 1
    print("---")
    print("총 %d 검증 — PASS %d / FAIL %d" % [_checks.size(), pass_count, fail_count])


func _run_scenario() -> bool:
    var all_ok: bool = true

    # === 1. 새 게임 시작 + intro 소비 ===
    GameManager.start_run()
    await get_tree().process_frame
    while not EventManager.event_state.is_empty():
        EventManager.advance_line()
    await get_tree().process_frame

    all_ok = _check("intro 소비 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map",
        "phase = %s" % str(RunManager.run_data.get("phase"))) and all_ok

    var se = RunManager.big_run_data.get("seen_events")
    all_ok = _check("seen_events 에 regression_speech 아직 미존재",
        se != null and (se is Dictionary)
        and (se as Dictionary).get("regression_speech", 0) == 0) and all_ok

    all_ok = _check("초기 player_pos = SPAWN_POS",
        RunManager.run_data.get("player_pos") == GameData.MAPS[GameData.STARTING_MAP]["spawn"]) and all_ok

    # === 2. 동 1칸 이동 — 빈 칸 (2,6), 이벤트 없음 ===
    var moved1: bool = RunManager.try_move(Vector2i(1, 0))
    all_ok = _check("(2,6) 으로 이동 성공", moved1) and all_ok
    all_ok = _check("(2,6) 진입 — 이벤트 미발화 (phase = 'map')",
        RunManager.run_data.get("phase") == "map") and all_ok

    # === 3. 동 1칸 이동 — (3,6) 에 regression_speech 발화 ===
    var moved2: bool = RunManager.try_move(Vector2i(1, 0))
    all_ok = _check("(3,6) 으로 이동 성공", moved2) and all_ok
    all_ok = _check("phase = 'event' 전이",
        RunManager.run_data.get("phase") == "event",
        "phase = %s" % str(RunManager.run_data.get("phase"))) and all_ok
    all_ok = _check("event_state 활성",
        not EventManager.event_state.is_empty()) and all_ok
    all_ok = _check("event_state.kind = 'dialogue'",
        EventManager.event_state.get("kind") == "dialogue") and all_ok
    all_ok = _check("event_state.event_id = 'regression_speech'",
        EventManager.event_state.get("event_id") == "regression_speech") and all_ok
    all_ok = _check("event_state.line_idx = 0",
        EventManager.event_state.get("line_idx") == 0) and all_ok
    all_ok = _check("event_state.chain_root_id = event_id",
        EventManager.event_state.get("chain_root_id") == "regression_speech") and all_ok

    # === 4. 이벤트 활성 중 외부 try_move 거부 ===
    var rejected: bool = RunManager.try_move(Vector2i(-1, 0))
    all_ok = _check("이벤트 중 try_move 거부", not rejected) and all_ok
    all_ok = _check("거부 후 phase 유지 = 'event'",
        RunManager.run_data.get("phase") == "event") and all_ok

    # === 5. advance_line → 자동 종료 (regression 1라인) ===
    EventManager.advance_line()
    all_ok = _check("종료 후 event_state = {}",
        EventManager.event_state.is_empty()) and all_ok
    all_ok = _check("종료 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map") and all_ok
    all_ok = _check("seen_events[regression_speech] = 1",
        RunManager.big_run_data.get("seen_events", {}).get("regression_speech", 0) == 1) and all_ok

    # === 6. once_per: big_run — 같은 큰 런 안 재진입 시 미발생 ===
    RunManager.try_move(Vector2i(-1, 0))   # (3,6) → (2,6)
    RunManager.try_move(Vector2i(-1, 0))   # (2,6) → (1,6) 스폰
    RunManager.try_move(Vector2i(1, 0))    # (1,6) → (2,6)
    RunManager.try_move(Vector2i(1, 0))    # (2,6) → (3,6) 재진입
    all_ok = _check("once_per: 재진입 시 phase 'map' 유지",
        RunManager.run_data.get("phase") == "map") and all_ok
    all_ok = _check("once_per: event_state 비활성 유지",
        EventManager.event_state.is_empty()) and all_ok

    # === 7. 회귀 후 — 슬롯 once_per: internal_run 이라 재발화 ===
    RunManager.end_internal_run("cleared")
    # seen_events 누적 카운터는 회귀 통과 (빅 런 통계). 슬롯 필터는 seen_this_run.
    all_ok = _check("회귀 후 seen_events 누적 유지",
        RunManager.big_run_data.get("seen_events", {}).get("regression_speech", 0) >= 1) and all_ok
    # 회귀 직후 _start_internal_run 이 run_start → intro 매 회차 재발화 (phase=event).
    all_ok = _check("회귀 후 phase = 'event' (intro 재발화)",
        RunManager.run_data.get("phase") == "event") and all_ok
    all_ok = _check("회귀 후 event_id = 'intro_speech'",
        EventManager.event_state.get("event_id") == "intro_speech") and all_ok
    all_ok = _check("회귀 후 player_pos = SPAWN_POS",
        RunManager.run_data.get("player_pos") == GameData.MAPS[GameData.STARTING_MAP]["spawn"]) and all_ok
    # intro 소비
    while not EventManager.event_state.is_empty():
        EventManager.advance_line()
    await get_tree().process_frame
    all_ok = _check("intro 소비 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map") and all_ok
    all_ok = _check("새 회차 — seen_this_run 비움",
        RunManager.run_data.get("seen_this_run", {}).is_empty()) and all_ok

    RunManager.try_move(Vector2i(1, 0))    # spawn → (2,6)
    RunManager.try_move(Vector2i(1, 0))    # (2,6) → (3,6) 회귀 후 재진입
    all_ok = _check("회귀 후 (3,6) 진입 — regression 재발화 (phase=event)",
        RunManager.run_data.get("phase") == "event") and all_ok
    all_ok = _check("회귀 후 event_id = 'regression_speech'",
        EventManager.event_state.get("event_id") == "regression_speech") and all_ok

    return all_ok
