extends Node

# I-5 — 인벤토리 세이브/로드 + 마이그레이션 검증.

const SAVE_PATH := "user://save/slot_0.save"

var _checks: Array = []
var _main: Node


func _ready() -> void:
    print("=== I-5 인벤토리 세이브/로드 자동 검증 시작 ===")
    if FileAccess.file_exists(SAVE_PATH):
        DirAccess.remove_absolute(SAVE_PATH)
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


func _consume_dialogues() -> void:
    while not EventManager.event_state.is_empty() and \
            EventManager.event_state.get("kind") == "dialogue":
        EventManager.advance_line()
    await get_tree().process_frame


func _run_scenario() -> bool:
    var ok := true

    GameManager.start_run()
    await _consume_dialogues()

    # 인벤토리 결 변경
    RunManager.add_item("food", 5)
    RunManager.add_item("repair_kit", 2)
    RunManager.add_item("rare_part", 3)
    RunManager.add_item("key", 1)

    var inv_before: Dictionary = RunManager.run_data["inventory"].duplicate()
    var tools_before: Dictionary = RunManager.run_data["tools"].duplicate()
    var big_inv_before: Dictionary = RunManager.big_run_data["inventory"].duplicate()

    # ============================================================
    # 신규 결 직렬화 + 복원
    # ============================================================
    var ok_save: bool = GameManager.save()
    ok = _check("save() = true", ok_save) and ok

    GameManager.return_to_title()
    await get_tree().process_frame
    var ok_load: bool = GameManager.load_save()
    await get_tree().process_frame
    ok = _check("load_save() = true", ok_load) and ok

    ok = _check("load 후 inventory 일치 (food/repair_kit/rare_part)",
        RunManager.run_data["inventory"] == inv_before) and ok
    ok = _check("load 후 tools['key'] = 1",
        RunManager.run_data["tools"] == tools_before) and ok
    ok = _check("load 후 big_run_data['inventory'] 일치",
        RunManager.big_run_data["inventory"] == big_inv_before) and ok

    # ============================================================
    # 옛 결 마이그레이션 — inventory / tools 결 없는 옛 세이브
    # ============================================================
    GameManager.return_to_title()
    await get_tree().process_frame

    var legacy_payload := {
        "version": 1,
        "saved_at": "legacy",
        "big_run_data": {
            "phase": "map",
            "body_hp": 150, "body_max_hp": 150,
            "arm_instances": {}, "equipped_arms": {"L": null, "R": null},
            "next_arm_instance_id": 1, "arm_inventory_max": 6,
            "meta": {"big_run_count": 0},
            "research_data": 0, "seen_events": {},
            # inventory 결 없음
        },
        "run_data": {
            "phase": "map",
            "body_hp": 150, "body_max_hp": 150,
            "arm_instances": {}, "equipped_arms": {"L": null, "R": null},
            "next_arm_instance_id": 1, "arm_inventory_max": 6,
            "meta": {"big_run_count": 0},
            "research_data": 0, "seen_events": {},
            "current_map_id": "field_01",
            "player_pos": Vector2i(1, 6),
            "day": 1, "day_max": 10,
            "actions_per_day": 8, "actions_remaining": 8,
            "visited_by_map": {"field_01": {Vector2i(1, 6): true}},
            "explored_by_map": {"field_01": {}},
            "seen_this_run": {},
            "pending_combat": {},
            # inventory / tools 결 없음
        },
    }
    var f_w := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    f_w.store_string(var_to_str(legacy_payload))
    f_w.close()

    var ok_legacy: bool = GameManager.load_save()
    await get_tree().process_frame
    ok = _check("옛 결 세이브 — load_save() = true", ok_legacy) and ok
    ok = _check("마이그레이션 후 big_run_data['inventory'] = {} (빈 dict)",
        RunManager.big_run_data.has("inventory")
        and RunManager.big_run_data["inventory"].is_empty()) and ok
    ok = _check("마이그레이션 후 run_data['inventory'] = {} (big 사본)",
        RunManager.run_data.has("inventory")
        and RunManager.run_data["inventory"].is_empty()) and ok
    ok = _check("마이그레이션 후 run_data['tools'] = {} (빈 결)",
        RunManager.run_data.has("tools")
        and RunManager.run_data["tools"].is_empty()) and ok

    return ok
