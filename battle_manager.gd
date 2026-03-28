extends Node

var combat_state := {}


# ============================
# 2단계: 그릇
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
        "shield": 0,
        "boost_multiplier": 1,
        "turn": 0,
        "player_hp": hp,
        "player_max_hp": max_hp,
        "enemies": enemies,
    }
    return combat_state


# ============================
# 3단계: 드로우·조합 판정
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
# 4단계: 효과 처리
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
# 5단계: 타겟·몬스터 턴
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
# 6단계: 턴 루프
# ============================

func return_hand():
    combat_state["deck"].append_array(combat_state["hand"])
    combat_state["hand"] = []


func combat(dice: Dictionary, hp: int, max_hp: int, enemies: Array, verbose: bool = false) -> Dictionary:
    init_combat(dice, hp, max_hp, enemies)

    while combat_state["turn"] < 100:
        combat_state["turn"] += 1

        draw_hand()

        var combo = _get_first_valid_combo(combat_state["hand"])
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

        resolve_combo(combo, target_index)

        if get_alive_enemies().size() == 0:
            if verbose:
                print("  → 승리! HP %d" % combat_state["player_hp"])
            return { "hp": combat_state["player_hp"], "outcome": "win" }

        return_hand()

        enemy_turn()

        if verbose:
            var enemy_info = []
            for e in combat_state["enemies"]:
                enemy_info.append("%s HP%d" % [e["name"], e["hp"]])
            print("         → 몬스터 턴 후 | HP %d | Shield %d | 적: %s" % [
                combat_state["player_hp"],
                combat_state["shield"],
                ", ".join(enemy_info),
            ])

        if combat_state["player_hp"] <= 0:
            if verbose:
                print("  → 패배! HP %d" % combat_state["player_hp"])
            return { "hp": combat_state["player_hp"], "outcome": "lose" }

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
        "shield": shield,
        "boost_multiplier": boost,
        "turn": 0,
        "player_hp": player_hp,
        "player_max_hp": max_hp,
        "enemies": enemies,
    }


# ============================
# 테스트: 2단계
# ============================

func test_stage_2():
    print("=== 2단계 테스트 시작 ===")

    var enemies_1 = spawn_enemies(1)
    assert(enemies_1.size() == 1)
    assert(enemies_1[0]["name"] == "슬라임")
    assert(enemies_1[0]["hp"] == 15)
    assert(enemies_1[0]["max_hp"] == 15)
    print("  2-1 spawn_enemies(1): %s — OK" % enemies_1[0]["name"])

    var enemies_4 = spawn_enemies(4)
    assert(enemies_4.size() == 2)
    print("  2-1 spawn_enemies(4): %d마리 — OK" % enemies_4.size())

    enemies_1[0]["hp"] = 0
    assert(GameData.ENEMIES["slime"]["hp"] == 15)
    print("  2-1 깊은 복사 — OK")

    var dice = GameData.starting_data["dice"]
    var deck = build_deck(dice)
    assert(deck.size() == 28)
    var type_count = { "attack": 0, "block": 0, "boost": 0, "heal": 0 }
    for card in deck:
        type_count[card["type"]] += 1
    for type in type_count:
        assert(type_count[type] == 7)
    print("  2-2 build_deck: 28장, 종류별 7장 — OK")

    var enemies = spawn_enemies(1)
    var state = init_combat(dice, 30, 30, enemies)
    assert(state["deck"].size() == 28)
    assert(state["hand"].size() == 0)
    assert(state["shield"] == 0)
    assert(state["boost_multiplier"] == 1)
    assert(state["player_hp"] == 30)
    assert(state["enemies"].size() == 1)
    print("  2-3 init_combat — OK")

    print("=== 2단계 테스트 완료 ===")


# ============================
# 테스트: 3단계
# ============================

func test_stage_3():
    print("=== 3단계 테스트 시작 ===")

    assert(is_valid_combo([_c("attack",2), _c("attack",1), _c("attack",2)]) == true)
    print("  3-1 종류 일치 — OK")

    assert(is_valid_combo([_c("attack",2), _c("block",2), _c("heal",2)]) == true)
    print("  3-1 숫자 일치 — OK")

    assert(is_valid_combo([_c("attack",2), _c("block",1), _c("heal",2)]) == false)
    print("  3-1 불일치 — OK")

    var hand_yes = [_c("attack",1), _c("attack",1), _c("attack",2), _c("block",1), _c("heal",2)]
    assert(has_valid_combo(hand_yes) == true)
    print("  3-2 유효 조합 있음 — OK")

    var hand_no = [_c("attack",1), _c("block",2), _c("heal",3), _c("boost",1), _c("attack",2)]
    assert(has_valid_combo(hand_no) == false)
    print("  3-2 유효 조합 없음 — OK")

    var dice = GameData.starting_data["dice"]
    var enemies = spawn_enemies(1)
    init_combat(dice, 30, 30, enemies)
    draw_hand()
    assert(combat_state["hand"].size() == 5)
    assert(combat_state["deck"].size() == 23)
    assert(has_valid_combo(combat_state["hand"]) == true)
    print("  3-3 draw_hand: hand 5장, deck 23장, 유효 조합 — OK")

    print("=== 3단계 테스트 완료 ===")


# ============================
# 테스트: 4단계
# ============================

func test_stage_4():
    print("=== 4단계 테스트 시작 ===")

    # case 1: attack 종류일치 → 적 hp 15-5=10
    _setup_test_state()
    resolve_combo([_c("attack",2), _c("attack",1), _c("attack",2)], 0)
    assert(combat_state["enemies"][0]["hp"] == 10)
    assert(combat_state["boost_multiplier"] == 1)
    print("  case 1: attack 종류일치 → 적 hp 10 — OK")

    # case 2: block 종류일치 → shield 4
    _setup_test_state()
    resolve_combo([_c("block",1), _c("block",1), _c("block",2)], 0)
    assert(combat_state["shield"] == 4)
    assert(combat_state["boost_multiplier"] == 1)
    print("  case 2: block 종류일치 → shield 4 — OK")

    # case 3: boost 종류일치 → boost = 5
    _setup_test_state()
    resolve_combo([_c("boost",2), _c("boost",2), _c("boost",1)], 0)
    assert(combat_state["boost_multiplier"] == 5)
    print("  case 3: boost 종류일치 → boost 5 — OK")

    # case 4: heal 종류일치 → hp 20+4=24
    _setup_test_state()
    resolve_combo([_c("heal",2), _c("heal",1), _c("heal",1)], 0)
    assert(combat_state["player_hp"] == 24)
    assert(combat_state["boost_multiplier"] == 1)
    print("  case 4: heal 종류일치 → hp 24 — OK")

    # case 5: 숫자일치 3종 → 적 13, shield 2, hp 22
    _setup_test_state()
    resolve_combo([_c("attack",2), _c("block",2), _c("heal",2)], 0)
    assert(combat_state["enemies"][0]["hp"] == 13)
    assert(combat_state["shield"] == 2)
    assert(combat_state["player_hp"] == 22)
    assert(combat_state["boost_multiplier"] == 1)
    print("  case 5: 숫자일치 3종 → 적 13, shield 2, hp 22 — OK")

    # case 6: 숫자일치 attack×2+heal → 적 11, hp 22
    _setup_test_state()
    resolve_combo([_c("attack",2), _c("attack",2), _c("heal",2)], 0)
    assert(combat_state["enemies"][0]["hp"] == 11)
    assert(combat_state["player_hp"] == 22)
    assert(combat_state["boost_multiplier"] == 1)
    print("  case 6: 숫자일치 attack×2+heal → 적 11, hp 22 — OK")

    # case 7: 숫자일치 attack+boost+heal → 적 13, hp 22, boost 2
    _setup_test_state()
    resolve_combo([_c("attack",2), _c("boost",2), _c("heal",2)], 0)
    assert(combat_state["enemies"][0]["hp"] == 13)
    assert(combat_state["player_hp"] == 22)
    assert(combat_state["boost_multiplier"] == 2)
    print("  case 7: 숫자일치 attack+boost+heal → 적 13, hp 22, boost 2 — OK")

    # case 8: 숫자일치 boost×2+heal → hp 22, boost 4
    _setup_test_state()
    resolve_combo([_c("boost",2), _c("boost",2), _c("heal",2)], 0)
    assert(combat_state["player_hp"] == 22)
    assert(combat_state["boost_multiplier"] == 4)
    print("  case 8: 숫자일치 boost×2+heal → hp 22, boost 4 — OK")

    # 추가: boost 적용 확인 (boost=5 상태에서 attack)
    _setup_test_state(15, 20, 30, 0, 5)
    resolve_combo([_c("attack",2), _c("attack",1), _c("attack",2)], 0)
    assert(combat_state["enemies"][0]["hp"] == 0)  # 5×5=25 → 15→0 (min 0)
    assert(combat_state["boost_multiplier"] == 1)
    print("  추가: boost 5 × attack 5 = 25 → 적 hp 0 — OK")

    print("=== 4단계 테스트 완료 ===")


# ============================
# 테스트: 5단계
# ============================

func test_stage_5():
    print("=== 5단계 테스트 시작 ===")

    # 5-1 get_alive_enemies
    _setup_test_state(10, 30, 30, 0, 1, 3)
    combat_state["enemies"][1]["hp"] = 0
    var alive = get_alive_enemies()
    assert(alive == [0, 2])
    print("  5-1 get_alive_enemies: [0, 2] — OK")

    # 5-2 타겟 선택: 1번만 피해
    _setup_test_state(10, 30, 30, 0, 1, 2)
    resolve_combo([_c("attack",2), _c("attack",1), _c("attack",2)], 1)
    assert(combat_state["enemies"][0]["hp"] == 10)
    assert(combat_state["enemies"][1]["hp"] == 5)
    print("  5-2 타겟 선택: 1번만 피해 — OK")

    # 5-3 shield 부분 흡수
    _setup_test_state(10, 30, 30, 4, 1)
    apply_enemy_attack(6)
    assert(combat_state["shield"] == 0)
    assert(combat_state["player_hp"] == 28)
    print("  5-3 shield 부분 흡수: shield 0, hp 28 — OK")

    # 5-3 shield 완전 흡수
    _setup_test_state(10, 30, 30, 10, 1)
    apply_enemy_attack(6)
    assert(combat_state["shield"] == 4)
    assert(combat_state["player_hp"] == 30)
    print("  5-3 shield 완전 흡수: shield 4, hp 30 — OK")

    # 5-3 shield 없음
    _setup_test_state(10, 30, 30, 0, 1)
    apply_enemy_attack(5)
    assert(combat_state["shield"] == 0)
    assert(combat_state["player_hp"] == 25)
    print("  5-3 shield 없음: hp 25 — OK")

    # 5-4 enemy_turn 결정론적 (스킬 1개씩)
    combat_state = {
        "deck": [], "hand": [],
        "shield": 0, "boost_multiplier": 1, "turn": 0,
        "player_hp": 30, "player_max_hp": 30,
        "enemies": [
            { "name": "A", "hp": 10, "max_hp": 10, "skills": [{ "type": "attack", "value": 3 }] },
            { "name": "B", "hp": 10, "max_hp": 10, "skills": [{ "type": "attack", "value": 5 }] },
        ],
    }
    enemy_turn()
    assert(combat_state["player_hp"] == 22)
    print("  5-4 enemy_turn: 3+5=8 피해 → hp 22 — OK")

    print("=== 5단계 테스트 완료 ===")


# ============================
# 테스트: 6단계
# ============================

func test_stage_6():
    print("=== 6단계 테스트 시작 ===")

    # 6-1 return_hand
    var dice = GameData.starting_data["dice"]
    var enemies = spawn_enemies(1)
    init_combat(dice, 30, 30, enemies)
    draw_hand()
    assert(combat_state["hand"].size() == 5)
    assert(combat_state["deck"].size() == 23)
    return_hand()
    assert(combat_state["hand"].size() == 0)
    assert(combat_state["deck"].size() == 28)
    print("  6-1 return_hand: hand 0, deck 28 — OK")

    # 6-2 확정 승리
    var weak = [{ "name": "약한적", "hp": 1, "max_hp": 1, "skills": [{ "type": "attack", "value": 1 }] }]
    var win = combat(dice, 30, 30, weak)
    assert(win["outcome"] == "win")
    assert(win["hp"] > 0)
    assert(win.has("deck") == false)
    assert(win.has("hand") == false)
    print("  6-2 확정 승리: outcome=%s, hp=%d — OK" % [win["outcome"], win["hp"]])

    # 6-2 확정 패배
    var strong = [{ "name": "강한적", "hp": 999, "max_hp": 999, "skills": [{ "type": "attack", "value": 999 }] }]
    var lose = combat(dice, 30, 30, strong)
    assert(lose["outcome"] == "lose")
    assert(lose["hp"] <= 0)
    print("  6-2 확정 패배: outcome=%s, hp=%d — OK" % [lose["outcome"], lose["hp"]])

    # 6-2 슬라임 실전 (verbose)
    print("  --- 슬라임 실전 ---")
    var slime = spawn_enemies(1)
    var result = combat(dice, 30, 30, slime, true)
    print("  결과: %s | HP %d" % [result["outcome"], result["hp"]])

    print("=== 6단계 테스트 완료 ===")
