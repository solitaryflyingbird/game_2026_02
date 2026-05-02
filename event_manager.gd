extends Node

# ============================================================
# 이벤트 매니저 — 안 4 (kind 분리 + chain).
# 한 이벤트는 단일 책임 단위. kind ∈ {"dialogue", "effect", "movie", "choice"}.
# 1A: dialogue 만. 1A-2: + run_start 트리거. 2 (ABD): + effect / choice / chain.
# 미구현 kind (movie 등) 는 스텁 — push_warning + 즉시 종료.
#
# event_state 는 이벤트 활성 동안 (chain 진행 중 포함) 채워지고 비활성 시 {}.
# chain 의 chain_root_id 는 chain 의 첫 이벤트로 고정 (seen_events 카운트 키).
# ============================================================

signal event_state_changed
# event_resolved.result 스키마: { "event_id": String  # = chain_root_id }
signal event_resolved(result: Dictionary)


# 이벤트(또는 chain) 활성 여부. UI / 외부 가드용.
func is_active() -> bool:
    return not event_state.is_empty()


# 이벤트 진행 중 일시 상태. 비활성 시 {}.
# 스키마 (kind 별 필드 다름):
#   { event_id: String,
#     kind: "dialogue" | "effect" | "choice" | ...,
#     phase: "awaiting_input" | "running",
#     chain_root_id: String,        # chain 의 첫 이벤트 id (seen_events 카운트 키)
#     line_idx: int                 # dialogue 만 사용
#   }
var event_state: Dictionary = {}


func _ready() -> void:
    _register_console_commands()


# ============================================================
# 이벤트 진입 / 진행 / 종료
# ============================================================

# 이벤트 시작. RunManager.move_to_node 의 type "event" 분기 / _start_internal_run
# 의 run_start 트리거에서 호출. chain 의 시작점 (= chain_root_id 가 자기 자신).
func begin_event(event_id: String, _context: Dictionary) -> void:
    _begin_event_internal(event_id, event_id)


# chain 전이 — 이전 이벤트의 next 필드로 들어올 때. chain_root_id 유지.
func _transition_to_event(event_id: String) -> void:
    var chain_root: String = event_state.get("chain_root_id", event_id)
    _begin_event_internal(event_id, chain_root)


# 공용 진입 핸들러. chain_root 인자로 root 추적.
func _begin_event_internal(event_id: String, chain_root: String) -> void:
    if not GameData.EVENTS.has(event_id):
        push_warning("begin_event: 알 수 없는 event_id '%s'" % event_id)
        return
    var def: Dictionary = GameData.EVENTS[event_id]
    var kind: String = def.get("kind", "")
    match kind:
        "dialogue":
            event_state = {
                "event_id": event_id,
                "kind": "dialogue",
                "phase": "awaiting_input",
                "chain_root_id": chain_root,
                "line_idx": 0,
            }
            event_state_changed.emit()
        "effect":
            event_state = {
                "event_id": event_id,
                "kind": "effect",
                "phase": "running",
                "chain_root_id": chain_root,
            }
            event_state_changed.emit()
            _apply_event_actions(def.get("effects", []))
            _finalize_event()
        "choice":
            event_state = {
                "event_id": event_id,
                "kind": "choice",
                "phase": "awaiting_input",
                "chain_root_id": chain_root,
            }
            event_state_changed.emit()
        _:
            push_warning("begin_event: 미지원 kind '%s' — 스텁 (즉시 종료)" % kind)
            event_state = {
                "event_id": event_id,
                "kind": kind,
                "phase": "running",
                "chain_root_id": chain_root,
            }
            event_state_changed.emit()
            _finalize_event()


# dialogue kind 의 라인 1개 진행. UI 또는 콘솔이 호출.
# 마지막 라인 통과 시 자동 _finalize_event.
func advance_line() -> void:
    if event_state.is_empty():
        push_warning("advance_line: 이벤트 비활성")
        return
    if event_state.get("kind") != "dialogue":
        push_warning("advance_line: kind != 'dialogue' (got: %s)" % event_state.get("kind"))
        return
    var event_id: String = event_state["event_id"]
    var def: Dictionary = GameData.EVENTS.get(event_id, {})
    var lines: Array = def.get("lines", [])
    var next_idx: int = event_state.get("line_idx", 0) + 1
    if next_idx >= lines.size():
        _finalize_event()
        return
    event_state["line_idx"] = next_idx
    event_state_changed.emit()


# choice kind 에서 선택지 인덱스 결정. 선택지의 next 로 chain 전이.
# UI (event_ui 의 버튼) 또는 콘솔 (event_choose) 이 호출.
func select_choice(idx: int) -> void:
    if event_state.is_empty():
        push_warning("select_choice: 이벤트 비활성")
        return
    if event_state.get("kind") != "choice":
        push_warning("select_choice: kind != 'choice' (got: %s)" % event_state.get("kind"))
        return
    var event_id: String = event_state["event_id"]
    var def: Dictionary = GameData.EVENTS.get(event_id, {})
    var choices: Array = def.get("choices", [])
    if idx < 0 or idx >= choices.size():
        push_warning("select_choice: idx %d 범위 밖 (size %d)" % [idx, choices.size()])
        return
    var picked: Dictionary = choices[idx]
    var next_id = picked.get("next", null)
    if next_id == null:
        # 가지에 next 없음 — chain 종료.
        _resolve_chain()
        return
    if not GameData.EVENTS.has(next_id):
        push_warning("select_choice: next '%s' 미등록 — chain 종료" % next_id)
        _resolve_chain()
        return
    _transition_to_event(next_id)


# Type 1 효과 적용. RunManager.apply_event_action 위임 — 디스패처는 RunManager 내부.
# (안 4 §0-E — escape 없음. 신규 효과 = RunManager 의 _apply_<type> 신설 강제.)
func _apply_event_actions(actions: Array) -> void:
    for action in actions:
        RunManager.apply_event_action(action)


# 현재 이벤트 종료. def.next 가 있으면 chain 전이, 없으면 chain 종료.
# dialogue 의 마지막 라인 advance / effect 의 모든 효과 적용 후 호출.
func _finalize_event() -> void:
    var current_id: String = event_state.get("event_id", "")
    var def: Dictionary = GameData.EVENTS.get(current_id, {})
    var next_id = def.get("next", null)
    if next_id != null and GameData.EVENTS.has(next_id):
        _transition_to_event(next_id)
        return
    _resolve_chain()


# chain 전체 종료. event_resolved 발화 + event_state 비움.
# 카운트 키 = chain_root_id (chain 한 단위에 1회만).
func _resolve_chain() -> void:
    var result: Dictionary = {
        "event_id": event_state.get("chain_root_id", event_state.get("event_id", "")),
    }
    event_state = {}
    event_resolved.emit(result)
    event_state_changed.emit()


# ============================================================
# 트리거 평가 — 어떤 이벤트가 발생할지 결정
# ============================================================
# 글로벌 트리거 풀에서 매치 + once_per 필터 + 가중치 추첨.
# 타일 슬롯이 직접 호출하는 이벤트 (regression_speech / repair_choice 등) 는
# trigger 필드 없이 라이브러리 결로만 등재 — 여기서 매치되지 않음 (의도).
#
# 트리거 풀:
#   - "run_start":  context 무관. 매 내부 런 시작 직후.
#   - "on_rest":    context 무관. RunManager.rest() 가 호출.

func resolve_event(trigger_type: String, _context: Dictionary) -> String:
    var candidates: Array = []
    var weights: Array = []
    var total_weight: int = 0
    for id in GameData.EVENTS.keys():
        var def: Dictionary = GameData.EVENTS[id]
        var trigger: Dictionary = def.get("trigger", {})
        if trigger.get("type", "") != trigger_type:
            continue
        if trigger_type != "run_start" and trigger_type != "on_rest":
            push_warning("resolve_event: 알 수 없는 trigger type '%s'" % trigger_type)
            continue
        # once_per 필터 — big_run (큰 런 통과) / internal_run (회차 1회).
        var op: String = def.get("once_per", "")
        if op == "big_run":
            var seen: Dictionary = RunManager.big_run_data.get("seen_events", {})
            if seen.get(id, 0) > 0:
                continue
        elif op == "internal_run":
            var seen_run: Dictionary = RunManager.run_data.get("seen_this_run", {})
            if seen_run.get(id, false):
                continue
        var w: int = int(def.get("weight", 1))
        candidates.append(id)
        weights.append(w)
        total_weight += w
    if candidates.is_empty():
        return ""
    if total_weight <= 0:
        return candidates[0]
    var pick: int = randi() % total_weight
    var acc: int = 0
    for i in candidates.size():
        acc += weights[i]
        if pick < acc:
            return candidates[i]
    return candidates[-1]


# ============================================================
# LimboConsole
# ============================================================

func _register_console_commands() -> void:
    LimboConsole.register_command(_cmd_event_advance, "event_advance",
        "이벤트 라인 진행 (dialogue kind)")
    LimboConsole.register_command(_cmd_event_choose, "event_choose",
        "선택지 결정 (choice kind). 인자: <idx>")
    LimboConsole.register_command(_cmd_show_event, "show_event",
        "event_state 덤프")


func _cmd_event_advance() -> void:
    advance_line()


func _cmd_event_choose(idx: int) -> void:
    select_choice(idx)


func _cmd_show_event() -> void:
    LimboConsole.info(JSON.stringify(event_state, "  "))
