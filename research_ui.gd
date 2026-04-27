extends Control

# ============================================================
# 주인공의 연구 화면 — 회귀 직전 강화 페이즈 UI.
#
# RunManager.state_changed 구독. phase == "research" 일 때만 의미 있는 표시.
# show_phase 가 visibility 토글하므로 본 스크립트는 phase 가드만 가볍게.
#
# 시뮬 상태 복제 없음. 매 갱신마다 RunManager.run_data / big_run_data 직접 읽기.
# 변경은 RunManager.purchase / leave_research 호출만.
# ============================================================

var _title_label: Label
var _balance_label: Label
var _offer_root: HBoxContainer
var _leave_button: Button


func _ready() -> void:
    _build_layout()
    RunManager.state_changed.connect(_refresh)
    _refresh()


func _build_layout() -> void:
    _title_label = Label.new()
    _title_label.text = "주인공의 연구"
    _title_label.position = Vector2(440, 40)
    _title_label.size = Vector2(400, 40)
    _title_label.add_theme_font_size_override("font_size", 28)
    _title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    add_child(_title_label)

    # 좌측 상단 — 우상단의 팔 인스펙터 버튼 (run_ui) 과 겹치지 않게.
    _balance_label = Label.new()
    _balance_label.position = Vector2(40, 50)
    _balance_label.size = Vector2(260, 28)
    _balance_label.add_theme_font_size_override("font_size", 18)
    _balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    add_child(_balance_label)

    _offer_root = HBoxContainer.new()
    _offer_root.position = Vector2(320, 180)
    _offer_root.size = Vector2(640, 340)
    _offer_root.add_theme_constant_override("separation", 40)
    add_child(_offer_root)

    _leave_button = Button.new()
    _leave_button.text = "연구 종료 — 회귀"
    _leave_button.position = Vector2(520, 580)
    _leave_button.size = Vector2(240, 60)
    _leave_button.pressed.connect(RunManager.leave_research)
    add_child(_leave_button)


func _refresh() -> void:
    if RunManager.run_data.is_empty():
        return
    if RunManager.run_data.get("phase") != "research":
        return  # show_phase 가 visibility 처리. 여기선 데이터 갱신 생략.

    var balance: int = RunManager.big_run_data.get("research_data", 0)
    _balance_label.text = "연구 데이터  %d" % balance

    _clear_node(_offer_root)
    var offers: Array = RunManager.run_data.get("research_offers", [])
    for i in range(offers.size()):
        _offer_root.add_child(_make_offer_card(i, offers[i], balance))


func _make_offer_card(idx: int, entry: Dictionary, balance: int) -> Control:
    var item: Dictionary = GameData.RESEARCH_OPTIONS.get(entry.get("item_id", ""), {})

    var card := Panel.new()
    card.custom_minimum_size = Vector2(280, 320)

    var col := VBoxContainer.new()
    col.position = Vector2(16, 18)
    col.size = Vector2(248, 284)
    col.add_theme_constant_override("separation", 12)
    card.add_child(col)

    var name_lbl := Label.new()
    name_lbl.text = item.get("name", "?")
    name_lbl.add_theme_font_size_override("font_size", 18)
    name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
    name_lbl.custom_minimum_size = Vector2(248, 0)
    col.add_child(name_lbl)

    var desc_lbl := Label.new()
    desc_lbl.text = item.get("description", "")
    desc_lbl.add_theme_font_size_override("font_size", 13)
    desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
    desc_lbl.custom_minimum_size = Vector2(248, 90)
    col.add_child(desc_lbl)

    var price_lbl := Label.new()
    price_lbl.text = "비용  %d 데이터" % entry.get("price", 0)
    price_lbl.add_theme_font_size_override("font_size", 14)
    col.add_child(price_lbl)

    var btn := Button.new()
    btn.custom_minimum_size = Vector2(248, 48)
    var applied: bool = entry.get("applied", false)
    var afford: bool = balance >= int(entry.get("price", 0))
    btn.text = "적용됨" if applied else "적용"
    btn.disabled = applied or not afford
    btn.pressed.connect(_on_apply_pressed.bind(idx))
    col.add_child(btn)

    return card


func _on_apply_pressed(idx: int) -> void:
    RunManager.purchase(idx)


func _clear_node(node: Node) -> void:
    for c in node.get_children():
        c.queue_free()
