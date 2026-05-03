extends Node

# M-3 — UI 다중 그리드 시각 검증.
# main.tscn 인스턴스 + field 스크린샷 + 전이 후 ruin 스크린샷 + 마커 / HUD 검증.

const SHOT_DIR := "res://test_screenshots/"

var _checks: Array = []
var _main: Node


func _ready() -> void:
    print("=== M-3 다중 맵 UI 시각 검증 시작 ===")
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


func _consume_dialogues() -> void:
    while not EventManager.event_state.is_empty() and \
            EventManager.event_state.get("kind") == "dialogue":
        EventManager.advance_line()
    await get_tree().process_frame


func _get_run_ui() -> Node:
    return _main.get_node("run_ui")


func _run_scenario() -> bool:
    var ok := true

    # 시작 + intro 소비
    GameManager.start_run()
    await _consume_dialogues()
    await _shot("multi_map_01_field_start")

    # _grid_roots 정합
    var ui := _get_run_ui()
    ok = _check("ui._grid_roots 모든 맵 보유",
        ui._grid_roots.size() == GameData.MAPS.size()) and ok
    ok = _check("ui._grid_roots[field_01] visible",
        ui._grid_roots["field_01"].visible) and ok
    ok = _check("ui._grid_roots[ruin_01] invisible",
        not ui._grid_roots["ruin_01"].visible) and ok

    # HUD 의 맵 이름
    ok = _check("HUD 의 맵 이름 = '평원'",
        "평원" in ui._terrain_label.text) and ok

    # field (13, 6) → 동 이동 → ruin 으로 전이
    RunManager.run_data["player_pos"] = Vector2i(13, 6)
    RunManager.run_data["actions_remaining"] = 8
    RunManager.try_move(Vector2i(1, 0))
    await get_tree().process_frame
    await get_tree().process_frame
    await _shot("multi_map_02_ruin_after_transition")

    ok = _check("전이 후 ruin_01 root visible",
        ui._grid_roots["ruin_01"].visible) and ok
    ok = _check("전이 후 field_01 root invisible",
        not ui._grid_roots["field_01"].visible) and ok
    ok = _check("HUD 의 맵 이름 = '폐허'",
        "폐허" in ui._terrain_label.text) and ok
    ok = _check("플레이어 마커가 ruin root 의 자식",
        ui._player_marker.get_parent() == ui._grid_roots["ruin_01"]) and ok

    # ruin 안 이동 + ruin_dust 발화 → 다시 grid (visible)
    RunManager.run_data["player_pos"] = Vector2i(3, 4)
    RunManager.run_data["actions_remaining"] = 8
    RunManager.try_move(Vector2i(1, 0))
    await _consume_dialogues()
    await _shot("multi_map_03_ruin_after_event")
    ok = _check("ruin_dust 소비 후 ruin root 다시 visible",
        ui._grid_roots["ruin_01"].visible) and ok

    # ruin (0, 5) 진입 → field 복귀
    RunManager.run_data["player_pos"] = Vector2i(1, 5)
    RunManager.run_data["actions_remaining"] = 8
    RunManager.try_move(Vector2i(-1, 0))
    await get_tree().process_frame
    await get_tree().process_frame
    await _shot("multi_map_04_field_after_return")

    ok = _check("복귀 후 field_01 root visible",
        ui._grid_roots["field_01"].visible) and ok
    ok = _check("복귀 후 ruin_01 root invisible",
        not ui._grid_roots["ruin_01"].visible) and ok
    ok = _check("복귀 후 HUD 의 맵 이름 = '평원'",
        "평원" in ui._terrain_label.text) and ok

    return ok
