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

# --- 그리드 디스플레이 (다중 맵) ---
const TILE_PX: int = 38
const GRID_ORIGIN: Vector2 = Vector2(220, 90)
var _grid_roots: Dictionary = {}     # map_id: String → Control (그리드 루트)
var _tile_rects_by_map: Dictionary = {}   # map_id → { Vector2i → ColorRect }
var _player_marker: ColorRect       # 플레이어 마커 (현 맵 root 의 자식으로 reparent)
# 현 visible 맵 — 옛 _map_root 결로 한 번에 하나만 visible.
var _map_root: Control               # 현재 보이는 그리드 루트 (= _grid_roots[current_map_id])
var _tile_rects: Dictionary = {}     # 현 _map_root 의 tile_rects (= _tile_rects_by_map[current])

# --- 그리드 HUD (일자 / 행동) ---
var _day_label: Label
var _actions_label: Label
var _terrain_label: Label
var _inventory_hud_label: Label
var _move_buttons: Dictionary = {}   # "U/D/L/R/E/REST" → Button

# --- 인벤토리 패널 ---
var _btn_show_inventory: Button
var _inventory_panel: Panel
var _inventory_container: VBoxContainer
var _inventory_visible: bool = false

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

    _build_grid_display()
    _build_grid_hud()
    _build_battle_preview()
    _build_recurrence_label()
    _build_balance_label()
    _build_research_screen()
    _build_save_ui()
    _build_arm_inspector()           # 맵 위에 — 노드 버튼이 인스펙터 덮지 않도록
    _build_inventory_panel()         # 인벤토리 패널
    _build_heroine_illustration()    # 맨 마지막 — 모든 위에 그려지도록


# --- 화면 전환 ---

func _on_state_changed():
    if RunManager.run_data.is_empty():
        _arm_inspector_panel.visible = false
        _btn_show_equipped.visible = false
        _btn_show_spare.visible = false
        if _heroine_sprite != null:
            _heroine_sprite.visible = false
        for r in _grid_roots.values():
            r.visible = false
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
        if _day_label != null:
            _day_label.visible = false
        if _actions_label != null:
            _actions_label.visible = false
        if _terrain_label != null:
            _terrain_label.visible = false
        if _inventory_hud_label != null:
            _inventory_hud_label.visible = false
        if _btn_show_inventory != null:
            _btn_show_inventory.visible = false
        if _inventory_panel != null:
            _inventory_panel.visible = false
        for btn in _move_buttons.values():
            btn.visible = false
        return

    var phase = RunManager.run_data["phase"]

    # combat·event phase 동안 팔 인스펙터·히로인 일러스트 등 오버레이 UI 숨김.
    # event phase 는 대사창만 보이는 게 단순.
    var hide_overlay: bool = phase == "combat" or phase == "event"
    _btn_show_equipped.visible = not hide_overlay
    _btn_show_spare.visible = not hide_overlay
    _btn_show_inventory.visible = not hide_overlay
    if hide_overlay:
        _arm_inspector_panel.visible = false
        _arm_inspect_mode = ""
        _inventory_panel.visible = false
        _inventory_visible = false
    _heroine_sprite.visible = _arm_inspector_panel.visible

    show_phase(phase)
    update_labels()
    _refresh_arm_inspector()
    _refresh_grid_display()
    _refresh_grid_hud(phase)
    _refresh_battle_preview()
    _refresh_recurrence_label(phase)
    _refresh_balance_label(phase)
    _refresh_research_screen(phase)
    _refresh_save_button(phase)
    _refresh_inventory_panel()

    if phase == "combat":
        $battle_ui.begin_combat()


func show_phase(phase: String):
    for screen in screens.values():
        screen.visible = false
    if phase in screens:
        screens[phase].visible = true
    # 그리드 가시성은 _refresh_grid_display 가 current_map_id 결로 처리.
    # 여기서는 phase != "map" 이면 모든 그리드 root 숨김.
    if phase != "map":
        for r in _grid_roots.values():
            r.visible = false
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
# 그리드 디스플레이 — MAPS[current_map_id] 기반 좌표 맵 + 이동/탐험/휴식
# ============================================================

func _build_grid_display() -> void:
    # 모든 맵의 그리드를 미리 빌드. _grid_roots[map_id] 가 각 맵의 Control.
    # 가시성은 _refresh_grid_display 가 current_map_id 결로 토글.
    for map_id in GameData.MAPS.keys():
        _build_one_grid(map_id)

    # 플레이어 마커 — 현 맵 root 결로 reparent. 일단 시작 맵 결.
    _player_marker = ColorRect.new()
    _player_marker.size = Vector2(TILE_PX - 10, TILE_PX - 10)
    _player_marker.color = Color(1.0, 0.85, 0.3)
    var start_root: Control = _grid_roots[GameData.STARTING_MAP]
    start_root.add_child(_player_marker)
    _map_root = start_root
    _tile_rects = _tile_rects_by_map[GameData.STARTING_MAP]


func _build_one_grid(map_id: String) -> void:
    var root := Control.new()
    root.position = GRID_ORIGIN
    root.visible = false
    add_child(root)
    _grid_roots[map_id] = root

    var map: Dictionary = GameData.MAPS[map_id]
    var rows: Array = map["terrain"]
    var tile_rects: Dictionary = {}
    for y in range(rows.size()):
        var row: String = rows[y]
        for x in range(row.length()):
            var t: String = row[x]
            var rect := ColorRect.new()
            rect.position = Vector2(x * TILE_PX, y * TILE_PX)
            rect.size = Vector2(TILE_PX - 2, TILE_PX - 2)
            rect.color = _terrain_color(t)
            root.add_child(rect)
            tile_rects[Vector2i(x, y)] = rect
    _tile_rects_by_map[map_id] = tile_rects

    # 조우 마커
    var encounters: Dictionary = map["encounters"]
    for pos in encounters.keys():
        var enc: Dictionary = encounters[pos]
        var marker := ColorRect.new()
        marker.size = Vector2(8, 8)
        marker.position = Vector2(pos.x * TILE_PX + (TILE_PX - 10) / 2,
                                   pos.y * TILE_PX + (TILE_PX - 10) / 2)
        marker.color = _encounter_color(enc)
        root.add_child(marker)


func _terrain_color(t: String) -> Color:
    match t:
        "G": return Color(0.40, 0.62, 0.32)   # 풀밭
        "P": return Color(0.78, 0.70, 0.50)   # 길
        "F": return Color(0.20, 0.32, 0.18)   # 숲 (벽)
        "C": return Color(0.45, 0.40, 0.38)   # 절벽
        "W": return Color(0.30, 0.45, 0.65)   # 물
        _:   return Color(0.5, 0.5, 0.5)


func _encounter_color(enc: Dictionary) -> Color:
    if enc.has("on_enter"):
        var k: String = enc["on_enter"].get("kind", "")
        match k:
            "event":      return Color(0.85, 0.55, 0.95)   # 보라 — 이벤트
            "combat":     return Color(0.95, 0.35, 0.35)   # 빨강 — 전투
            "research":   return Color(0.40, 0.85, 0.95)   # 시안 — 연구
            "transition": return Color(1.0, 1.0, 1.0)       # 흰색 — 전이
    if enc.has("explore"):
        return Color(0.95, 0.85, 0.40)   # 노랑 — 탐험 슬롯
    return Color(0.8, 0.8, 0.8)


func _refresh_grid_display() -> void:
    var map_id: String = RunManager.run_data.get("current_map_id", GameData.STARTING_MAP)

    # 현 맵 root 가시 + 다른 맵 root 숨김 + 플레이어 마커 reparent
    var phase_is_map: bool = (RunManager.run_data.get("phase") == "map")
    for mid in _grid_roots.keys():
        var root: Control = _grid_roots[mid]
        var should_show: bool = (mid == map_id) and phase_is_map
        root.visible = should_show
    if _map_root != _grid_roots.get(map_id):
        _map_root = _grid_roots[map_id]
        _tile_rects = _tile_rects_by_map[map_id]
        if _player_marker.get_parent() != _map_root:
            _player_marker.get_parent().remove_child(_player_marker)
            _map_root.add_child(_player_marker)

    if not _map_root.visible:
        return

    var map: Dictionary = GameData.MAPS[map_id]
    var spawn: Vector2i = map["spawn"]
    var pos: Vector2i = RunManager.run_data.get("player_pos", spawn)
    _player_marker.position = Vector2(pos.x * TILE_PX + 5, pos.y * TILE_PX + 5)

    var visited: Dictionary = RunManager.run_data.get("visited_by_map", {}).get(map_id, {})
    var rows: Array = map["terrain"]
    for tile_pos in _tile_rects.keys():
        var rect: ColorRect = _tile_rects[tile_pos]
        var t: String = rows[tile_pos.y][tile_pos.x]
        var base: Color = _terrain_color(t)
        if not GameData.TERRAIN_RULES.get(t, {}).get("passable", false):
            rect.color = base   # 벽은 그대로
        elif visited.get(tile_pos, false):
            rect.color = base
        else:
            rect.color = base * 0.55   # 미방문 — 어둡게


# --- 그리드 HUD: 일자 / 행동 / 지형 + 이동·탐험·휴식 버튼 ---

func _build_grid_hud() -> void:
    _day_label = Label.new()
    _day_label.position = Vector2(40, 30)
    _day_label.size = Vector2(160, 28)
    _day_label.add_theme_font_size_override("font_size", 18)
    _day_label.visible = false
    add_child(_day_label)

    _actions_label = Label.new()
    _actions_label.position = Vector2(40, 60)
    _actions_label.size = Vector2(160, 28)
    _actions_label.add_theme_font_size_override("font_size", 16)
    _actions_label.visible = false
    add_child(_actions_label)

    _terrain_label = Label.new()
    _terrain_label.position = Vector2(40, 90)
    _terrain_label.size = Vector2(160, 28)
    _terrain_label.add_theme_font_size_override("font_size", 14)
    _terrain_label.visible = false
    add_child(_terrain_label)

    _inventory_hud_label = Label.new()
    _inventory_hud_label.position = Vector2(40, 120)
    _inventory_hud_label.size = Vector2(180, 28)
    _inventory_hud_label.add_theme_font_size_override("font_size", 14)
    _inventory_hud_label.visible = false
    add_child(_inventory_hud_label)

    var btn_specs: Array = [
        ["U",    "↑",       Vector2(120, 540), Vector2i(0, -1)],
        ["L",    "←",       Vector2(72,  580), Vector2i(-1, 0)],
        ["D",    "↓",       Vector2(120, 580), Vector2i(0, 1)],
        ["R",    "→",       Vector2(168, 580), Vector2i(1, 0)],
        ["E",    "탐험 (E)", Vector2(40,  640), Vector2i.ZERO],
        ["REST", "휴식 (R)", Vector2(140, 640), Vector2i.ZERO],
    ]
    for spec in btn_specs:
        var key: String = spec[0]
        var btn := Button.new()
        btn.text = spec[1]
        btn.position = spec[2]
        btn.custom_minimum_size = Vector2(46, 36) if key in ["U", "D", "L", "R"] else Vector2(96, 36)
        btn.add_theme_font_size_override("font_size", 18 if key in ["U", "D", "L", "R"] else 14)
        btn.visible = false
        if key in ["U", "D", "L", "R"]:
            btn.pressed.connect(_on_move_pressed.bind(spec[3]))
        elif key == "E":
            btn.pressed.connect(RunManager.try_explore)
        elif key == "REST":
            btn.pressed.connect(RunManager.rest)
        add_child(btn)
        _move_buttons[key] = btn


func _on_move_pressed(dir: Vector2i) -> void:
    RunManager.try_move(dir)


func _refresh_grid_hud(phase: String) -> void:
    var show: bool = (phase == "map")
    if _day_label != null: _day_label.visible = show
    if _actions_label != null: _actions_label.visible = show
    if _terrain_label != null: _terrain_label.visible = show
    if _inventory_hud_label != null: _inventory_hud_label.visible = show
    for btn in _move_buttons.values():
        btn.visible = show
    if not show:
        return
    var d = RunManager.run_data
    var day: int = d.get("day", 1)
    var day_max: int = d.get("day_max", GameData.DAY_MAX)
    var actions: int = d.get("actions_remaining", 0)
    var actions_max: int = d.get("actions_per_day", GameData.ACTIONS_PER_DAY)
    var map_id: String = d.get("current_map_id", GameData.STARTING_MAP)
    var spawn: Vector2i = GameData.MAPS[map_id]["spawn"]
    var pos: Vector2i = d.get("player_pos", spawn)
    _day_label.text = "Day %d / %d" % [day, day_max]
    _actions_label.text = "행동 %d / %d" % [actions, actions_max]
    _terrain_label.text = "%s — %s  (%d, %d)" % [
        RunManager.get_current_map_name(),
        RunManager.get_terrain_name(pos), pos.x, pos.y]
    _inventory_hud_label.text = _format_inventory_hud(d)


# 보유 > 0 모든 아이템 결 자동 표시. 카탈로그 결 자동 — 새 결 추가 시 코드 변경 X.
func _format_inventory_hud(d: Dictionary) -> String:
    var parts: Array = []
    for item_id in GameData.ITEMS.keys():
        var def: Dictionary = GameData.ITEMS[item_id]
        var scope: String = def.get("scope", "big_run_default")
        var inv: Dictionary = d.get("tools" if scope == "internal_run" else "inventory", {})
        var count: int = inv.get(item_id, 0)
        if count > 0:
            parts.append("%s %d" % [def.get("name", item_id), count])
    if parts.is_empty():
        return "(인벤토리 비어있음)"
    return "  ".join(parts)


func _unhandled_input(event: InputEvent) -> void:
    if not (event is InputEventKey) or not event.pressed:
        return
    if RunManager.run_data.is_empty():
        return
    if RunManager.run_data.get("phase") != "map":
        return
    match (event as InputEventKey).keycode:
        KEY_W, KEY_UP:    RunManager.try_move(Vector2i(0, -1))
        KEY_S, KEY_DOWN:  RunManager.try_move(Vector2i(0, 1))
        KEY_A, KEY_LEFT:  RunManager.try_move(Vector2i(-1, 0))
        KEY_D, KEY_RIGHT: RunManager.try_move(Vector2i(1, 0))
        KEY_E:            RunManager.try_explore()
        KEY_R:            RunManager.rest()


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
    var pending: Dictionary = RunManager.run_data.get("pending_combat", {})
    var enemy_id: String = pending.get("enemy_id", "")
    if enemy_id == "" or not GameData.ENEMIES.has(enemy_id):
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


# ============================================================
# 인벤토리 패널 (RPG 결 — 보유 결만 + 카테고리 자동)
# ============================================================

func _build_inventory_panel() -> void:
    _btn_show_inventory = Button.new()
    _btn_show_inventory.text = "인벤토리"
    _btn_show_inventory.position = Vector2(1100, 212)   # 타이틀로 (y=174+32) 아래
    _btn_show_inventory.custom_minimum_size = Vector2(140, 32)
    _btn_show_inventory.pressed.connect(_on_show_inventory_pressed)
    _btn_show_inventory.visible = false
    add_child(_btn_show_inventory)

    _inventory_panel = Panel.new()
    _inventory_panel.position = Vector2(900, 250)
    _inventory_panel.size = Vector2(340, 380)
    _inventory_panel.visible = false
    add_child(_inventory_panel)

    _inventory_container = VBoxContainer.new()
    _inventory_container.position = Vector2(12, 12)
    _inventory_container.size = Vector2(316, 356)
    _inventory_container.add_theme_constant_override("separation", 6)
    _inventory_panel.add_child(_inventory_container)


func _on_show_inventory_pressed() -> void:
    _inventory_visible = not _inventory_visible
    _inventory_panel.visible = _inventory_visible
    if _inventory_visible:
        _refresh_inventory_panel()


func _refresh_inventory_panel() -> void:
    if _inventory_panel == null or not _inventory_panel.visible:
        return
    for child in _inventory_container.get_children():
        child.queue_free()

    var d: Dictionary = RunManager.run_data
    var big_inv: Dictionary = d.get("inventory", {})
    var tools: Dictionary = d.get("tools", {})

    # 카테고리 자동 결 — ITEMS 의 category 결 수집. 보유 > 0 만.
    var by_category: Dictionary = {}
    for item_id in GameData.ITEMS.keys():
        var def: Dictionary = GameData.ITEMS[item_id]
        var scope: String = def.get("scope", "big_run_default")
        var inv: Dictionary = (tools if scope == "internal_run" else big_inv)
        var count: int = inv.get(item_id, 0)
        if count <= 0:
            continue   # 보유 0 = 미표시 (RPG 결)
        var cat: String = def.get("category", "기타")
        if not by_category.has(cat):
            by_category[cat] = []
        by_category[cat].append({"id": item_id, "def": def, "count": count})

    if by_category.is_empty():
        _inventory_container.add_child(_make_label("(인벤토리 비어있음)", 13))
        return

    # 카테고리 결로 sort + 표시
    var cats: Array = by_category.keys()
    cats.sort()
    for cat in cats:
        var items: Array = by_category[cat]
        _inventory_container.add_child(
            _make_label("=== %s ===" % _category_title(cat), 13))
        for entry in items:
            _inventory_container.add_child(_make_inventory_entry(entry))


func _category_title(cat: String) -> String:
    return GameData.CATEGORY_NAMES.get(cat, cat)


func _make_inventory_entry(entry: Dictionary) -> Control:
    var def: Dictionary = entry["def"]
    var count: int = entry["count"]
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)

    var name_lbl := Label.new()
    name_lbl.text = "%s × %d" % [def.get("name", "?"), count]
    name_lbl.add_theme_font_size_override("font_size", 12)
    name_lbl.custom_minimum_size = Vector2(180, 24)
    row.add_child(name_lbl)

    var use_event_id = def.get("use_event_id", null)
    if use_event_id != null and use_event_id != "":
        var btn := Button.new()
        btn.text = "사용"
        btn.custom_minimum_size = Vector2(60, 24)
        btn.pressed.connect(_on_use_item_pressed.bind(entry["id"]))
        row.add_child(btn)

    return row


func _on_use_item_pressed(item_id: String) -> void:
    RunManager.use_item(item_id)
