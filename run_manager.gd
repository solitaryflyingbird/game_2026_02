
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
    while run_data["phase"] not in ["lose"]:
        print("Floor %d | HP %d | Phase %s" % [run_data["floor"], run_data["hp"], run_data["phase"]])
        run_step()
    print("결과: %s | Floor %d | HP %d" % [run_data["phase"], run_data["floor"], run_data["hp"]])
