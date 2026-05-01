extends Node

# 세이브 / 로드 통합 검증.
# main.tscn 인스턴스 + 시뮬 + 저장 + 로드 + 상태 일치 확인.
# 정책 게이팅 (phase != "map" 거부) + 잘못된 파일 (JSON 깨짐 / version 누락) 거부도 검증.
#
# 실행: godot --path "<프로젝트>" res://test/test_save_load.tscn
#       (--headless OK — 스크린샷 없음)

const SAVE_PATH := "user://save/slot_0.save"

var _checks: Array = []
var _main: Node


func _ready() -> void:
    print("=== 세이브/로드 자동 검증 시작 ===")
    # 베이스라인 — 이전 세이브 정리
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
    # 섹션 1: 기반 — 폴더, 초기 상태
    # ============================================================
    ok = _check("save 폴더 존재",
        DirAccess.dir_exists_absolute("user://save/")) and ok
    ok = _check("초기 has_save = false (베이스라인 정리됨)",
        not GameManager.has_save()) and ok

    # ============================================================
    # 섹션 2: 활성 런 없을 때 save 거부
    # ============================================================
    var ok_save: bool = GameManager.save()
    ok = _check("런 없음 — save() = false",
        not ok_save) and ok

    # ============================================================
    # 섹션 3: 시뮬 진행 + phase != map 시 save 거부
    # ============================================================
    GameManager.start_run()
    await get_tree().process_frame
    # 이 시점 phase = "event" (intro_speech 발화)
    ok = _check("start_run 후 phase = 'event' (intro 발화)",
        RunManager.run_data.get("phase") == "event") and ok

    ok_save = GameManager.save()
    ok = _check("phase = 'event' — save() 거부",
        not ok_save) and ok

    # intro 소비 → phase = map
    await _consume_dialogues()
    ok = _check("intro 소비 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok

    # 노드 5 진입 → regression 발화 → 소비
    RunManager.move_to_node(5)
    await _consume_dialogues()

    # ============================================================
    # 섹션 4: 정상 save
    # ============================================================
    var current_node_before: int = RunManager.run_data.get("current_node_id", -1)
    var body_hp_before: int = RunManager.run_data.get("body_hp", 0)
    var seen_intro_before: int = RunManager.big_run_data["seen_events"].get("intro_speech", 0)
    var seen_regression_before: int = RunManager.big_run_data["seen_events"].get("regression_speech", 0)

    # 저장 버튼이 visible 한 상태 캡처 (phase = "map")
    await get_tree().process_frame
    await get_tree().process_frame
    var img1: Image = get_viewport().get_texture().get_image()
    img1.save_png("res://test_screenshots/save_01_button_visible.png")
    print(">>> screenshot: save_01_button_visible.png")

    ok_save = GameManager.save()
    ok = _check("phase = 'map' — save() = true",
        ok_save) and ok

    # 저장 직후 피드백 라벨 표시 캡처
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
    # 섹션 5: 파일 내용 JSON 파싱 + 스키마
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

    ok = _check("load 후 current_node_id 일치",
        RunManager.run_data.get("current_node_id") == current_node_before,
        "before=%d after=%d" % [current_node_before, RunManager.run_data.get("current_node_id", -1)]) and ok
    ok = _check("load 후 body_hp 일치",
        RunManager.run_data.get("body_hp") == body_hp_before) and ok
    ok = _check("load 후 seen_events[intro_speech] 일치",
        RunManager.big_run_data["seen_events"].get("intro_speech", 0) == seen_intro_before) and ok
    ok = _check("load 후 seen_events[regression_speech] 일치",
        RunManager.big_run_data["seen_events"].get("regression_speech", 0) == seen_regression_before) and ok
    ok = _check("load 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok

    # ============================================================
    # 섹션 6.5: load 후 인터랙션 — move_to_node 가 실제 작동하는가
    # ============================================================
    var current_after_load: int = RunManager.run_data.get("current_node_id", -1)
    var current_node = RunManager.get_current_node()
    var connections: Array = current_node.get("connections", [])
    ok = _check("load 후 연결된 인접 노드 존재 (= 이동 가능)",
        connections.size() > 0,
        "current=%d connections=%s" % [current_after_load, connections]) and ok

    # 일반 노드 (이벤트·연구 트리거 안 거는) 인접 찾기
    var safe_target: int = -1
    for adj_id in connections:
        var adj_node = RunManager.get_node_by_id(adj_id)
        var ttype: String = adj_node.get("type", "")
        # research 트리거시 phase 변경, 일반 enemy 도 OK 임 (event 만 분기 트리거)
        # 단순한 검증을 위해 type 이 비거나 enemy_id 만 있는 노드 선호
        if ttype == "":
            safe_target = adj_id
            break
    if safe_target == -1 and connections.size() > 0:
        safe_target = connections[0]  # 안전 노드 없으면 첫 인접

    # 직접 API — RunManager.move_to_node
    var pre_phase: String = RunManager.run_data.get("phase", "")
    var moved: bool = RunManager.move_to_node(safe_target)
    ok = _check("load 후 move_to_node 직호출 성공",
        moved, "target=%d pre_phase=%s" % [safe_target, pre_phase]) and ok
    ok = _check("load 후 current_node_id 갱신됨",
        RunManager.run_data.get("current_node_id") == safe_target,
        "expected=%d actual=%d" % [safe_target, RunManager.run_data.get("current_node_id", -2)]) and ok

    # 맵 버튼 객체가 제대로 _node_buttons 에 들어있는가 (UI 캐시 stale 검증)
    var run_ui_node = _main.get_node("run_ui")
    var node_buttons_dict = run_ui_node._node_buttons
    ok = _check("UI 의 _node_buttons dict 채워져 있음 (재load 후에도)",
        node_buttons_dict.size() > 0,
        "_node_buttons size = %d" % node_buttons_dict.size()) and ok

    # 인접 노드의 버튼이 disabled = false 여야 클릭 가능
    if safe_target != -1 and node_buttons_dict.has(safe_target):
        # 방금 move_to_node 로 phase 변경됐을 수도 있어 검증 의미 약화. pre-move 시점 검증으로 분리하자.
        pass

    # ============================================================
    # 섹션 7: 잘못된 파일 거부
    # ============================================================
    # version 키 없음
    var f_bad := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    f_bad.store_string('{"big_run_data": {}, "run_data": {}}')
    f_bad.close()
    ok_load = GameManager.load_save()
    ok = _check("version 키 없는 파일 — load 거부",
        not ok_load) and ok

    # 잘못된 JSON
    var f_garbage := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    f_garbage.store_string("not a json {{{")
    f_garbage.close()
    ok_load = GameManager.load_save()
    ok = _check("잘못된 JSON — load 거부",
        not ok_load) and ok

    # 파일 자체 없음
    DirAccess.remove_absolute(SAVE_PATH)
    ok = _check("파일 삭제 후 has_save = false",
        not GameManager.has_save()) and ok
    ok_load = GameManager.load_save()
    ok = _check("파일 없음 — load_save = false",
        not ok_load) and ok

    return ok
