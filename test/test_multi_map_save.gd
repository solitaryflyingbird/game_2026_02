extends Node

# M-4 — 다중 맵 세이브/로드 직렬화 검증.
# 시나리오: ruin_01 에서 세이브 → 로드 → current_map_id / player_pos / 양 맵 visited 일치.

const SAVE_PATH := "user://save/slot_0.save"

var _checks: Array = []
var _main: Node


func _ready() -> void:
    print("=== M-4 다중 맵 세이브/로드 자동 검증 시작 ===")
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

    # 시작 + intro 소비
    GameManager.start_run()
    await _consume_dialogues()

    # field (13, 6) → (14, 6) → ruin 전이
    RunManager.run_data["player_pos"] = Vector2i(13, 6)
    RunManager.run_data["actions_remaining"] = 8
    RunManager.try_move(Vector2i(1, 0))
    await get_tree().process_frame
    ok = _check("ruin_01 진입 OK",
        RunManager.run_data["current_map_id"] == "ruin_01") and ok

    # ruin 안 (3, 4) → (4, 4) ruin_dust 발화 → 소비
    RunManager.run_data["player_pos"] = Vector2i(3, 4)
    RunManager.run_data["actions_remaining"] = 8
    RunManager.try_move(Vector2i(1, 0))
    await _consume_dialogues()

    # 세이브 (phase=map, ruin_01 에 있음)
    var pos_before: Vector2i = RunManager.run_data["player_pos"]
    var map_before: String = RunManager.run_data["current_map_id"]
    var field_visited_size: int = RunManager.run_data["visited_by_map"]["field_01"].size()
    var ruin_visited_size: int = RunManager.run_data["visited_by_map"]["ruin_01"].size()

    var ok_save: bool = GameManager.save()
    ok = _check("ruin_01 에서 save() = true",
        ok_save) and ok

    # 파일 검증 — Vector2i / current_map_id / visited_by_map 직렬화
    var f_read := FileAccess.open(SAVE_PATH, FileAccess.READ)
    var content := f_read.get_as_text()
    f_read.close()
    var parsed = str_to_var(content)
    ok = _check("저장 파일 파싱 성공",
        parsed != null and parsed is Dictionary) and ok
    var rd_saved: Dictionary = parsed.get("run_data", {})
    ok = _check("저장 파일 run_data.current_map_id == 'ruin_01'",
        rd_saved.get("current_map_id") == "ruin_01") and ok
    ok = _check("저장 파일 run_data.player_pos 가 Vector2i 결",
        rd_saved.get("player_pos") is Vector2i
        and rd_saved.get("player_pos") == pos_before) and ok
    ok = _check("저장 파일 run_data.visited_by_map 양 맵 결",
        rd_saved.get("visited_by_map", {}).has("field_01")
        and rd_saved.get("visited_by_map", {}).has("ruin_01")) and ok

    # return_to_title → load
    GameManager.return_to_title()
    await get_tree().process_frame
    var ok_load: bool = GameManager.load_save()
    await get_tree().process_frame
    ok = _check("load_save() = true", ok_load) and ok

    # 복원 검증
    ok = _check("load 후 current_map_id == 'ruin_01'",
        RunManager.run_data.get("current_map_id") == map_before) and ok
    ok = _check("load 후 player_pos 일치",
        RunManager.run_data.get("player_pos") == pos_before) and ok
    ok = _check("load 후 visited_by_map[field_01] 크기 일치",
        RunManager.run_data["visited_by_map"]["field_01"].size() == field_visited_size) and ok
    ok = _check("load 후 visited_by_map[ruin_01] 크기 일치",
        RunManager.run_data["visited_by_map"]["ruin_01"].size() == ruin_visited_size) and ok

    # load 후 try_move 정상 작동
    var moved: bool = RunManager.try_move(Vector2i(1, 0))
    ok = _check("load 후 try_move 정상 작동", moved) and ok

    # ============================================================
    # 옛 결 세이브 마이그레이션 검증
    # ============================================================
    GameManager.return_to_title()
    await get_tree().process_frame

    # 옛 결 fixture 직접 박기 (visited_tiles / explored_tiles 키, current_map_id 누락)
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
        },
        "run_data": {
            "phase": "map",
            "body_hp": 150, "body_max_hp": 150,
            "arm_instances": {}, "equipped_arms": {"L": null, "R": null},
            "next_arm_instance_id": 1, "arm_inventory_max": 6,
            "meta": {"big_run_count": 0},
            "research_data": 0, "seen_events": {},
            # 옛 결 — 1 맵 결의 visited / explored
            "player_pos": Vector2i(3, 6),
            "day": 1, "day_max": 10,
            "actions_per_day": 8, "actions_remaining": 5,
            "visited_tiles": { Vector2i(1, 6): true, Vector2i(2, 6): true, Vector2i(3, 6): true },
            "explored_tiles": {},
            "seen_this_run": {},
            "pending_combat": {},
        },
    }
    var f_w := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    f_w.store_string(var_to_str(legacy_payload))
    f_w.close()

    var ok_legacy_load: bool = GameManager.load_save()
    await get_tree().process_frame
    ok = _check("옛 결 세이브 — load_save() = true",
        ok_legacy_load) and ok
    ok = _check("마이그레이션 후 current_map_id == STARTING_MAP",
        RunManager.run_data.get("current_map_id") == GameData.STARTING_MAP) and ok
    ok = _check("마이그레이션 후 visited_by_map[STARTING] 옛 visited 결 보존",
        RunManager.run_data["visited_by_map"][GameData.STARTING_MAP].size() == 3) and ok
    ok = _check("마이그레이션 후 explored_by_map[STARTING] 비어있음",
        RunManager.run_data["explored_by_map"][GameData.STARTING_MAP].is_empty()) and ok
    ok = _check("마이그레이션 후 옛 visited_tiles 키 폐기",
        not RunManager.run_data.has("visited_tiles")) and ok
    ok = _check("마이그레이션 후 옛 explored_tiles 키 폐기",
        not RunManager.run_data.has("explored_tiles")) and ok
    ok = _check("마이그레이션 후 player_pos 보존",
        RunManager.run_data["player_pos"] == Vector2i(3, 6)) and ok

    return ok
