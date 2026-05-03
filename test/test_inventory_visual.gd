extends Node

# I-4 — 인벤토리 UI 시각 검증.
# RPG 결 — 보유 > 0 만 표시 / 카테고리 자동 / 사용 버튼.

const SHOT_DIR := "res://test_screenshots/"

var _checks: Array = []
var _main: Node


func _ready() -> void:
    print("=== I-4 인벤토리 UI 시각 검증 시작 ===")
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
    img.save_png(SHOT_DIR + name + ".png")
    print(">>> screenshot saved: " + name + ".png")


func _consume_dialogues() -> void:
    while not EventManager.event_state.is_empty() and \
            EventManager.event_state.get("kind") == "dialogue":
        EventManager.advance_line()
    await get_tree().process_frame


func _run_scenario() -> bool:
    var ok := true

    GameManager.start_run()
    await _consume_dialogues()
    var ui := _main.get_node("run_ui")

    # ============================================================
    # 빈 인벤토리 결 (시작 시)
    # ============================================================
    await _shot("inventory_01_empty")
    ok = _check("HUD '(인벤토리 비어있음)' 표시 (RPG 결)",
        "비어있음" in ui._inventory_hud_label.text) and ok
    ok = _check("토글 버튼 visible (phase=map)",
        ui._btn_show_inventory.visible) and ok
    ok = _check("패널 초기 invisible",
        not ui._inventory_panel.visible) and ok

    # 패널 토글 — 빈 결
    ui._on_show_inventory_pressed()
    await get_tree().process_frame
    await _shot("inventory_02_panel_empty")
    ok = _check("토글 후 패널 visible (빈 결)",
        ui._inventory_panel.visible) and ok

    # ============================================================
    # 일부 보유 — add_item 후 결
    # ============================================================
    RunManager.add_item("food", 5)
    RunManager.add_item("repair_kit", 1)
    RunManager.add_item("rare_part", 3)
    await get_tree().process_frame
    await _shot("inventory_03_partial")
    ok = _check("HUD 보유 결 표시 (식량 5, 응급수리키트 1, 희귀 부품 3)",
        "식량 5" in ui._inventory_hud_label.text
        and "응급수리키트 1" in ui._inventory_hud_label.text
        and "희귀 부품 3" in ui._inventory_hud_label.text) and ok
    ok = _check("패널 자식 결 > 0 (카테고리 + 아이템)",
        ui._inventory_container.get_child_count() > 0) and ok

    # ============================================================
    # 사용 버튼 — repair_kit 사용
    # ============================================================
    RunManager.run_data["body_hp"] = 100
    RunManager.run_data["body_max_hp"] = 150
    RunManager.use_item("repair_kit")
    await get_tree().process_frame
    await _shot("inventory_04_after_use")
    ok = _check("사용 후 repair_kit erase",
        not RunManager.run_data["inventory"].has("repair_kit")) and ok
    ok = _check("사용 후 body_hp +25",
        RunManager.run_data["body_hp"] == 125) and ok
    ok = _check("HUD 갱신 — 응급수리키트 결 미표시 (erase)",
        not ("응급수리키트" in ui._inventory_hud_label.text)) and ok

    # 패널 닫기
    ui._on_show_inventory_pressed()
    await get_tree().process_frame
    ok = _check("재토글 후 패널 invisible",
        not ui._inventory_panel.visible) and ok

    return ok
