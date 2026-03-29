extends Node2D

var run_data := {}

func _ready() -> void:
    init_run()
    test_run()

func init_run():
    run_data = GameData.starting_data.duplicate(true)

func stub_combat():
    run_data["hp"] -= 3
    if run_data["hp"] <= 0:
        run_data["phase"] = "lose"
    elif run_data["floor"] > len(GameData.FLOOR_ENCOUNTERS):
        run_data["phase"] = "victory"
    else:
        run_data["phase"] = "reward"

func _process(delta: float) -> void:
    pass

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
            stub_combat()
        "reward":
            run_data["floor"] += 1
            run_data["phase"] = "combat"

func test_run():
    run_data["phase"] = "combat"
    while run_data["phase"] not in ["lose", "victory"]:
        print("Floor %d | HP %d | Phase %s" % [run_data["floor"], run_data["hp"], run_data["phase"]])
        run_step()
    print("결과: %s | Floor %d | HP %d" % [run_data["phase"], run_data["floor"], run_data["hp"]])

# ── 보상 포함 테스트 ──

func test_run_with_rewards():
    init_run()
    run_data["phase"] = "combat"
    while run_data["phase"] not in ["lose", "victory"]:
        print("Floor %d | HP %d/%d | Phase %s" % [run_data["floor"], run_data["hp"], run_data["max_hp"], run_data["phase"]])
        run_step()
        if run_data["phase"] == "reward":
            # 테스트용: 홀수 층은 회복, 짝수 층은 강화
            if run_data["floor"] % 2 == 1:
                reward_heal()
                print("  → 보상: 체력 회복 (%d/%d)" % [run_data["hp"], run_data["max_hp"]])
            else:
                reward_upgrade("attack")
                var d = run_data["dice"]["attack"]
                print("  → 보상: attack 강화 (등급 %d, 경험치 %d)" % [d["grade"], d["grade_exp"]])
            run_data["floor"] += 1
            run_data["phase"] = "combat"
    print("결과: %s | Floor %d | HP %d/%d" % [run_data["phase"], run_data["floor"], run_data["hp"], run_data["max_hp"]])
    print("최종 주사위: %s" % str(run_data["dice"]))
