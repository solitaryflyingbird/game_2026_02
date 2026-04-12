extends Node

# ============================================================
# 전투 상태
# ============================================================

var draw_pile: Array = []
var hand: Array = []
var discard_pile: Array = []
var exhaust_pile: Array = []

var player := {}
var enemies: Array = []
var turn: int = 0

# ============================================================
# 전투 시작 / 종료
# ============================================================

func start_combat(deck: Array, hp: int, max_hp: int, enemy_ids: Array) -> void:
    # 덱 deep copy
    draw_pile = []
    for card_inst in deck:
        draw_pile.append(card_inst.duplicate())
    hand = []
    discard_pile = []
    exhaust_pile = []
    draw_pile.shuffle()

    # 플레이어
    player = {
        "hp": hp,
        "max_hp": max_hp,
        "block": 0,
        "energy": 3,
        "energy_max": 3,
    }

    # 적 생성
    enemies = []
    for eid in enemy_ids:
        var base = GameData.ENEMIES[eid]
        enemies.append({
            "id": eid,
            "name": base["name"],
            "hp": base["max_hp"],
            "max_hp": base["max_hp"],
            "block": 0,
            "intent": {},
            "actions": base["actions"].duplicate(true),
        })

    turn = 0

func get_result() -> Dictionary:
    return {"outcome": "win" if _all_enemies_dead() else "lose", "hp": player["hp"]}

# ============================================================
# 턴 흐름
# ============================================================

func start_turn() -> void:
    turn += 1
    player["block"] = 0
    for e in enemies:
        if e["hp"] > 0:
            e["block"] = 0
    player["energy"] = player["energy_max"]
    draw(5)
    _decide_intents()

func end_turn() -> void:
    discard_hand()

func enemy_turn() -> void:
    for e in enemies:
        if e["hp"] <= 0:
            continue
        var intent = e["intent"]
        if intent.get("kind") == "attack":
            _apply_damage_to_player(intent["value"])

func is_combat_over() -> String:
    if _all_enemies_dead():
        return "win"
    if player["hp"] <= 0:
        return "lose"
    return ""

# ============================================================
# 카드 사용
# ============================================================

func can_play_card(hand_index: int) -> bool:
    if hand_index < 0 or hand_index >= hand.size():
        return false
    var stats = GameData.get_card_stats(hand[hand_index])
    return player["energy"] >= stats["cost"]

func play_card(hand_index: int, target_index: int) -> void:
    var card_inst = hand[hand_index]
    var stats = GameData.get_card_stats(card_inst)

    # 에너지 차감
    player["energy"] -= stats["cost"]

    # 효과 적용
    if stats["damage"] > 0 and target_index >= 0 and target_index < enemies.size():
        _apply_damage_to_enemy(target_index, stats["damage"])
    if stats["block"] > 0:
        player["block"] += stats["block"]

    # hand → discard
    hand.remove_at(hand_index)
    discard_pile.append(card_inst)

func exhaust_card(hand_index: int) -> void:
    var card_inst = hand[hand_index]
    hand.remove_at(hand_index)
    exhaust_pile.append(card_inst)

# ============================================================
# 덱 조작 6함수
# ============================================================

func draw(n: int) -> void:
    for i in range(n):
        if draw_pile.is_empty():
            reshuffle()
        if draw_pile.is_empty():
            break  # 카드가 아예 없음
        hand.append(draw_pile.pop_back())

func discard_hand() -> void:
    discard_pile.append_array(hand)
    hand.clear()

func reshuffle() -> void:
    draw_pile.append_array(discard_pile)
    discard_pile.clear()
    draw_pile.shuffle()

# ============================================================
# 데미지 계산
# ============================================================

func _apply_damage_to_enemy(enemy_index: int, amount: int) -> void:
    var e = enemies[enemy_index]
    var incoming = amount
    var absorbed = min(e["block"], incoming)
    e["block"] -= absorbed
    incoming -= absorbed
    e["hp"] = max(0, e["hp"] - incoming)

func _apply_damage_to_player(amount: int) -> void:
    var incoming = amount
    var absorbed = min(player["block"], incoming)
    player["block"] -= absorbed
    incoming -= absorbed
    player["hp"] -= incoming

# ============================================================
# 내부 헬퍼
# ============================================================

func _all_enemies_dead() -> bool:
    for e in enemies:
        if e["hp"] > 0:
            return false
    return true

func _get_alive_enemies() -> Array:
    var alive := []
    for i in range(enemies.size()):
        if enemies[i]["hp"] > 0:
            alive.append(i)
    return alive

func _decide_intents() -> void:
    for e in enemies:
        if e["hp"] <= 0:
            continue
        var actions = e["actions"]
        e["intent"] = actions[randi() % actions.size()].duplicate()
