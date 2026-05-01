extends Node2D

# ============================================================
# 앱 레벨 UI 오케스트레이션.
# - title_screen: 이 노드의 직속 자식
# - run_ui: 런 진행 중일 때만 표시
# GameManager.app_state_changed 를 구독해 표시 대상을 바꾼다.
# ============================================================

@onready var _title_screen: Control = $title_screen
@onready var _run_ui: Node2D = $run_ui


func _ready() -> void:
    GameManager.app_state_changed.connect(_on_app_state_changed)

    # 타이틀 버튼 배선
    _title_screen.get_node("start_button").pressed.connect(GameManager.start_run)
    _title_screen.get_node("load_button").pressed.connect(_on_load_pressed)
    _title_screen.get_node("settings_button").pressed.connect(_on_settings_pressed)
    _title_screen.get_node("quit_button").pressed.connect(GameManager.quit_app)

    _refresh_visibility()


func _on_app_state_changed() -> void:
    _refresh_visibility()


func _refresh_visibility() -> void:
    var in_title: bool = GameManager.app_phase == "title"
    _title_screen.visible = in_title
    _run_ui.visible = not in_title
    if in_title:
        var load_btn: Button = _title_screen.get_node("load_button")
        load_btn.disabled = not GameManager.has_save()


# --- 타이틀 버튼 핸들러 ---

func _on_load_pressed() -> void:
    if not GameManager.load_save():
        push_warning("[title] 불러올 세이브 없음 또는 형식 오류")


func _on_settings_pressed() -> void:
    print("[title] 설정: 아직 구현되지 않음")
