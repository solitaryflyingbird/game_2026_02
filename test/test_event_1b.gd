extends Node

# Stage 1B — event_ui.gd + main.tscn 배선 자동 검증.
# main.tscn 을 자식으로 인스턴스해 실제 UI 트리를 띄우고, 시뮬 API 로 시나리오
# 진행. 핵심 시점마다 viewport 스크린샷을 PNG 로 저장.
#
# 실행: godot --headless --path "<프로젝트>" res://test/test_event_1b.tscn
# 종료 코드: 0 = PASS, 1 = FAIL.
# 스크린샷: res://test_screenshots/1b_*.png

const SHOT_DIR := "res://test_screenshots/"

var _checks: Array = []
var _main: Node


func _ready() -> void:
    print("=== Stage 1B 자동 검증 시작 ===")
    _main = preload("res://main.tscn").instantiate()
    add_child(_main)
    await get_tree().process_frame
    await get_tree().process_frame  # title_screen 정상 노출까지 한 프레임 더

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


func _shot(name: String) -> void:
    await get_tree().process_frame
    await get_tree().process_frame
    var img: Image = get_viewport().get_texture().get_image()
    var path := SHOT_DIR + name + ".png"
    var err := img.save_png(path)
    if err != OK:
        push_error("save_png 실패: %s (err %d)" % [path, err])
    else:
        print(">>> screenshot saved: %s" % path)


func _get_run_ui() -> Node:
    return _main.get_node("run_ui")


func _get_event_screen() -> Control:
    return _main.get_node("run_ui/event_screen") as Control


func _run_scenario() -> bool:
    var ok := true

    # ========== 0. 타이틀 화면 (시작 전) ==========
    await _shot("1b_00_title")
    ok = _check("타이틀 단계 — app_phase = 'title'",
        GameManager.app_phase == "title") and ok
    var event_screen: Control = _get_event_screen()
    ok = _check("event_screen 노드 존재",
        event_screen != null) and ok
    ok = _check("초기 event_screen.visible = false",
        not event_screen.visible) and ok

    # ========== 1. start_run → run_start → intro_speech UI 노출 ==========
    GameManager.start_run()
    await _shot("1b_01_intro_dialogue")

    ok = _check("intro 발화 — phase = 'event'",
        RunManager.run_data.get("phase") == "event") and ok
    ok = _check("intro 발화 — event_state.event_id = 'intro_speech'",
        EventManager.event_state.get("event_id") == "intro_speech") and ok
    ok = _check("intro 발화 — event_screen.visible = true",
        event_screen.visible) and ok

    # ========== 2. 라인 1 → 2 → 종료 → 맵 노출 (intro_speech 가 2 라인) ==========
    EventManager.advance_line()
    await _shot("1b_01b_intro_line2")
    ok = _check("intro 라인 2 표시 — line_idx = 1",
        EventManager.event_state.get("line_idx") == 1) and ok

    EventManager.advance_line()
    await _shot("1b_02_after_intro_map")

    ok = _check("intro 종료 — event_state = {}",
        EventManager.event_state.is_empty()) and ok
    ok = _check("intro 종료 — phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok
    ok = _check("intro 종료 — event_screen.visible = false",
        not event_screen.visible) and ok

    # ========== 3. 노드 5 진입 → regression_speech UI 노출 ==========
    RunManager.move_to_node(5)
    await _shot("1b_03_regression_dialogue")

    ok = _check("regression 발화 — phase = 'event'",
        RunManager.run_data.get("phase") == "event") and ok
    ok = _check("regression 발화 — event_state.event_id = 'regression_speech'",
        EventManager.event_state.get("event_id") == "regression_speech") and ok
    ok = _check("regression 발화 — event_screen.visible = true",
        event_screen.visible) and ok

    # ========== 4. 라인 advance → 종료 → 맵 노출 ==========
    EventManager.advance_line()
    await _shot("1b_04_after_regression_map")

    ok = _check("regression 종료 — event_state = {}",
        EventManager.event_state.is_empty()) and ok
    ok = _check("regression 종료 — phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok
    ok = _check("regression 종료 — event_screen.visible = false",
        not event_screen.visible) and ok

    # ========== 5. 회귀 후 once_per — 이벤트 미발생 ==========
    RunManager.end_internal_run("cleared")
    await _shot("1b_05_after_regression_run")

    ok = _check("회귀 후 — phase = 'map' (intro 미발생)",
        RunManager.run_data.get("phase") == "map") and ok
    ok = _check("회귀 후 — event_screen.visible = false",
        not event_screen.visible) and ok

    return ok
