extends Node2D

# ============================================================
# 런 진행 중 UI. RunManager.state_changed 구독 후 화면 갱신.
# 맵/조우/회귀 라벨은 프로그래매틱 빌드, 전투·보상·결과는 씬 자식.
# ============================================================

@onready var screens = {
    "combat":   $battle_ui,
    "reward":   $reward_screen,
    "lose":     $result_screen,
    "research": $research_screen,
    "event":    $event_screen,
}

# --- 팔 인스펙터 (자료구조 확인용 + 장착 조작) ---
var _btn_show_equipped: Button
var _btn_show_spare: Button
var _arm_inspector_panel: Panel
var _arm_inspector_container: VBoxContainer
var _arm_inspect_mode: String = ""  # "" | "equipped" | "spare"

# --- 히로인 일러스트 (인스펙터 토글 시 좌측 표시) ---
const HEROINE_FRONT_DIR := "res://에셋/타이틀/"   # battle_ui 와 동일 idle 8프레임
var _heroine_sprite: AnimatedSprite2D

# --- 맵 디스플레이 ---
const MAP_ORIGIN: Vector2 = Vector2(180, 90)
const MAP_SIZE: Vector2 = Vector2(880, 500)
var _map_root: Control
var _node_buttons: Dictionary = {}   # id: int → Button

# --- 전투 프리뷰 ---
var _battle_preview_root: Control
var _preview_enemy_name_label: Label
var _preview_enemy_hp_label: Label
var _preview_intents_label: Label

# --- 회귀 카운트 (맵 화면 우측 상단, 검증용 임시 라벨) ---
var _recurrence_label: Label

# --- 연구 데이터 잔액 (맵·연구 화면 우측 상단, 회귀 카운트 아래) ---
var _balance_label: Label

# --- 연구 화면 (research_screen 자식 동적 빌드) ---
var _research_offer_root: HBoxContainer

# --- 저장·타이틀로 버튼 (맵 phase 한정) + 저장 피드백 라벨 ---
var _save_button: Button
var _save_feedback_label: Label
var _save_feedback_timer: Timer
var _to_title_button: Button


func _ready():
    RunManager.state_changed.connect(_on_state_changed)

    # 보상 — 맵으로 복귀 (적 제거된 상태로)
    $reward_screen/next_floor_button.pressed.connect(RunManager.return_to_map)
    # 결과 (승리·패배 공용) — 타이틀로
    $result_screen/title_button.pressed.connect(GameManager.return_to_title)

    _build_map_display()
    _build_battle_preview()
    _build_recurrence_label()
    _build_balance_label()
    _build_research_screen()
    _build_save_ui()
    _build_arm_inspector()           # 맵 위에 — 노드 버튼이 인스펙터 덮지 않도록
    _build_heroine_illustration()    # 맨 마지막 — 모든 위에 그려지도록


# --- 화면 전환 ---

func _on_state_changed():
    if RunManager.run_data.is_empty():
        _arm_inspector_panel.visible = false
        _btn_show_equipped.visible = false
        _btn_show_spare.visible = false
        if _heroine_sprite != null:
            _heroine_sprite.visible = false
        if _map_root != null:
            _map_root.visible = false
        if _battle_preview_root != null:
            _battle_preview_root.visible = false
        if _recurrence_label != null:
            _recurrence_label.visible = false
        if _balance_label != null:
            _balance_label.visible = false
        if _save_button != null:
            _save_button.visible = false
        if _save_feedback_label != null:
            _save_feedback_label.visible = false
        if _to_title_button != null:
            _to_title_button.visible = false
        return

    var phase = RunManager.run_data["phase"]

    # combat·event phase 동안 팔 인스펙터·히로인 일러스트 등 오버레이 UI 숨김.
    # event phase 는 대사창만 보이는 게 단순.
    var hide_overlay: bool = phase == "combat" or phase == "event"
    _btn_show_equipped.visible = not hide_overlay
    _btn_show_spare.visible = not hide_overlay
    if hide_overlay:
        _arm_inspector_panel.visible = false
        _arm_inspect_mode = ""
    _heroine_sprite.visible = _arm_inspector_panel.visible

    show_phase(phase)
    update_labels()
    _refresh_arm_inspector()
    _refresh_map_display()
    _refresh_battle_preview()
    _refresh_recurrence_label(phase)
    _refresh_balance_label(phase)
    _refresh_research_screen(phase)
    _refresh_save_button(phase)

    if phase == "combat":
        $battle_ui.begin_combat()


func show_phase(phase: String):
    for screen in screens.values():
        screen.visible = false
    if phase in screens:
        screens[phase].visible = true
    if _map_root != null:
        _map_root.visible = phase == "map"
    if _battle_preview_root != null:
        _battle_preview_root.visible = phase == "battle_preview"


func update_labels():
    var d = RunManager.run_data
    if d.is_empty():
        return

    match d["phase"]:
        "lose":
            $result_screen/result_label.text = "기동 정지"


# ============================================================
# 팔 인스펙터 (자료구조 확인용 + 장착 조작)
# ============================================================

func _build_arm_inspector():
    _btn_show_equipped = Button.new()
    _btn_show_equipped.text = "장착된 팔"
    _btn_show_equipped.position = Vector2(1100, 60)
    _btn_show_equipped.custom_minimum_size = Vector2(140, 32)
    _btn_show_equipped.pressed.connect(_on_show_equipped_pressed)
    _btn_show_equipped.visible = false
    add_child(_btn_show_equipped)

    _btn_show_spare = Button.new()
    _btn_show_spare.text = "스페어 팔"
    _btn_show_spare.position = Vector2(1100, 98)
    _btn_show_spare.custom_minimum_size = Vector2(140, 32)
    _btn_show_spare.pressed.connect(_on_show_spare_pressed)
    _btn_show_spare.visible = false
    add_child(_btn_show_spare)

    _arm_inspector_panel = Panel.new()
    _arm_inspector_panel.position = Vector2(900, 140)
    _arm_inspector_panel.size = Vector2(340, 420)
    _arm_inspector_panel.visible = false
    add_child(_arm_inspector_panel)

    _arm_inspector_container = VBoxContainer.new()
    _arm_inspector_container.position = Vector2(12, 12)
    _arm_inspector_container.size = Vector2(316, 396)
    _arm_inspector_container.add_theme_constant_override("separation", 6)
    _arm_inspector_panel.add_child(_arm_inspector_container)


func _on_show_equipped_pressed():
    if _arm_inspect_mode == "equipped":
        _arm_inspect_mode = ""
        _arm_inspector_panel.visible = false
    else:
        _arm_inspect_mode = "equipped"
        _arm_inspector_panel.visible = true
        _refresh_arm_inspector()
    _heroine_sprite.visible = _arm_inspector_panel.visible


func _on_show_spare_pressed():
    if _arm_inspect_mode == "spare":
        _arm_inspect_mode = ""
        _arm_inspector_panel.visible = false
    else:
        _arm_inspect_mode = "spare"
        _arm_inspector_panel.visible = true
        _refresh_arm_inspector()
    _heroine_sprite.visible = _arm_inspector_panel.visible


func _refresh_arm_inspector():
    if not _arm_inspector_panel.visible:
        return
    _clear_inspector_container()

    var data: Dictionary = RunManager.run_data
    if data.is_empty():
        return

    var instances: Dictionary = data.get("arm_instances", {})
    var equipped: Dictionary = data.get("equipped_arms", {"L": null, "R": null})

    if _arm_inspect_mode == "equipped":
        _build_equipped_view(instances, equipped)
    elif _arm_inspect_mode == "spare":
        var cap: int = data.get("arm_inventory_max", 6)
        _build_spare_view(instances, equipped, cap)


func _clear_inspector_container():
    for child in _arm_inspector_container.get_children():
        child.queue_free()


# --- 히로인 일러스트 빌드 (battle_ui 와 동일 idle 8프레임) ---

func _build_heroine_illustration() -> void:
    _heroine_sprite = AnimatedSprite2D.new()
    var frames := SpriteFrames.new()
    frames.add_animation("idle")
    frames.set_animation_speed("idle", 8)
    frames.set_animation_loop("idle", true)
    for i in range(1, 9):
        var f: Texture2D = load(HEROINE_FRONT_DIR + "%d.png" % i)
        if f != null:
            frames.add_frame("idle", f)
    _heroine_sprite.sprite_frames = frames
    _heroine_sprite.animation = "idle"
    _heroine_sprite.autoplay = "idle"
    _heroine_sprite.scale = Vector2(0.45, 0.45)
    _heroine_sprite.position = Vector2(240, 441)
    _heroine_sprite.visible = false
    add_child(_heroine_sprite)


func _build_equipped_view(instances: Dictionary, equipped: Dictionary):
    _arm_inspector_container.add_child(_make_label("=== 장착된 팔 ===", 13))
    for side in ["L", "R"]:
        _arm_inspector_container.add_child(_make_label("[%s]" % side, 12))
        var id = equipped.get(side, null)
        if id == null:
            _arm_inspector_container.add_child(_make_label("  (빈 슬롯)", 11))
        else:
            var arm: Dictionary = instances.get(id, {})
            _arm_inspector_container.add_child(_make_label(_format_arm_text(arm), 11))


func _build_spare_view(instances: Dictionary, equipped: Dictionary, cap: int):
    var equipped_ids := [equipped.get("L"), equipped.get("R")]
    var spare_ids: Array = []
    for id in instances.keys():
        if id not in equipped_ids:
            spare_ids.append(id)

    _arm_inspector_container.add_child(
        _make_label("=== 스페어 팔 (%d / %d) ===" % [spare_ids.size(), cap], 13))

    if spare_ids.is_empty():
        _arm_inspector_container.add_child(_make_label("(비어있음)", 11))
        return

    for id in spare_ids:
        var arm: Dictionary = instances.get(id, {})
        _arm_inspector_container.add_child(_make_spare_entry(arm))


func _make_spare_entry(arm: Dictionary) -> Control:
    var entry = VBoxContainer.new()
    entry.add_theme_constant_override("separation", 2)

    entry.add_child(_make_label(_format_arm_text(arm), 11))

    var slot_type: String = arm.get("slot_type", "")
    var instance_id: int = arm.get("instance_id", 0)
    var can_l: bool = slot_type == "any" or slot_type == "left_arm"
    var can_r: bool = slot_type == "any" or slot_type == "right_arm"

    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 6)

    var btn_l = Button.new()
    btn_l.text = "L 장착"
    btn_l.custom_minimum_size = Vector2(80, 24)
    btn_l.disabled = not can_l
    btn_l.pressed.connect(_on_equip_pressed.bind("L", instance_id))
    row.add_child(btn_l)

    var btn_r = Button.new()
    btn_r.text = "R 장착"
    btn_r.custom_minimum_size = Vector2(80, 24)
    btn_r.disabled = not can_r
    btn_r.pressed.connect(_on_equip_pressed.bind("R", instance_id))
    row.add_child(btn_r)

    entry.add_child(row)
    return entry


func _on_equip_pressed(side: String, instance_id: int):
    RunManager.equip_arm(side, instance_id)


func _make_label(text: String, font_size: int) -> Label:
    var lbl = Label.new()
    lbl.text = text
    lbl.add_theme_font_size_override("font_size", font_size)
    return lbl


func _format_arm_text(arm: Dictionary) -> String:
    if arm.is_empty():
        return "  (데이터 없음)"
    return "  #%d %s (%s)\n  HP: %d / %d" % [
        arm.get("instance_id", 0),
        arm.get("name", "?"),
        arm.get("slot_type", "?"),
        arm.get("hp", 0),
        arm.get("max_hp", 0),
    ]


# ============================================================
# 맵 디스플레이 — TEST_MAP_GRAPH 기반 노드 그래프 + 이동
# ============================================================

func _build_map_display():
    _map_root = Control.new()
    _map_root.position = MAP_ORIGIN
    _map_root.size = MAP_SIZE
    _map_root.visible = false
    add_child(_map_root)

    # 엣지 (Line2D, 양방향 중 한 번만 그림)
    var drawn_edges: Dictionary = {}
    for id in GameData.TEST_MAP_GRAPH.keys():
        var node: Dictionary = GameData.TEST_MAP_GRAPH[id]
        for conn_id in node.connections:
            var a: int = min(id, conn_id)
            var b: int = max(id, conn_id)
            var key: String = "%d-%d" % [a, b]
            if drawn_edges.has(key):
                continue
            drawn_edges[key] = true

            var line := Line2D.new()
            line.points = PackedVector2Array([_node_position(id), _node_position(conn_id)])
            line.width = 3.0
            line.default_color = Color(0.5, 0.5, 0.55)
            _map_root.add_child(line)

    # 노드 버튼
    for id in GameData.TEST_MAP_GRAPH.keys():
        var btn := Button.new()
        var pos: Vector2 = _node_position(id)
        btn.custom_minimum_size = Vector2(80, 80)
        btn.position = pos - Vector2(40, 40)
        btn.text = "%d" % id
        btn.add_theme_font_size_override("font_size", 22)
        btn.pressed.connect(_on_map_node_pressed.bind(id))
        _map_root.add_child(btn)
        _node_buttons[id] = btn


func _node_position(id: int) -> Vector2:
    var node: Dictionary = GameData.TEST_MAP_GRAPH[id]
    var pos: Array = node.get("position", [0.5, 0.5])
    return Vector2(pos[0] * MAP_SIZE.x, pos[1] * MAP_SIZE.y)


func _on_map_node_pressed(id: int):
    RunManager.move_to_node(id)


func _refresh_map_display():
    if _map_root == null or not _map_root.visible:
        return
    var current_id = RunManager.run_data.get("current_node_id")
    var current_node: Dictionary = RunManager.get_current_node()
    var adjacent_ids: Array = current_node.get("connections", [])

    for id in _node_buttons.keys():
        var btn: Button = _node_buttons[id]
        var node: Dictionary = RunManager.get_node_by_id(id)
        var is_current: bool = id == current_id
        var is_visited: bool = node.get("visited", false)
        var is_adjacent: bool = id in adjacent_ids

        if is_current:
            btn.modulate = Color(1.0, 0.85, 0.3)     # 노랑 — 현재 위치
            btn.disabled = true
        elif is_adjacent:
            btn.modulate = Color(0.5, 1.0, 0.6)      # 초록 — 이동 가능
            btn.disabled = false
        elif is_visited:
            btn.modulate = Color(0.55, 0.55, 0.55)   # 회색 — 방문함
            btn.disabled = true
        else:
            btn.modulate = Color(0.85, 0.85, 0.85)   # 옅은 — 미방문/비인접
            btn.disabled = true


# ============================================================
# 전투 프리뷰 — enemy_id 있는 노드 진입 시 표시. "전투 시작" 버튼으로 진입.
# ============================================================

func _build_battle_preview():
    _battle_preview_root = Control.new()
    _battle_preview_root.position = Vector2(340, 180)
    _battle_preview_root.size = Vector2(600, 360)
    _battle_preview_root.visible = false
    add_child(_battle_preview_root)

    var panel = Panel.new()
    panel.size = Vector2(600, 360)
    _battle_preview_root.add_child(panel)

    var title = Label.new()
    title.text = "조우"
    title.position = Vector2(20, 16)
    title.add_theme_font_size_override("font_size", 16)
    _battle_preview_root.add_child(title)

    _preview_enemy_name_label = Label.new()
    _preview_enemy_name_label.position = Vector2(20, 56)
    _preview_enemy_name_label.size = Vector2(560, 36)
    _preview_enemy_name_label.add_theme_font_size_override("font_size", 24)
    _battle_preview_root.add_child(_preview_enemy_name_label)

    _preview_enemy_hp_label = Label.new()
    _preview_enemy_hp_label.position = Vector2(20, 110)
    _preview_enemy_hp_label.size = Vector2(560, 28)
    _preview_enemy_hp_label.add_theme_font_size_override("font_size", 14)
    _battle_preview_root.add_child(_preview_enemy_hp_label)

    _preview_intents_label = Label.new()
    _preview_intents_label.position = Vector2(20, 150)
    _preview_intents_label.size = Vector2(560, 28)
    _preview_intents_label.add_theme_font_size_override("font_size", 14)
    _battle_preview_root.add_child(_preview_intents_label)

    var start_btn = Button.new()
    start_btn.text = "전투 시작"
    start_btn.position = Vector2(230, 280)
    start_btn.custom_minimum_size = Vector2(140, 48)
    start_btn.pressed.connect(_on_preview_start_pressed)
    _battle_preview_root.add_child(start_btn)


func _on_preview_start_pressed():
    RunManager.start_combat()


func _refresh_battle_preview():
    if _battle_preview_root == null or not _battle_preview_root.visible:
        return
    var current: Dictionary = RunManager.get_current_node()
    var enemy_id = current.get("enemy_id")
    if enemy_id == null or not GameData.ENEMIES.has(enemy_id):
        _preview_enemy_name_label.text = "(enemy 없음)"
        _preview_enemy_hp_label.text = ""
        _preview_intents_label.text = ""
        return

    var enemy: Dictionary = GameData.ENEMIES[enemy_id]
    _preview_enemy_name_label.text = enemy.get("name", "?")
    _preview_enemy_hp_label.text = "HP %d" % enemy.get("max_hp", 0)

    var intents: Array = enemy.get("intents", [])
    var parts: Array = []
    for v in intents:
        parts.append(str(v))
    _preview_intents_label.text = "공격 패턴: %s (순환)" % " → ".join(parts)


# ============================================================
# 회귀 카운트 라벨 (맵·연구 화면 우측 상단, 검증용 라벨)
# ============================================================

func _build_recurrence_label() -> void:
    _recurrence_label = Label.new()
    _recurrence_label.position = Vector2(1080, 18)
    _recurrence_label.size = Vector2(180, 28)
    _recurrence_label.add_theme_font_size_override("font_size", 18)
    _recurrence_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _recurrence_label.visible = false
    add_child(_recurrence_label)


func _refresh_recurrence_label(phase: String) -> void:
    if _recurrence_label == null:
        return
    var show: bool = phase == "map" or phase == "research"
    _recurrence_label.visible = show
    if not show:
        return
    var count: int = RunManager.big_run_data.get("meta", {}).get("big_run_count", 0)
    _recurrence_label.text = "회귀 %d 회" % count


# ============================================================
# 연구 데이터 잔액 라벨 (맵·연구 화면 우측 상단, 회귀 카운트 아래)
# ============================================================

func _build_balance_label() -> void:
    _balance_label = Label.new()
    _balance_label.position = Vector2(1080, 46)  # 회귀 라벨 바로 아래
    _balance_label.size = Vector2(180, 28)
    _balance_label.add_theme_font_size_override("font_size", 16)
    _balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _balance_label.visible = false
    add_child(_balance_label)


func _refresh_balance_label(phase: String) -> void:
    if _balance_label == null:
        return
    var show: bool = phase == "map" or phase == "research"
    _balance_label.visible = show
    if not show:
        return
    var data: int = RunManager.big_run_data.get("research_data", 0)
    _balance_label.text = "연구 데이터 %d" % data


# ============================================================
# 주인공의 연구 화면 — 회귀 직전 강화 페이즈.
# RESEARCH_OPTIONS 풀에서 무작위 2개를 카드로 표시. 적용 / 회귀 버튼.
# 시뮬 상태 직접 변경 X — RunManager.purchase / leave_research 만 호출.
# ============================================================

func _build_research_screen() -> void:
    var screen: Control = $research_screen

    var title := Label.new()
    title.text = "주인공의 연구"
    title.position = Vector2(440, 40)
    title.size = Vector2(400, 40)
    title.add_theme_font_size_override("font_size", 28)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    screen.add_child(title)

    _research_offer_root = HBoxContainer.new()
    _research_offer_root.position = Vector2(320, 180)
    _research_offer_root.size = Vector2(640, 340)
    _research_offer_root.add_theme_constant_override("separation", 40)
    screen.add_child(_research_offer_root)

    var leave_button := Button.new()
    leave_button.text = "연구 종료 — 회귀"
    leave_button.position = Vector2(520, 580)
    leave_button.size = Vector2(240, 60)
    leave_button.pressed.connect(RunManager.leave_research)
    screen.add_child(leave_button)


func _refresh_research_screen(phase: String) -> void:
    if _research_offer_root == null:
        return
    if phase != "research":
        return
    for c in _research_offer_root.get_children():
        c.queue_free()
    var balance: int = RunManager.big_run_data.get("research_data", 0)
    var offers: Array = RunManager.run_data.get("research_offers", [])
    for i in range(offers.size()):
        _research_offer_root.add_child(_make_research_offer_card(i, offers[i], balance))


func _make_research_offer_card(idx: int, entry: Dictionary, balance: int) -> Control:
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
    btn.pressed.connect(_on_research_apply_pressed.bind(idx))
    col.add_child(btn)

    return card


func _on_research_apply_pressed(idx: int) -> void:
    RunManager.purchase(idx)


# ============================================================
# 저장 버튼 (맵 phase 한정) + 짧은 피드백
# ============================================================

func _build_save_ui() -> void:
    _save_button = Button.new()
    _save_button.text = "저장"
    _save_button.position = Vector2(1100, 136)  # 스페어 팔 버튼 (y=98+32) 아래
    _save_button.custom_minimum_size = Vector2(140, 32)
    _save_button.pressed.connect(_on_save_pressed)
    _save_button.visible = false
    add_child(_save_button)

    _save_feedback_label = Label.new()
    _save_feedback_label.position = Vector2(920, 142)
    _save_feedback_label.size = Vector2(170, 24)
    _save_feedback_label.add_theme_font_size_override("font_size", 14)
    _save_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _save_feedback_label.modulate = Color(0.7, 1.0, 0.7)
    _save_feedback_label.visible = false
    add_child(_save_feedback_label)

    _save_feedback_timer = Timer.new()
    _save_feedback_timer.wait_time = 1.5
    _save_feedback_timer.one_shot = true
    _save_feedback_timer.timeout.connect(_on_save_feedback_timeout)
    add_child(_save_feedback_timer)

    # 타이틀로 — 테스트 편의용. 현재 런 종료하고 타이틀 복귀.
    _to_title_button = Button.new()
    _to_title_button.text = "타이틀로"
    _to_title_button.position = Vector2(1100, 174)  # 저장 버튼 (y=136+32) 아래
    _to_title_button.custom_minimum_size = Vector2(140, 32)
    _to_title_button.pressed.connect(GameManager.return_to_title)
    _to_title_button.visible = false
    add_child(_to_title_button)


func _refresh_save_button(phase: String) -> void:
    if _save_button == null:
        return
    var show: bool = (phase == "map")
    _save_button.visible = show
    if _to_title_button != null:
        _to_title_button.visible = show


func _on_save_pressed() -> void:
    var ok: bool = GameManager.save()
    _save_feedback_label.text = "저장됨" if ok else "저장 실패"
    _save_feedback_label.modulate = Color(0.7, 1.0, 0.7) if ok else Color(1.0, 0.7, 0.7)
    _save_feedback_label.visible = true
    _save_feedback_timer.start()


func _on_save_feedback_timeout() -> void:
    _save_feedback_label.visible = false
