extends Node

# Stage 2 (effect + chain + choice 통합) 자동 검증 (그리드 결).
# 시나리오:
#   spawn (1,6) → (3,6) regression_speech 통과 → (5,6) repair_choice → 가지 →
#   가지의 next (effect kind) → 그 다음 next (dialogue) → chain 종료.
# 두 가지 (팔/몸) 모두 검증.

const SHOT_DIR := "res://test_screenshots/"

var _checks: Array = []
var _main: Node


func _ready() -> void:
    print("=== Stage 2 (effect + chain + choice) 자동 검증 시작 (그리드) ===")
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


# dialogue 만 자동 advance. choice 는 그대로 둠.
func _consume_dialogues() -> void:
    while not EventManager.event_state.is_empty() and \
            EventManager.event_state.get("kind") == "dialogue":
        EventManager.advance_line()
    await get_tree().process_frame


func _l_arm() -> Dictionary:
    var instance_id = RunManager.run_data.get("equipped_arms", {}).get("L")
    if instance_id == null:
        return {}
    return RunManager.run_data.get("arm_instances", {}).get(instance_id, {})


# 동쪽 N칸 이동 (단계마다 advance dialogue 자동 처리).
func _move_east(n: int) -> void:
    for i in range(n):
        RunManager.try_move(Vector2i(1, 0))
        await _consume_dialogues()


func _run_scenario() -> bool:
    var ok := true

    # ========== 섹션 1: 시작 + intro_speech 소비 ==========
    GameManager.start_run()
    await _consume_dialogues()

    ok = _check("intro 소비 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok

    # ========== 섹션 2: (3,6) regression_speech 통과 ==========
    # try_move 동 2번 → (3,6) → regression 발화 → 소비
    RunManager.try_move(Vector2i(1, 0))   # (2,6)
    RunManager.try_move(Vector2i(1, 0))   # (3,6) regression
    await _consume_dialogues()

    ok = _check("regression 소비 후 phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok

    # ========== 섹션 3: (5,6) repair_choice 진입 ==========
    var arm_before: Dictionary = _l_arm()
    var arm_hp_before: int = arm_before.get("hp", 0)
    var arm_max_before: int = arm_before.get("max_hp", 0)

    RunManager.try_move(Vector2i(1, 0))   # (4,6)
    RunManager.try_move(Vector2i(1, 0))   # (5,6) repair_choice
    await _shot("2_01_repair_choice")

    ok = _check("repair_choice 발화 — phase = 'event'",
        RunManager.run_data.get("phase") == "event") and ok
    ok = _check("event_id = 'repair_choice'",
        EventManager.event_state.get("event_id") == "repair_choice") and ok
    ok = _check("event_state.kind = 'choice'",
        EventManager.event_state.get("kind") == "choice") and ok
    ok = _check("chain_root_id = 'repair_choice'",
        EventManager.event_state.get("chain_root_id") == "repair_choice") and ok

    # ========== 섹션 4: 팔 수리 — choice → effect → dialogue ==========
    EventManager.select_choice(0)
    await _shot("2_02_after_arm_repair_dialogue")

    ok = _check("선택 후 chain 전이 — event_id = 'repair_done_arm'",
        EventManager.event_state.get("event_id") == "repair_done_arm") and ok
    ok = _check("선택 후 kind = 'dialogue'",
        EventManager.event_state.get("kind") == "dialogue") and ok
    ok = _check("chain_root_id 유지 = 'repair_choice'",
        EventManager.event_state.get("chain_root_id") == "repair_choice") and ok
    ok = _check("phase = 'event' 유지",
        RunManager.run_data.get("phase") == "event") and ok

    var arm_after: Dictionary = _l_arm()
    ok = _check("팔 수리 효과 — arm hp += 20",
        arm_after.get("hp", 0) == arm_hp_before + 20,
        "before=%d after=%d expect=%d" % [
            arm_hp_before, arm_after.get("hp", 0), arm_hp_before + 20]) and ok
    ok = _check("팔 수리 효과 — arm max_hp += 20",
        arm_after.get("max_hp", 0) == arm_max_before + 20) and ok

    # ========== 섹션 5: 마지막 라인 advance → chain 종료 ==========
    EventManager.advance_line()
    await _shot("2_03_chain_done_back_to_grid")

    ok = _check("chain 종료 — event_state = {}",
        EventManager.event_state.is_empty()) and ok
    ok = _check("chain 종료 — phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok
    ok = _check("seen_events[repair_choice] = 1 (chain root 만)",
        RunManager.big_run_data["seen_events"].get("repair_choice", 0) == 1) and ok
    ok = _check("seen_events[repair_arm] 미존재",
        RunManager.big_run_data["seen_events"].get("repair_arm", 0) == 0) and ok
    ok = _check("seen_events[repair_done_arm] 미존재",
        RunManager.big_run_data["seen_events"].get("repair_done_arm", 0) == 0) and ok

    # ========== 섹션 6: 재진입 — once_per 필터 ==========
    # (5,6) → (4,6) → (5,6) 재진입
    RunManager.try_move(Vector2i(-1, 0))   # (4,6)
    RunManager.try_move(Vector2i(1, 0))    # (5,6) 재진입

    ok = _check("재진입 시 phase = 'map' (이벤트 미발생)",
        RunManager.run_data.get("phase") == "map") and ok
    ok = _check("재진입 시 event_state 비활성",
        EventManager.event_state.is_empty()) and ok

    # ========== 섹션 7: 회귀 후 — 슬롯 internal_run 재발화 ==========
    RunManager.end_internal_run("cleared")
    await get_tree().process_frame
    # 회귀 직후 intro 다시 발화 → 소비 (regression 도 첫 칸 진입 시 재발화)
    await _consume_dialogues()

    ok = _check("회귀 후 seen_events[repair_choice] 누적 유지 (>=1)",
        RunManager.big_run_data["seen_events"].get("repair_choice", 0) >= 1) and ok

    # 회귀 후 spawn (1,6) — 동 2칸 → (3,6) regression 재발화 (internal_run)
    RunManager.try_move(Vector2i(1, 0))   # (2,6)
    RunManager.try_move(Vector2i(1, 0))   # (3,6) — regression 재발화
    ok = _check("회귀 후 (3,6) 진입 — regression 재발화",
        RunManager.run_data.get("phase") == "event"
        and EventManager.event_state.get("event_id") == "regression_speech") and ok
    await _consume_dialogues()

    # 동 2칸 더 → (5,6) repair_choice 재발화
    RunManager.try_move(Vector2i(1, 0))   # (4,6)
    RunManager.try_move(Vector2i(1, 0))   # (5,6) — repair 재발화
    ok = _check("회귀 후 (5,6) 진입 — repair_choice 재발화",
        RunManager.run_data.get("phase") == "event"
        and EventManager.event_state.get("event_id") == "repair_choice") and ok
    # chain 종료 — 팔 수리 가지 (또 한 번)
    EventManager.select_choice(0)
    EventManager.advance_line()
    await get_tree().process_frame

    # ========== 섹션 8: reset + 몸 수리 가지 ==========
    GameManager.return_to_title()
    await get_tree().process_frame
    GameManager.start_run()
    await _consume_dialogues()  # intro_speech (fresh seen_events)

    # spawn → (3,6) regression → (5,6) repair_choice
    RunManager.try_move(Vector2i(1, 0))
    RunManager.try_move(Vector2i(1, 0))
    await _consume_dialogues()  # regression

    var body_hp_before: int = RunManager.run_data.get("body_hp", 0)
    var body_max_before: int = RunManager.run_data.get("body_max_hp", 0)

    RunManager.try_move(Vector2i(1, 0))   # (4,6)
    RunManager.try_move(Vector2i(1, 0))   # (5,6) repair_choice
    await get_tree().process_frame

    ok = _check("reset 후 repair_choice 다시 발화",
        EventManager.event_state.get("event_id") == "repair_choice") and ok

    EventManager.select_choice(1)  # 몸 수리
    await _shot("2_04_after_body_repair_dialogue")

    ok = _check("몸 수리 가지 — event_id = 'repair_done_body'",
        EventManager.event_state.get("event_id") == "repair_done_body") and ok
    ok = _check("몸 수리 효과 — body_hp += 20",
        RunManager.run_data.get("body_hp") == body_hp_before + 20,
        "before=%d after=%d" % [
            body_hp_before, RunManager.run_data.get("body_hp", 0)]) and ok
    ok = _check("몸 수리 효과 — body_max_hp += 20",
        RunManager.run_data.get("body_max_hp") == body_max_before + 20) and ok

    EventManager.advance_line()
    await get_tree().process_frame

    ok = _check("body 가지 chain 종료 — phase = 'map'",
        RunManager.run_data.get("phase") == "map") and ok
    ok = _check("body 가지 — seen_events[repair_choice] = 1 (new big_run)",
        RunManager.big_run_data["seen_events"].get("repair_choice", 0) == 1) and ok

    return ok
