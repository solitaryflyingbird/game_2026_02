extends Node

# ============================================================
# 이벤트 매니저 — 안 4 (kind 분리 + chain) 의 1A 단계 구현.
# 한 이벤트는 단일 책임 단위. kind ∈ {"dialogue", "effect", "movie", "choice"}.
# 1A: dialogue kind 만 실 구현. 나머지 kind 는 스텁 (push_warning + 즉시 종료).
#
# 상태(event_state) 는 이벤트 활성 동안만 채워지고 비활성 시 {}.
# BattleManager.battle_state 와 동일 결.
# ============================================================

signal event_state_changed
signal event_resolved(result: Dictionary)


# 이벤트 진행 중 일시 상태. 비활성 시 {}.
# 스키마:
#   { event_id: String,
#     kind: String,
#     phase: "awaiting_input" | "running",
#     chain_root_id: String,        # 1A 단계는 = event_id
#     line_idx: int                 # dialogue 만 사용
#   }
var event_state: Dictionary = {}


func _ready() -> void:
    _register_console_commands()


# ============================================================
# 이벤트 진입 / 진행 / 종료
# ============================================================

# 이벤트 시작. RunManager.move_to_node 의 type "event" 분기에서 호출.
# kind 별 디스패처 분기.
func begin_event(event_id: String, _context: Dictionary) -> void:
    if not GameData.EVENTS.has(event_id):
        push_warning("begin_event: 알 수 없는 event_id '%s'" % event_id)
        return
    var def: Dictionary = GameData.EVENTS[event_id]
    var kind: String = def.get("kind", "")
    match kind:
        "dialogue":
            _dispatch_dialogue(event_id, def)
        _:
            # 1A 단계는 dialogue 외 미지원. 스텁: 즉시 종료.
            push_warning("begin_event: 1A 단계 미지원 kind '%s'" % kind)
            event_state = {
                "event_id": event_id,
                "kind": kind,
                "phase": "running",
                "chain_root_id": event_id,
            }
            event_state_changed.emit()
            _finalize_event()


func _dispatch_dialogue(event_id: String, _def: Dictionary) -> void:
    event_state = {
        "event_id": event_id,
        "kind": "dialogue",
        "phase": "awaiting_input",
        "chain_root_id": event_id,
        "line_idx": 0,
    }
    event_state_changed.emit()


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


# 이벤트 종료. event_resolved 발화 + event_state 비움.
# 카운트 키는 chain_root_id (1A 단계는 = event_id).
func _finalize_event() -> void:
    var result: Dictionary = {
        "event_id": event_state.get("chain_root_id", event_state.get("event_id", "")),
    }
    event_state = {}
    event_resolved.emit(result)
    event_state_changed.emit()


# ============================================================
# 트리거 평가 — 어떤 이벤트가 발생할지 결정
# ============================================================
# 필터: trigger.type 매치 → trigger 별 추가 매치 조건 → once_per → 가중치 추첨.
# 매치 없으면 "" 반환 (이벤트 미발생).
#
# 트리거 풀 (1A-2 시점):
#   - "node_enter": context = {"node_type": String}. trigger.node_type 매치.
#   - "run_start":  context 무관. 추가 매치 없음.

func resolve_event(trigger_type: String, context: Dictionary) -> String:
    var candidates: Array = []
    var weights: Array = []
    var total_weight: int = 0
    for id in GameData.EVENTS.keys():
        var def: Dictionary = GameData.EVENTS[id]
        var trigger: Dictionary = def.get("trigger", {})
        if trigger.get("type", "") != trigger_type:
            continue
        # 트리거별 추가 매치 조건
        match trigger_type:
            "node_enter":
                if trigger.get("node_type", "") != context.get("node_type", ""):
                    continue
            "run_start":
                pass  # 추가 조건 없음
            _:
                push_warning("resolve_event: 알 수 없는 trigger type '%s'" % trigger_type)
                continue
        # once_per 필터
        if def.get("once_per", "") == "big_run":
            var seen: Dictionary = RunManager.big_run_data.get("seen_events", {})
            if seen.get(id, 0) > 0:
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


# 노드 진입용 wrapper. RunManager.move_to_node 의 type "event" 분기에서 호출.
func _resolve_event_for_node(node: Dictionary) -> String:
    var node_type: String = node.get("type", "")
    if node_type == "":
        return ""
    return resolve_event("node_enter", {"node_type": node_type})


# ============================================================
# LimboConsole
# ============================================================

func _register_console_commands() -> void:
    LimboConsole.register_command(_cmd_event_advance, "event_advance",
        "이벤트 라인 진행 (dialogue kind)")
    LimboConsole.register_command(_cmd_show_event, "show_event",
        "event_state 덤프")


func _cmd_event_advance() -> void:
    advance_line()


func _cmd_show_event() -> void:
    LimboConsole.info(JSON.stringify(event_state, "  "))
