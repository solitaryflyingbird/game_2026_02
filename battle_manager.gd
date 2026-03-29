extends Node

signal turn_started
signal combo_resolved
signal enemy_turn_done
signal combat_ended(result: Dictionary)

var combat_state := {}


# ============================
# 그릇
# ============================

func spawn_enemies(floor_num: int) -> Array:
    var encounter = GameData.FLOOR_ENCOUNTERS[floor_num]
    var enemies = []
    for key in encounter:
        var base = GameData.ENEMIES[key]
        var enemy = {
            "name": base["name"],
            "hp": base["hp"],
            "max_hp": base["hp"],
            "skills": base["skills"].duplicate(true),
        }
        enemies.append(enemy)
    return enemies


func build_deck(dice: Dictionary) -> Array:
    var deck = []
    for type in ["attack", "block", "boost", "heal"]:
        var grade = dice[type]["grade"]
        var faces = GameData.GRADE_FACES[grade]
        for value in faces:
            deck.append({ "type": type, "value": value })
    deck.shuffle()
    return deck


func init_combat(dice: Dictionary, hp: int, max_hp: int, enemies: Array) -> Dictionary:
    combat_state = {
        "deck": build_deck(dice),
        "hand": [],
        "pending_combo": [],
        "shield": 0,
        "boost_multiplier": 1,
        "turn": 0,
        "player_hp": hp,
        "player_max_hp": max_hp,
        "enemies": enemies,
    }
    return combat_state


# ============================
# 드로우·조합 판정
# ============================

func is_valid_combo(cards: Array) -> bool:
    var type_match = cards[0]["type"] == cards[1]["type"] and cards[1]["type"] == cards[2]["type"]
    var num_match = cards[0]["value"] == cards[1]["value"] and cards[1]["value"] == cards[2]["value"]
    return type_match or num_match


func _get_first_valid_combo(hand: Array) -> Array:
    for i in range(hand.size()):
        for j in range(i + 1, hand.size()):
            for k in range(j + 1, hand.size()):
                var combo = [hand[i], hand[j], hand[k]]
                if is_valid_combo(combo):
                    return combo
    return []


func has_valid_combo(hand: Array) -> bool:
    return _get_first_valid_combo(hand).size() > 0


func draw_hand():
    while true:
        combat_state["deck"].shuffle()
        var drawn = combat_state["deck"].slice(0, 5)
        if has_valid_combo(drawn):
            combat_state["hand"] = drawn
            combat_state["deck"] = combat_state["deck"].slice(5)
            break


# ============================
# 효과 처리
# ============================

func apply_attack(damage: int, target_index: int):
    combat_state["enemies"][target_index]["hp"] -= damage
    combat_state["enemies"][target_index]["hp"] = max(0, combat_state["enemies"][target_index]["hp"])


func apply_block(shield_gain: int):
    combat_state["shield"] += shield_gain


func apply_heal(heal_amount: int):
    combat_state["player_hp"] = min(
        combat_state["player_hp"] + heal_amount,
        combat_state["player_max_hp"]
    )


func apply_boost(boost_value: int):
    combat_state["boost_multiplier"] = boost_value


func resolve_combo(cards: Array, target_index: int):
    var type_match = cards[0]["type"] == cards[1]["type"] and cards[1]["type"] == cards[2]["type"]

    var effects = {}

    if type_match:
        var t = cards[0]["type"]
        var total = 0
        for c in cards:
            total += c["value"]
        effects[t] = total
    else:
        for c in cards:
            if c["type"] not in effects:
                effects[c["type"]] = 0
            effects[c["type"]] += c["value"]

    var current_boost = combat_state["boost_multiplier"]
    var has_non_boost = false

    for type in ["attack", "block", "heal"]:
        if type in effects:
            has_non_boost = true
            match type:
                "attack":
                    apply_attack(effects[type] * current_boost, target_index)
                "block":
                    apply_block(effects[type] * current_boost)
                "heal":
                    apply_heal(effects[type] * current_boost)

    if has_non_boost:
        combat_state["boost_multiplier"] = 1

    if "boost" in effects:
        apply_boost(effects["boost"])


# ============================
# 타겟·몬스터 턴
# ============================

func get_alive_enemies() -> Array:
    var alive = []
    for i in range(combat_state["enemies"].size()):
        if combat_state["enemies"][i]["hp"] > 0:
            alive.append(i)
    return alive


func apply_enemy_attack(skill_value: int):
    var incoming = skill_value
    if combat_state["shield"] > 0:
        var absorbed = min(combat_state["shield"], incoming)
        combat_state["shield"] -= absorbed
        incoming -= absorbed
    combat_state["player_hp"] -= incoming


func enemy_turn():
    for i in get_alive_enemies():
        var enemy = combat_state["enemies"][i]
        var skill = enemy["skills"][randi() % enemy["skills"].size()]
        apply_enemy_attack(skill["value"])


# ============================
# 턴 루프 (단계별 함수 + signal)
# ============================

func return_hand():
    combat_state["deck"].append_array(combat_state["hand"])
    combat_state["hand"] = []


func start_turn():
    combat_state["turn"] += 1
    draw_hand()
    turn_started.emit()


func submit_combo(cards: Array) -> bool:
    if cards.size() != 3:
        return false
    if not is_valid_combo(cards):
        return false
    combat_state["pending_combo"] = cards
    return true


func resolve(target_index: int) -> String:
    resolve_combo(combat_state["pending_combo"], target_index)
    combat_state["pending_combo"] = []
    combo_resolved.emit()

    if get_alive_enemies().size() == 0:
        var result = { "hp": combat_state["player_hp"], "outcome": "win" }
        combat_ended.emit(result)
        return "win"

    return_hand()
    enemy_turn()
    enemy_turn_done.emit()

    if combat_state["player_hp"] <= 0:
        var result = { "hp": combat_state["player_hp"], "outcome": "lose" }
        combat_ended.emit(result)
        return "lose"

    return "continue"


# ============================
# 자동 전투 (테스트·호환용)
# ============================

func combat(dice: Dictionary, hp: int, max_hp: int, enemies: Array, verbose: bool = false) -> Dictionary:
    init_combat(dice, hp, max_hp, enemies)

    while combat_state["turn"] < 100:
        start_turn()

        var combo = _get_first_valid_combo(combat_state["hand"])
        submit_combo(combo)

        var alive = get_alive_enemies()
        var target_index = alive[0] if alive.size() > 0 else 0

        if verbose:
            var combo_types = []
            for c in combo:
                combo_types.append("%s(%d)" % [c["type"], c["value"]])
            print("  턴 %d | HP %d | Shield %d | Boost x%d | 조합: %s" % [
                combat_state["turn"],
                combat_state["player_hp"],
                combat_state["shield"],
                combat_state["boost_multiplier"],
                ", ".join(combo_types),
            ])

        var result = resolve(target_index)

        if verbose and result != "continue":
            print("  → %s! HP %d" % [
                "승리" if result == "win" else "패배",
                combat_state["player_hp"],
            ])

        if result == "win":
            return { "hp": combat_state["player_hp"], "outcome": "win" }
        if result == "lose":
            return { "hp": combat_state["player_hp"], "outcome": "lose" }

        if verbose:
            var enemy_info = []
            for e in combat_state["enemies"]:
                enemy_info.append("%s HP%d" % [e["name"], e["hp"]])
            print("         → 몬스터 턴 후 | HP %d | Shield %d | 적: %s" % [
                combat_state["player_hp"],
                combat_state["shield"],
                ", ".join(enemy_info),
            ])

    push_warning("전투 100턴 초과 — 강제 종료")
    return { "hp": combat_state["player_hp"], "outcome": "lose" }


# ============================
# 테스트 헬퍼
# ============================

func _c(type: String, value: int) -> Dictionary:
    return { "type": type, "value": value }


func _setup_test_state(enemy_hp: int = 15, player_hp: int = 20, max_hp: int = 30, shield: int = 0, boost: int = 1, enemy_count: int = 1):
    var enemies = []
    for i in range(enemy_count):
        enemies.append({
            "name": "test_%d" % i,
            "hp": enemy_hp,
            "max_hp": enemy_hp,
            "skills": [{ "type": "attack", "value": 3 }],
        })
    combat_state = {
        "deck": [],
        "hand": [],
        "pending_combo": [],
        "shield": shield,
        "boost_multiplier": boost,
        "turn": 0,
        "player_hp": player_hp,
        "player_max_hp": max_hp,
        "enemies": enemies,
    }


# ============================
# 통합 테스트
# ============================

func test_all():
    print("=== 통합 테스트 시작 ===")

    var dice = GameData.starting_data["dice"]

    # --- 단계별 함수 ---
    var enemies = spawn_enemies(1)
    init_combat(dice, 30, 30, enemies)

    start_turn()
    assert(combat_state["hand"].size() == 5)
    assert(combat_state["turn"] == 1)
    print("  start_turn: hand 5장, turn 1 — OK")

    var valid = _get_first_valid_combo(combat_state["hand"])
    assert(submit_combo(valid) == true)
    assert(submit_combo([_c("attack",1), _c("block",2), _c("heal",3)]) == false)
    assert(submit_combo([_c("attack",1), _c("attack",1)]) == false)
    print("  submit_combo: 유효/무효/장수부족 — OK")

    submit_combo(valid)
    var res = resolve(0)
    assert(res in ["continue", "win", "lose"])
    assert(combat_state["pending_combo"].size() == 0)
    print("  resolve: %s, pending 비움 — OK" % res)

    # --- 자동 전투 호환 ---
    var weak = [{ "name": "약한적", "hp": 1, "max_hp": 1, "skills": [{ "type": "attack", "value": 1 }] }]
    var win = combat(dice, 30, 30, weak)
    assert(win["outcome"] == "win")
    assert(win["hp"] > 0)
    print("  확정 승리: outcome=%s, hp=%d — OK" % [win["outcome"], win["hp"]])

    var strong = [{ "name": "강한적", "hp": 999, "max_hp": 999, "skills": [{ "type": "attack", "value": 999 }] }]
    var lose = combat(dice, 30, 30, strong)
    assert(lose["outcome"] == "lose")
    assert(lose["hp"] <= 0)
    print("  확정 패배: outcome=%s, hp=%d — OK" % [lose["outcome"], lose["hp"]])

    # --- 슬라임 실전 ---
    print("  --- 슬라임 실전 ---")
    var slime = spawn_enemies(1)
    var slime_result = combat(dice, 30, 30, slime, true)
    print("  결과: %s | HP %d" % [slime_result["outcome"], slime_result["hp"]])

    print("=== 통합 테스트 완료 ===")
