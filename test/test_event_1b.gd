extends Node

# Stage 1B — event_ui.gd + main.tscn 배선 자동 검증 (그리드 결).
# main.tscn 인스턴스 + 시뮬 + viewport 스크린샷.

const SHOT_DIR := "res://test_screenshots/"

var _checks: Array = []
var _main: Node


func _ready() -> void:
    print("=== Stage 1B 자동 검증 시작 (그리드) ===")
    _main = preload("res://main.tscn").instantiate()
    add_child(_main)
    await get_tree().process_frame
    await get_tree().process_frame

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


func _get_event_screen() -> Control:
    return _main.get_node("run_ui/event_screen") as Control


func _run_scenario() -> bool:
    var ok := true

    # ========== 0. 타이틀 ==========
    await _shot("1b_00_title")
    ok = _check("타이틀 — app_phase = 'title'",
        GameManager.app_phase == "title") and ok
    var event_screen: Control = _get_event_screen()
    ok = _check("event_screen 노드 존재", event_screen != null) and ok
    ok = _check("초기 event_screen.visible = false",
        not event_screen.visible) and ok

    # ========== 1. start_run → intro 노출 ==========
    GameManager.start_run()
    await _shot("1b_01_intro_dialogue")

    ok = _check("intro 발화 — phase = 'event'",
        RunManager.run_data.get("phase") == "event") and ok
    ok = _check("intro 발화 — event_id = 'intro_speech'",
        EventManager.event_state.get("event_id") == "intro_speech") and ok
    ok = _check("intro 발화 — event_screen.visible = true",
        event_screen.visible) and ok

    # ========== 2. 라인 advance × 2 → 종료 → 그리드 노출 ==========
    EventManager.advance_line()
    await _shot("1b_01b_intro_line2")
    ok = _check("intro 라인 2 — line_idx = 1",
        EventManager.event_state.get("line_idx") == 1) and ok

    EventManager.advance_line()
    await _shot("1b_02_after_intro_grid")

    ok = _check("intro 종료 — event_state = {}",
        EventManager.event_state.is_empty()) and ok
    ok = _check("intro 종료 — phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok
    ok = _check("intro 종료 — event_screen.visible = false",
        not event_screen.visible) and ok

    # ========== 3. 동 2칸 → (3,6) → regression 발화 ==========
    RunManager.try_move(Vector2i(1, 0))
    RunManager.try_move(Vector2i(1, 0))
    await _shot("1b_03_regression_dialogue")

    ok = _check("regression 발화 — phase = 'event'",
        RunManager.run_data.get("phase") == "event") and ok
    ok = _check("regression 발화 — event_id = 'regression_speech'",
        EventManager.event_state.get("event_id") == "regression_speech") and ok
    ok = _check("regression 발화 — event_screen.visible = true",
        event_screen.visible) and ok

    # ========== 4. advance → 종료 → 그리드 ==========
    EventManager.advance_line()
    await _shot("1b_04_after_regression_grid")

    ok = _check("regression 종료 — event_state = {}",
        EventManager.event_state.is_empty()) and ok
    ok = _check("regression 종료 — phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok
    ok = _check("regression 종료 — event_screen.visible = false",
        not event_screen.visible) and ok

    # ========== 5. 회귀 후 — intro 매 회차 재발화 ==========
    RunManager.end_internal_run("cleared")
    await _shot("1b_05_after_regression_intro")

    ok = _check("회귀 후 — phase = 'event' (intro 재발화)",
        RunManager.run_data.get("phase") == "event") and ok
    ok = _check("회귀 후 — event_id = 'intro_speech'",
        EventManager.event_state.get("event_id") == "intro_speech") and ok
    ok = _check("회귀 후 — event_screen.visible = true",
        event_screen.visible) and ok

    return ok
