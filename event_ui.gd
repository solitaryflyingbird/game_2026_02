extends Control

# ============================================================
# 이벤트 UI — dialogue / choice kind.
# - dialogue: 화면 어디든 클릭 → advance_line. (_unhandled_input)
# - choice: 박스 안 버튼 클릭 → select_choice. 다른 곳 클릭은 무시.
# - 그 외 (effect / 미지원) : 무화면 (즉시 통과).
#
# 선택지 버튼은 GUI 입력에서 먼저 소비 → _unhandled_input 안 옴.
# 박스·라벨·컨테이너는 MOUSE_FILTER_IGNORE — GUI 입력 안 받음.
# ============================================================

var _box: Panel
var _speaker_label: Label
var _text_label: Label
var _hint_label: Label
var _choice_container: HBoxContainer
var _choice_buttons: Array = []  # Button[]


func _ready() -> void:
    # self mouse_filter = IGNORE 로 hit-test 제외. Control 의 기본값 STOP 이면
    # 게임 진입 시 클릭을 소비만 하고 처리 안 해 _unhandled_input 까지 안 옴 (확인된 버그).
    # IGNORE → 클릭이 자식 선택지 버튼·_unhandled_input 으로 정상 도달.
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _build_dialogue_box()
    EventManager.event_state_changed.connect(_on_event_state_changed)
    _on_event_state_changed()


func _build_dialogue_box() -> void:
    _box = Panel.new()
    _box.position = Vector2(80, 500)
    _box.size = Vector2(1120, 200)
    _box.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 시각만, 클릭은 self 통과
    add_child(_box)

    _speaker_label = Label.new()
    _speaker_label.position = Vector2(24, 16)
    _speaker_label.size = Vector2(400, 32)
    _speaker_label.add_theme_font_size_override("font_size", 20)
    _speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _box.add_child(_speaker_label)

    _text_label = Label.new()
    _text_label.position = Vector2(28, 56)
    _text_label.size = Vector2(1064, 50)
    _text_label.add_theme_font_size_override("font_size", 22)
    _text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _box.add_child(_text_label)

    _hint_label = Label.new()
    _hint_label.position = Vector2(990, 168)
    _hint_label.size = Vector2(110, 24)
    _hint_label.add_theme_font_size_override("font_size", 12)
    _hint_label.modulate = Color(0.7, 0.7, 0.7)
    _hint_label.text = "▼ 클릭"
    _hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _box.add_child(_hint_label)

    _choice_container = HBoxContainer.new()
    _choice_container.position = Vector2(28, 116)
    _choice_container.size = Vector2(1064, 70)
    _choice_container.add_theme_constant_override("separation", 12)
    _choice_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _box.add_child(_choice_container)


func _on_event_state_changed() -> void:
    var es: Dictionary = EventManager.event_state
    _clear_choice_buttons()
    # 하드 가드: 이벤트 비활성 시 _unhandled_input 자체를 끔.
    # 활성 시에도 dialogue 외 kind 는 함수 안에서 추가 무시.
    set_process_unhandled_input(EventManager.is_active())
    if es.is_empty():
        visible = false
        return
    var kind: String = es.get("kind", "")
    match kind:
        "dialogue":
            visible = true
            _show_dialogue_mode(es)
        "choice":
            visible = true
            _show_choice_mode(es)
        _:
            visible = false  # effect / 미구현 kind 는 무화면


func _show_dialogue_mode(es: Dictionary) -> void:
    _hint_label.visible = true
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


func _show_choice_mode(es: Dictionary) -> void:
    _hint_label.visible = false
    var event_id: String = es.get("event_id", "")
    var def: Dictionary = GameData.EVENTS.get(event_id, {})
    var prompt: Dictionary = def.get("prompt", {})
    _speaker_label.text = prompt.get("speaker", "")
    _text_label.text = prompt.get("text", "")

    var choices: Array = def.get("choices", [])
    for i in choices.size():
        var btn := Button.new()
        btn.text = "%d. %s" % [i + 1, choices[i].get("label", "")]
        btn.custom_minimum_size = Vector2(220, 60)
        btn.add_theme_font_size_override("font_size", 18)
        btn.pressed.connect(_on_choice_pressed.bind(i))
        _choice_container.add_child(btn)
        _choice_buttons.append(btn)


func _clear_choice_buttons() -> void:
    for btn in _choice_buttons:
        btn.queue_free()
    _choice_buttons.clear()


func _on_choice_pressed(idx: int) -> void:
    EventManager.select_choice(idx)


# 이벤트 활성 시에만 호출됨 (set_process_unhandled_input 하드 가드).
# dialogue 외 kind (choice / effect) 는 여기서 한번 더 무시.
# 선택지 버튼은 자체 STOP 으로 GUI 입력에서 먼저 캐치 → 여기 안 옴.
func _unhandled_input(event: InputEvent) -> void:
    if EventManager.event_state.get("kind", "") != "dialogue":
        return
    if event is InputEventMouseButton:
        var mb: InputEventMouseButton = event
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            EventManager.advance_line()
            get_viewport().set_input_as_handled()
