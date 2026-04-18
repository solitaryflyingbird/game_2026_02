extends Node

# ============================================================
# 앱 레벨 코디네이터 (자동로드).
# 타이틀 ↔ 런 전환을 담당. 런 자체 상태는 RunManager가 소유.
# ============================================================

signal app_state_changed

var app_phase: String = "title"  # "title" | "in_run"


func start_run() -> void:
    RunManager.init_run()
    app_phase = "in_run"
    app_state_changed.emit()

func return_to_title() -> void:
    RunManager.reset()
    app_phase = "title"
    app_state_changed.emit()

func quit_app() -> void:
    get_tree().quit()
