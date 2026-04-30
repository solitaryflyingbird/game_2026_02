extends Control

# ============================================================
# 이벤트 UI — 안 4 / Stage 1B.
# dialogue kind 의 라인을 단순 대사창으로 표시. 클릭 → advance_line.
# 다른 kind / 비활성 시 자기 자신 visible = false.
#
# EventManager.event_state_changed 한 채널 구독. event_state 의 변화를 보고
# 라인 렌더 + 자기 visibility 갱신. UI 내부 상태 (라인 누적 등) 안 들고있음.
# ============================================================

var _box: Panel
var _speaker_label: Label
var _text_label: Label
var _hint_label: Label


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE  # Control 자체는 입력 패스, _box 만 받음
    _build_dialogue_box()
    EventManager.event_state_changed.connect(_on_event_state_changed)
    _on_event_state_changed()  # 초기 동기화


func _build_dialogue_box() -> void:
    # 화면 하단 대사창 (1280x720 기준).
    _box = Panel.new()
    _box.position = Vector2(80, 500)
    _box.size = Vector2(1120, 200)
    _box.mouse_filter = Control.MOUSE_FILTER_STOP
    _box.gui_input.connect(_on_box_gui_input)
    add_child(_box)

    _speaker_label = Label.new()
    _speaker_label.position = Vector2(24, 16)
    _speaker_label.size = Vector2(400, 32)
    _speaker_label.add_theme_font_size_override("font_size", 20)
    _box.add_child(_speaker_label)

    _text_label = Label.new()
    _text_label.position = Vector2(28, 60)
    _text_label.size = Vector2(1064, 110)
    _text_label.add_theme_font_size_override("font_size", 22)
    _text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _box.add_child(_text_label)

    _hint_label = Label.new()
    _hint_label.position = Vector2(990, 168)
    _hint_label.size = Vector2(110, 24)
    _hint_label.add_theme_font_size_override("font_size", 12)
    _hint_label.modulate = Color(0.7, 0.7, 0.7)
    _hint_label.text = "▼ 클릭"
    _box.add_child(_hint_label)


func _on_event_state_changed() -> void:
    var es: Dictionary = EventManager.event_state
    if es.is_empty():
        visible = false
        return
    if es.get("kind") != "dialogue":
        # 1B 단계는 dialogue 만 렌더. 다른 kind 는 자리만 마련하고 무화면.
        visible = false
        return
    visible = true
    _render_dialogue_line(es)


func _render_dialogue_line(es: Dictionary) -> void:
    var event_id: String = es.get("event_id", "")
    var def: Dictionary = GameData.EVENTS.get(event_id, {})
    var lines: Array = def.get("lines", [])
    var line_idx: int = es.get("line_idx", 0)
    if line_idx < 0 or line_idx >= lines.size():
        push_warning("event_ui: line_idx %d 범위 밖 (size %d)" % [line_idx, lines.size()])
        _speaker_label.text = ""
        _text_label.text = ""
        return
    var line: Dictionary = lines[line_idx]
    _speaker_label.text = line.get("speaker", "")
    _text_label.text = line.get("text", "")


func _on_box_gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var mb: InputEventMouseButton = event
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            EventManager.advance_line()
            accept_event()
