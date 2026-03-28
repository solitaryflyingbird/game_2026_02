extends Node2D

var run_data := {}

func _ready() -> void:
    init_run()
    test_run()

func init_run():
    run_data = GameData.starting_data.duplicate(true)

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

func run_step():
    match run_data["phase"]:
        "combat":
            var enemies = $battle_manager.spawn_enemies(run_data["floor"])
            var result = $battle_manager.combat(
                run_data["dice"],
                run_data["hp"],
                run_data["max_hp"],
                enemies
            )
            run_data["hp"] = result["hp"]
            if result["outcome"] == "lose":
                run_data["phase"] = "lose"
            elif run_data["floor"] >= 7:
                run_data["phase"] = "victory"
            else:
                run_data["phase"] = "reward"
        "reward":
            # 테스트: 자동으로 회복 선택
            reward_heal()
            run_data["floor"] += 1
            run_data["phase"] = "combat"

func test_run():
    print("=== 런 테스트 시작 ===")
    run_data["phase"] = "combat"
    while run_data["phase"] not in ["lose", "victory"]:
        var floor_before = run_data["floor"]
        var hp_before = run_data["hp"]
        run_step()
        if run_data["phase"] == "reward":
            print("  Floor %d | 전투 승리 | HP %d → %d" % [floor_before, hp_before, run_data["hp"]])
        elif run_data["phase"] == "lose":
            print("  Floor %d | 전투 패배 | HP %d → %d" % [floor_before, hp_before, run_data["hp"]])
        elif run_data["phase"] == "victory":
            print("  Floor %d | 전투 승리 | HP %d → %d | 최종 승리!" % [floor_before, hp_before, run_data["hp"]])
    print("결과: %s | Floor %d | HP %d/%d" % [run_data["phase"], run_data["floor"], run_data["hp"], run_data["max_hp"]])
    print("=== 런 테스트 완료 ===")

func _process(delta: float) -> void:
    pass
