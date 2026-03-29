extends Node2D

signal state_changed

var run_data := {}

func _ready() -> void:
    init_run()

func init_run():
    run_data = GameData.starting_data.duplicate(true)
    state_changed.emit()

# --- 전투 ---

func real_combat():
    var enemies = BattleManager.spawn_enemies(run_data["floor"])
    var result = BattleManager.combat(
        run_data["dice"], run_data["hp"], run_data["max_hp"], enemies, true
    )
    run_data["hp"] = result["hp"]
    if result["outcome"] == "lose":
        run_data["phase"] = "lose"
    elif run_data["floor"] >= len(GameData.FLOOR_ENCOUNTERS):
        run_data["phase"] = "victory"
    else:
        run_data["phase"] = "reward"
    state_changed.emit()

# --- 보상 ---

func reward_max_hp():
    run_data["max_hp"] += 3

func reward_heal():
    run_data["hp"] = run_data["max_hp"]

func reward_upgrade(dice_type: String):
    var dice = run_data["dice"][dice_type]
    if dice["grade"] >= len(GameData.GRADE_FACES):
        return
    dice["grade_exp"] += 1
    if dice["grade_exp"] >= dice["grade"]:
        dice["grade_exp"] = 0
        dice["grade"] += 1

func advance_floor():
    run_data["floor"] += 1
    run_data["phase"] = "floor"
    state_changed.emit()

# --- 버튼 핸들러 ---

## 타이틀 → 플로어
func start_run():
    init_run()
    run_data["phase"] = "floor"
    state_changed.emit()

## 플로어 → 전투
func start_combat():
    run_data["phase"] = "combat"
    state_changed.emit()
    real_combat()

## 보상: 체력 회복 → 다음 층
func finish_reward_heal():
    reward_heal()
    advance_floor()

## 보상: 최대HP 증가 → 다음 층
func finish_reward_maxhp():
    reward_max_hp()
    advance_floor()

## 보상: 주사위 강화 → 다음 층
func finish_reward_upgrade(dice_type: String):
    reward_upgrade(dice_type)
    advance_floor()

## 결과 → 타이틀
func return_to_title():
    init_run()
    run_data["phase"] = "title"
    state_changed.emit()

# --- 통합 테스트 ---

func test_run():
    init_run()
    run_data["phase"] = "combat"
    print("=== 풀 런 테스트 시작 ===")
    while run_data["phase"] not in ["lose", "victory"]:
        print("Floor %d | HP %d/%d | Phase %s" % [
            run_data["floor"], run_data["hp"], run_data["max_hp"], run_data["phase"]
        ])
        real_combat()
        if run_data["phase"] == "reward":
            reward_heal()
            print("  → 보상: 체력 회복 → HP %d/%d" % [run_data["hp"], run_data["max_hp"]])
            run_data["floor"] += 1
            run_data["phase"] = "combat"
    print("=== 결과: %s | Floor %d | HP %d/%d ===" % [
        run_data["phase"], run_data["floor"], run_data["hp"], run_data["max_hp"]
    ])
