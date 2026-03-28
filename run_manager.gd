extends Node2D

var run_data := {}

func _ready() -> void:
    init_run()
    test_run()
    test_upgrade_path()

func init_run():
    run_data = GameData.starting_data.duplicate(true)

# --- 2단계: stub_combat (victory 분기 추가) ---

func stub_combat():
    run_data["hp"] -= 3
    if run_data["hp"] <= 0:
        run_data["phase"] = "lose"
    elif run_data["floor"] >= 7:
        run_data["phase"] = "victory"
    else:
        run_data["phase"] = "reward"

# --- 4단계: 보상 시스템 ---

func reward_max_hp():
    run_data["max_hp"] += 3

func reward_heal():
    run_data["hp"] = run_data["max_hp"]

func reward_upgrade(dice_type: String):
    var dice = run_data["dice"][dice_type]
    if dice["grade"] >= 4:
        return
    dice["grade_exp"] += 1
    if dice["grade_exp"] >= dice["grade"]:
        dice["grade_exp"] = 0
        dice["grade"] += 1

func generate_reward_options() -> Array:
    var pool = []

    # 강화 가능한 주사위가 있는지 확인
    var upgradable = get_upgradable_dice()
    if upgradable.size() > 0:
        pool.append("upgrade")

    pool.append("heal")
    pool.append("maxhp")

    pool.shuffle()
    return pool.slice(0, 2)

func get_upgradable_dice() -> Array:
    var result = []
    for key in run_data["dice"]:
        if run_data["dice"][key]["grade"] < 4:
            result.append(key)
    return result

func apply_reward(option: String):
    match option:
        "upgrade":
            var upgradable = get_upgradable_dice()
            if upgradable.size() > 0:
                var pick = upgradable[randi() % upgradable.size()]
                reward_upgrade(pick)
                print("  → 강화: %s (grade %d, exp %d)" % [pick, run_data["dice"][pick]["grade"], run_data["dice"][pick]["grade_exp"]])
        "heal":
            reward_heal()
            print("  → 회복: hp %d / %d" % [run_data["hp"], run_data["max_hp"]])
        "maxhp":
            reward_max_hp()
            print("  → 최대HP 증가: max_hp %d" % run_data["max_hp"])

# --- 3단계: 런 루프 ---

func run_step():
    match run_data["phase"]:
        "combat":
            stub_combat()
        "reward":
            var options = generate_reward_options()
            var choice = options[randi() % options.size()]
            print("  보상 옵션: %s | 선택: %s" % [str(options), choice])
            apply_reward(choice)
            run_data["floor"] += 1
            run_data["phase"] = "combat"

# --- 테스트 ---

func test_run():
    run_data["phase"] = "combat"
    print("=== 런 시작 ===")
    while run_data["phase"] not in ["lose", "victory"]:
        print("Floor %d | HP %d/%d | Phase %s" % [run_data["floor"], run_data["hp"], run_data["max_hp"], run_data["phase"]])
        run_step()
    print("=== 결과: %s | Floor %d | HP %d/%d ===" % [run_data["phase"], run_data["floor"], run_data["hp"], run_data["max_hp"]])
    print_dice_summary()

func print_dice_summary():
    print("--- 주사위 최종 상태 ---")
    for key in run_data["dice"]:
        var d = run_data["dice"][key]
        print("  %s: grade %d, exp %d" % [key, d["grade"], d["grade_exp"]])
        
        
func test_upgrade_path():
    init_run()
    var dice = run_data["dice"]["attack"]
    # 1→2: 1회
    reward_upgrade("attack")
    print("1회: grade %d, exp %d" % [dice["grade"], dice["grade_exp"]])
    # 2→3: 2회
    reward_upgrade("attack")
    reward_upgrade("attack")
    print("3회: grade %d, exp %d" % [dice["grade"], dice["grade_exp"]])
    # 3→4: 3회
    reward_upgrade("attack")
    reward_upgrade("attack")
    reward_upgrade("attack")
    print("6회: grade %d, exp %d" % [dice["grade"], dice["grade_exp"]])
    # 등급 4에서 강화 시도
    reward_upgrade("attack")
    print("7회(무효): grade %d, exp %d" % [dice["grade"], dice["grade_exp"]])
