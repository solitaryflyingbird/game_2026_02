extends Node

# Stage 1A — EventManager + dialogue 시뮬 자동 검증.
# 안 4 §6 시나리오 1 + 롤아웃 §2 검증 시퀀스를 자동화.
#
# 실행: godot --headless --path "<프로젝트>" res://test/test_event_1a.tscn
# 종료 코드: 0 = PASS, 1 = FAIL.

var _checks: Array = []  # [{name: String, ok: bool, detail: String}]


func _ready() -> void:
    print("=== Stage 1A 자동 검증 시작 ===")
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

    # === 1. 새 게임 시작 + run_start 이벤트 소비 ===
    # 1A-2 이후 run_start 트리거로 intro_speech 자동 발화. 1A 본 시나리오는
    # node_enter 트리거 흐름이므로, intro 는 advance 로 미리 닫고 진입.
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

    # === 2. event 노드 (5번) 으로 이동 ===
    var moved: bool = RunManager.move_to_node(5)
    all_ok = _check("event 노드 move 성공", moved) and all_ok
    all_ok = _check("phase = 'event' 전이",
        RunManager.run_data.get("phase") == "event",
        "phase = %s" % str(RunManager.run_data.get("phase"))) and all_ok
    all_ok = _check("event_state 활성",
        not EventManager.event_state.is_empty()) and all_ok
    all_ok = _check("event_state.kind = 'dialogue'",
        EventManager.event_state.get("kind") == "dialogue",
        "kind = %s" % str(EventManager.event_state.get("kind"))) and all_ok
    all_ok = _check("event_state.event_id = 'regression_speech'",
        EventManager.event_state.get("event_id") == "regression_speech") and all_ok
    all_ok = _check("event_state.line_idx = 0",
        EventManager.event_state.get("line_idx") == 0) and all_ok
    all_ok = _check("event_state.chain_root_id = event_id",
        EventManager.event_state.get("chain_root_id") == "regression_speech") and all_ok

    # === 3. 이벤트 활성 중 외부 move 거부 ===
    var rejected: bool = RunManager.move_to_node(1)
    all_ok = _check("이벤트 중 move_to_node 거부",
        not rejected) and all_ok
    all_ok = _check("거부 후 phase 유지 = 'event'",
        RunManager.run_data.get("phase") == "event") and all_ok

    # === 4. 라인 advance → 자동 종료 (regression_speech 는 1 라인) ===
    EventManager.advance_line()
    all_ok = _check("종료 후 event_state = {}",
        EventManager.event_state.is_empty()) and all_ok
    all_ok = _check("종료 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map",
        "phase = %s" % str(RunManager.run_data.get("phase"))) and all_ok
    all_ok = _check("seen_events[regression_speech] = 1",
        RunManager.big_run_data.get("seen_events", {}).get("regression_speech", 0) == 1) and all_ok

    # === 6. once_per 'big_run' — 같은 큰 런 안 재진입 시 미발생 ===
    var moved2: bool = RunManager.move_to_node(1)
    all_ok = _check("이벤트 종료 후 일반 move 가능", moved2) and all_ok
    var moved3: bool = RunManager.move_to_node(5)
    all_ok = _check("event 노드 재진입 move 성공", moved3) and all_ok
    all_ok = _check("once_per: 재진입 시 phase 'map' 유지 (이벤트 미발생)",
        RunManager.run_data.get("phase") == "map",
        "phase = %s" % str(RunManager.run_data.get("phase"))) and all_ok
    all_ok = _check("once_per: event_state 비활성 유지",
        EventManager.event_state.is_empty()) and all_ok

    # === 7. 회귀 후에도 once_per 'big_run' 유지 ===
    RunManager.end_internal_run("cleared")
    all_ok = _check("회귀 후 seen_events 유지",
        RunManager.big_run_data.get("seen_events", {}).get("regression_speech", 0) == 1) and all_ok
    all_ok = _check("회귀 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map") and all_ok
    all_ok = _check("회귀 후 current_node_id = 1",
        RunManager.run_data.get("current_node_id") == 1) and all_ok
    var moved4: bool = RunManager.move_to_node(5)
    all_ok = _check("회귀 후 event 노드 이동 성공", moved4) and all_ok
    all_ok = _check("회귀 후에도 once_per 회피 — 이벤트 미발생",
        RunManager.run_data.get("phase") == "map") and all_ok

    return all_ok
