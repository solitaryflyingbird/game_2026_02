extends Node

# ============================================================
# 앱 레벨 코디네이터 (자동로드).
# - 타이틀 ↔ 런 전환 (app_phase)
# - 세이브/로드 — 영속화 코디네이션
# 런 자체 상태는 RunManager 가 소유.
# ============================================================

signal app_state_changed

var app_phase: String = "title"  # "title" | "in_run"


# --- 세이브 / 로드 ---
# 직렬화: var_to_str / str_to_var 사용 (JSON 아님). int 키·Godot 타입 보존.
# JSON 은 numeric key 를 string 으로 캐스팅해서 map/arm_instances 같은 int-keyed
# dict 가 깨짐 — 그래서 var_to_str 채택. 확장자는 .save 로 비-JSON 명시.
const SAVE_DIR := "user://save/"
const SAVE_PATH := "user://save/slot_0.save"
const SAVE_VERSION := 1


func _ready() -> void:
    DirAccess.make_dir_absolute(SAVE_DIR)  # 이미 있으면 무탈


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


# ============================================================
# 세이브 / 로드
# ============================================================
# RunManager 의 dict 를 직접 read/write — 삼항 §3 의 cross-manager 직접 접근을
# 영속화 한정 의도적 허용. (영속화는 GameManager 의 책임, RunManager 는 데이터만
# 소유. dict 스키마 진화 시 wrapper 갱신 부담 회피.)

func save() -> bool:
    if RunManager.run_data.is_empty():
        push_warning("save: 활성 런 없음")
        return false
    if RunManager.run_data.get("phase", "") != "map":
        push_warning("save: phase != 'map' (현재: %s) — 안전 시점에서만 저장" %
            RunManager.run_data.get("phase", ""))
        return false
    var payload := {
        "version": SAVE_VERSION,
        "saved_at": Time.get_datetime_string_from_system(),
        "big_run_data": RunManager.big_run_data,
        "run_data": RunManager.run_data,
    }
    var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if f == null:
        push_warning("save: 파일 열기 실패: %s" % SAVE_PATH)
        return false
    f.store_string(var_to_str(payload))
    return true


func load_save() -> bool:
    if not FileAccess.file_exists(SAVE_PATH):
        return false
    var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if f == null:
        return false
    var content := f.get_as_text()
    var data = str_to_var(content)
    if data == null or not (data is Dictionary):
        push_warning("load: 직렬화 파싱 실패")
        return false
    if not data.has("version"):
        push_warning("load: 버전 정보 없음 — 알 수 없는 형식")
        return false
    RunManager.big_run_data = (data.get("big_run_data", {}) as Dictionary).duplicate(true)
    RunManager.run_data = (data.get("run_data", {}) as Dictionary).duplicate(true)
    _migrate_save(RunManager.run_data, RunManager.big_run_data)
    RunManager.state_changed.emit()
    app_phase = "in_run"
    app_state_changed.emit()
    return true


# 옛 결 세이브 → 신 결 결로 자동 변환.
# 1 맵 결 (`visited_tiles` / `explored_tiles` / `current_map_id` 누락) → 다중 맵 결.
# in-place 수정 — RunManager.run_data 직접 변경.
func _migrate_save(rd: Dictionary, brd: Dictionary) -> void:
    if not rd.has("current_map_id"):
        rd["current_map_id"] = GameData.STARTING_MAP
    if not rd.has("visited_by_map"):
        var legacy_visited: Dictionary = rd.get("visited_tiles", {})
        rd["visited_by_map"] = { GameData.STARTING_MAP: legacy_visited.duplicate() }
        rd.erase("visited_tiles")
    if not rd.has("explored_by_map"):
        var legacy_explored: Dictionary = rd.get("explored_tiles", {})
        rd["explored_by_map"] = { GameData.STARTING_MAP: legacy_explored.duplicate() }
        rd.erase("explored_tiles")
    # 인벤토리 결 (I-5 신설)
    if not brd.has("inventory"):
        brd["inventory"] = {}
    if not rd.has("inventory"):
        rd["inventory"] = brd["inventory"].duplicate()
    if not rd.has("tools"):
        rd["tools"] = {}


func has_save() -> bool:
    return FileAccess.file_exists(SAVE_PATH)
