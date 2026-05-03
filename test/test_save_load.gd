extends Node

# 세이브 / 로드 통합 검증 (그리드 결).
# main.tscn 인스턴스 + 시뮬 + 저장 + 로드 + 상태 일치.
# Vector2i 직렬화 round-trip 포함.

const SAVE_PATH := "user://save/slot_0.save"

var _checks: Array = []
var _main: Node


func _ready() -> void:
    print("=== 세이브/로드 자동 검증 시작 (그리드) ===")
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

    # ============================================================
    # 섹션 0: Vector2i var_to_str round-trip 사전검증
    # ============================================================
    var v := Vector2i(3, 7)
    var v_serialized := var_to_str(v)
    var v_restored = str_to_var(v_serialized)
    ok = _check("Vector2i var_to_str round-trip",
        v_restored is Vector2i and v_restored == v,
        "serialized=%s restored=%s" % [v_serialized, v_restored]) and ok

    # ============================================================
    # 섹션 1: 기반
    # ============================================================
    ok = _check("save 폴더 존재",
        DirAccess.dir_exists_absolute("user://save/")) and ok
    ok = _check("초기 has_save = false",
        not GameManager.has_save()) and ok

    # ============================================================
    # 섹션 2: 활성 런 없을 때 save 거부
    # ============================================================
    var ok_save: bool = GameManager.save()
    ok = _check("런 없음 — save() = false",
        not ok_save) and ok

    # ============================================================
    # 섹션 3: 시뮬 + phase != map 시 save 거부
    # ============================================================
    GameManager.start_run()
    await get_tree().process_frame
    ok = _check("start_run 후 phase = 'event'",
        RunManager.run_data.get("phase") == "event") and ok

    ok_save = GameManager.save()
    ok = _check("phase = 'event' — save() 거부",
        not ok_save) and ok

    await _consume_dialogues()
    ok = _check("intro 소비 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok

    # 동 2칸 → (3,6) regression → 소비
    RunManager.try_move(Vector2i(1, 0))
    RunManager.try_move(Vector2i(1, 0))
    await _consume_dialogues()

    # ============================================================
    # 섹션 4: 정상 save
    # ============================================================
    var player_pos_before: Vector2i = RunManager.run_data.get("player_pos")
    var day_before: int = RunManager.run_data.get("day", -1)
    var actions_before: int = RunManager.run_data.get("actions_remaining", -1)
    var body_hp_before: int = RunManager.run_data.get("body_hp", 0)
    var seen_intro_before: int = RunManager.big_run_data["seen_events"].get("intro_speech", 0)
    var seen_regression_before: int = RunManager.big_run_data["seen_events"].get("regression_speech", 0)
    var visited_before: Dictionary = RunManager.run_data.get("visited_by_map", {}).get(GameData.STARTING_MAP, {}).duplicate(true)

    await get_tree().process_frame
    await get_tree().process_frame
    var img1: Image = get_viewport().get_texture().get_image()
    img1.save_png("res://test_screenshots/save_01_button_visible.png")
    print(">>> screenshot: save_01_button_visible.png")

    ok_save = GameManager.save()
    ok = _check("phase = 'map' — save() = true", ok_save) and ok

    await get_tree().process_frame
    await get_tree().process_frame
    var img2: Image = get_viewport().get_texture().get_image()
    img2.save_png("res://test_screenshots/save_02_feedback.png")
    print(">>> screenshot: save_02_feedback.png")
    ok = _check("save 후 파일 존재",
        FileAccess.file_exists(SAVE_PATH)) and ok
    ok = _check("save 후 has_save() = true",
        GameManager.has_save()) and ok

    # ============================================================
    # 섹션 5: 파일 내용 + 스키마
    # ============================================================
    var f_read := FileAccess.open(SAVE_PATH, FileAccess.READ)
    var content := f_read.get_as_text()
    f_read.close()
    var parsed = str_to_var(content)
    ok = _check("저장 파일 var_to_str 직렬화 파싱 성공",
        parsed != null and parsed is Dictionary) and ok
    if parsed is Dictionary:
        ok = _check("저장 파일 version = 1",
            parsed.get("version") == 1) and ok
        ok = _check("저장 파일에 big_run_data 포함",
            parsed.has("big_run_data")) and ok
        ok = _check("저장 파일에 run_data 포함",
            parsed.has("run_data")) and ok
        ok = _check("저장 파일 saved_at 존재",
            parsed.has("saved_at")) and ok
        # Vector2i / 그리드 필드 확인
        var rd: Dictionary = parsed.get("run_data", {})
        ok = _check("run_data.player_pos 가 Vector2i 로 복원됨",
            rd.get("player_pos") is Vector2i,
            "type = %s value = %s" % [
                typeof(rd.get("player_pos")), str(rd.get("player_pos"))]) and ok
        ok = _check("run_data.day 직렬화",
            rd.get("day") == day_before) and ok

    # ============================================================
    # 섹션 6: return_to_title → load → 상태 일치
    # ============================================================
    GameManager.return_to_title()
    await get_tree().process_frame
    ok = _check("return_to_title 후 run_data 비움",
        RunManager.run_data.is_empty()) and ok
    ok = _check("return_to_title 후 app_phase = 'title'",
        GameManager.app_phase == "title") and ok

    var ok_load: bool = GameManager.load_save()
    ok = _check("load_save() = true",
        ok_load) and ok
    await get_tree().process_frame
    ok = _check("load 후 app_phase = 'in_run'",
        GameManager.app_phase == "in_run") and ok

    ok = _check("load 후 player_pos 일치",
        RunManager.run_data.get("player_pos") == player_pos_before,
        "before=%s after=%s" % [player_pos_before, RunManager.run_data.get("player_pos")]) and ok
    ok = _check("load 후 day 일치",
        RunManager.run_data.get("day") == day_before) and ok
    ok = _check("load 후 actions_remaining 일치",
        RunManager.run_data.get("actions_remaining") == actions_before) and ok
    ok = _check("load 후 body_hp 일치",
        RunManager.run_data.get("body_hp") == body_hp_before) and ok
    ok = _check("load 후 seen_events[intro_speech] 일치",
        RunManager.big_run_data["seen_events"].get("intro_speech", 0) == seen_intro_before) and ok
    ok = _check("load 후 seen_events[regression_speech] 일치",
        RunManager.big_run_data["seen_events"].get("regression_speech", 0) == seen_regression_before) and ok
    ok = _check("load 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok
    ok = _check("load 후 visited_by_map[STARTING] 크기 일치",
        RunManager.run_data.get("visited_by_map", {}).get(GameData.STARTING_MAP, {}).size() == visited_before.size()) and ok

    # ============================================================
    # 섹션 6.5: load 후 인터랙션 — try_move 가 실제 작동
    # ============================================================
    var pre_phase: String = RunManager.run_data.get("phase", "")
    var pos_pre_move: Vector2i = RunManager.run_data.get("player_pos")
    # 일단 (3,6) 에 있을 것 — 동쪽 (4,6) 으로 이동 가능 (open grass)
    var moved: bool = RunManager.try_move(Vector2i(1, 0))
    ok = _check("load 후 try_move 직호출 성공",
        moved, "pre_phase=%s pre_pos=%s" % [pre_phase, pos_pre_move]) and ok
    ok = _check("load 후 player_pos 갱신됨",
        RunManager.run_data.get("player_pos") == pos_pre_move + Vector2i(1, 0)) and ok

    # 그리드 UI tile_rects 채워져 있나
    var run_ui_node = _main.get_node("run_ui")
    var tile_rects = run_ui_node._tile_rects
    ok = _check("UI 의 _tile_rects dict 채워져 있음",
        tile_rects.size() > 0,
        "_tile_rects size = %d" % tile_rects.size()) and ok

    # ============================================================
    # 섹션 7: 잘못된 파일 거부
    # ============================================================
    var f_bad := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    f_bad.store_string('{"big_run_data": {}, "run_data": {}}')
    f_bad.close()
    ok_load = GameManager.load_save()
    ok = _check("version 키 없는 파일 — load 거부",
        not ok_load) and ok

    var f_garbage := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    f_garbage.store_string("not a json {{{")
    f_garbage.close()
    ok_load = GameManager.load_save()
    ok = _check("잘못된 JSON — load 거부",
        not ok_load) and ok

    DirAccess.remove_absolute(SAVE_PATH)
    ok = _check("파일 삭제 후 has_save = false",
        not GameManager.has_save()) and ok
    ok_load = GameManager.load_save()
    ok = _check("파일 없음 — load_save = false",
        not ok_load) and ok

    return ok
