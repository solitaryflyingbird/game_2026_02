extends Node

# Stage 1A-2 — run_start 트리거 + 다중 이벤트 자동 검증 (그리드 결).
#
# 두 이벤트:
#   1. intro_speech       (run_start, 2 라인)
#   2. regression_speech  (타일 (3,6) on_enter, 1 라인)
# 둘 다 once_per: big_run.

var _checks: Array = []


func _ready() -> void:
    print("=== Stage 1A-2 자동 검증 시작 (그리드) ===")
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


func _dump_event_state(label: String) -> void:
    print(">>> [%s] event_state = %s" % [label, JSON.stringify(EventManager.event_state)])


func _dump_seen_events(label: String) -> void:
    print(">>> [%s] seen_events = %s" % [label,
        JSON.stringify(RunManager.big_run_data.get("seen_events", {}))])


func _run_scenario() -> bool:
    var ok := true

    # =========================================================
    # 섹션 1: start_run → run_start 트리거 → intro_speech 발화
    # =========================================================
    GameManager.start_run()
    await get_tree().process_frame

    _dump_event_state("start_run 직후")

    ok = _check("phase = 'event' (intro 자동 발화)",
        RunManager.run_data.get("phase") == "event",
        "phase = %s" % str(RunManager.run_data.get("phase"))) and ok
    ok = _check("event_state.event_id = 'intro_speech'",
        EventManager.event_state.get("event_id") == "intro_speech") and ok
    ok = _check("event_state.kind = 'dialogue'",
        EventManager.event_state.get("kind") == "dialogue") and ok
    ok = _check("event_state.line_idx = 0",
        EventManager.event_state.get("line_idx") == 0) and ok
    ok = _check("event_state.chain_root_id = 'intro_speech'",
        EventManager.event_state.get("chain_root_id") == "intro_speech") and ok

    # 라인 1 → 2
    EventManager.advance_line()
    _dump_event_state("intro line 1 → 2 후")
    ok = _check("advance 1회 → line_idx = 1",
        EventManager.event_state.get("line_idx") == 1) and ok
    ok = _check("advance 1회 후 phase = 'event' 유지",
        RunManager.run_data.get("phase") == "event") and ok

    # 라인 2 → 종료
    EventManager.advance_line()
    _dump_event_state("intro 종료 후")
    _dump_seen_events("intro 종료 후")

    ok = _check("intro 종료 후 event_state = {}",
        EventManager.event_state.is_empty()) and ok
    ok = _check("intro 종료 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok
    ok = _check("seen_events[intro_speech] = 1",
        RunManager.big_run_data["seen_events"].get("intro_speech", 0) == 1) and ok

    # =========================================================
    # 섹션 2: 동 2칸 → 타일 (3,6) → regression_speech 발화
    # =========================================================
    var moved1: bool = RunManager.try_move(Vector2i(1, 0))
    var moved2: bool = RunManager.try_move(Vector2i(1, 0))
    ok = _check("(2,6) 이동 성공", moved1) and ok
    ok = _check("(3,6) 이동 성공", moved2) and ok

    _dump_event_state("(3,6) 진입 직후")

    ok = _check("phase = 'event' 전이",
        RunManager.run_data.get("phase") == "event") and ok
    ok = _check("event_state.event_id = 'regression_speech'",
        EventManager.event_state.get("event_id") == "regression_speech") and ok
    ok = _check("event_state.kind = 'dialogue'",
        EventManager.event_state.get("kind") == "dialogue") and ok
    ok = _check("event_state.line_idx = 0",
        EventManager.event_state.get("line_idx") == 0) and ok

    EventManager.advance_line()
    _dump_event_state("regression 종료 후")
    _dump_seen_events("regression 종료 후")

    ok = _check("regression 종료 후 event_state = {}",
        EventManager.event_state.is_empty()) and ok
    ok = _check("regression 종료 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok
    ok = _check("seen_events[regression_speech] = 1",
        RunManager.big_run_data["seen_events"].get("regression_speech", 0) == 1) and ok
    ok = _check("seen_events[intro_speech] 도 그대로 = 1",
        RunManager.big_run_data["seen_events"].get("intro_speech", 0) == 1) and ok

    # =========================================================
    # 섹션 3: 회귀 후 — intro 매 회차 재발화 + 슬롯 internal_run 재발화
    # =========================================================
    RunManager.end_internal_run("cleared")
    _dump_event_state("회귀 직후")
    _dump_seen_events("회귀 직후")

    # 회귀 직후 _start_internal_run 이 run_start → intro 다시 발화 (phase=event).
    ok = _check("회귀 후 phase = 'event' (intro 재발화)",
        RunManager.run_data.get("phase") == "event",
        "phase = %s" % str(RunManager.run_data.get("phase"))) and ok
    ok = _check("회귀 후 event_id = 'intro_speech'",
        EventManager.event_state.get("event_id") == "intro_speech") and ok
    ok = _check("회귀 후 player_pos = SPAWN_POS",
        RunManager.run_data.get("player_pos") == GameData.SPAWN_POS) and ok

    # intro 소비
    EventManager.advance_line()
    EventManager.advance_line()
    _dump_event_state("intro 재소비 후")
    _dump_seen_events("intro 재소비 후")
    ok = _check("intro 재소비 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok
    # seen_events 카운터는 누적 — 회귀 후 다시 발화했으니 += 1
    ok = _check("seen_events[intro_speech] = 2 (누적)",
        RunManager.big_run_data["seen_events"].get("intro_speech", 0) == 2) and ok
    ok = _check("seen_events[regression_speech] 유지 = 1",
        RunManager.big_run_data["seen_events"].get("regression_speech", 0) == 1) and ok

    # 동 2칸 재이동 — 슬롯 once_per: internal_run → 재발화
    RunManager.try_move(Vector2i(1, 0))
    RunManager.try_move(Vector2i(1, 0))
    ok = _check("회귀 후 (3,6) 재진입 — regression 재발화 (phase=event)",
        RunManager.run_data.get("phase") == "event") and ok
    ok = _check("회귀 후 event_id = 'regression_speech'",
        EventManager.event_state.get("event_id") == "regression_speech") and ok

    return ok
