extends Node

# Stage 1A-2 — run_start 트리거 + 다중 이벤트 자동 검증.
#
# 두 이벤트:
#   1. intro_speech       (run_start, "시작합니다.")
#   2. regression_speech  (node_enter type "event", "회귀합니다.")
# 둘 다 once_per: big_run.
#
# 콘솔 검증 + event_state JSON 스키마 출력 (각 lifecycle 시점에 _dump).
# 실행: godot --headless --path "<프로젝트>" res://test/test_event_1a2.tscn
# 종료 코드: 0 = PASS, 1 = FAIL.

var _checks: Array = []


func _ready() -> void:
    print("=== Stage 1A-2 자동 검증 시작 ===")
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

    ok = _check("phase = 'event' (intro_speech 자동 발화)",
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

    # 1라인 advance → 자동 종료
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
    # 섹션 2: 노드 5 진입 → regression_speech 발화
    # =========================================================
    var moved: bool = RunManager.move_to_node(5)
    ok = _check("event 노드 (5) move 성공", moved) and ok

    _dump_event_state("node 5 진입 직후")

    ok = _check("phase = 'event' 전이",
        RunManager.run_data.get("phase") == "event") and ok
    ok = _check("event_state.event_id = 'regression_speech'",
        EventManager.event_state.get("event_id") == "regression_speech",
        "event_id = %s" % str(EventManager.event_state.get("event_id"))) and ok
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
    # 섹션 3: 회귀 (end_internal_run cleared) — once_per: big_run 유지
    # =========================================================
    RunManager.end_internal_run("cleared")
    _dump_event_state("회귀 직후 (새 internal run 시작 직후)")
    _dump_seen_events("회귀 직후")

    ok = _check("회귀 후 seen_events[intro_speech] 유지 = 1",
        RunManager.big_run_data["seen_events"].get("intro_speech", 0) == 1) and ok
    ok = _check("회귀 후 seen_events[regression_speech] 유지 = 1",
        RunManager.big_run_data["seen_events"].get("regression_speech", 0) == 1) and ok

    # 회귀 후 새 internal run 자동 시작 — run_start 재평가, 단 once_per 로 미발생
    ok = _check("회귀 후 phase = 'map' (intro_speech 미발생)",
        RunManager.run_data.get("phase") == "map",
        "phase = %s" % str(RunManager.run_data.get("phase"))) and ok
    ok = _check("회귀 후 event_state 비활성",
        EventManager.event_state.is_empty()) and ok
    ok = _check("회귀 후 current_node_id = 1",
        RunManager.run_data.get("current_node_id") == 1) and ok

    # 노드 5 재진입 — once_per 로 regression 미발생
    var moved2: bool = RunManager.move_to_node(5)
    ok = _check("회귀 후 node 5 move 성공", moved2) and ok
    ok = _check("회귀 후 node 5 진입 시 phase = 'map' (regression 미발생)",
        RunManager.run_data.get("phase") == "map") and ok
    ok = _check("회귀 후 event_state 비활성 유지",
        EventManager.event_state.is_empty()) and ok

    return ok
