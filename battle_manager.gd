extends Node

signal state_changed                                       # 범용 갱신
signal turn_began(turn: int)
signal player_turn_ended
signal damage_dealt(amount: int)
signal block_added(arm_side: String, amount: int)
signal block_absorbed(arm_side: String, amount: int)
signal body_damaged(amount: int)
signal arm_self_damaged(arm_side: String, amount: int)
signal arm_destroyed(arm_side: String)
signal battle_ended(result: String)                        # "victory" | "defeat"
signal play_failed(reason: String)                         # "energy_insufficient" 등


var battle_state: Dictionary = {}


# ============================================================
# 전투 시작 (명세 §5.1)
# ============================================================

func begin_battle(floor_num: int) -> void:
    var floors: Array = GameData.FLOORS
    floor_num = clampi(floor_num, 1, floors.size())
    var floor_data: Dictionary = floors[floor_num - 1]

    var arm_l_src: Dictionary = RunManager.get_equipped_arm("L")
    var arm_r_src: Dictionary = RunManager.get_equipped_arm("R")

    battle_state = {
        "body_hp": RunManager.run_data.get("body_hp", 0),
        "body_max_hp": RunManager.run_data.get("body_max_hp", 0),
        "arm_l": (arm_l_src.duplicate(true) if not arm_l_src.is_empty() else null),
        "arm_r": (arm_r_src.duplicate(true) if not arm_r_src.is_empty() else null),

        "enemy_name": floor_data.name,
        "enemy_max_hp": floor_data.max_hp,
        "enemy_hp": floor_data.max_hp,
        "enemy_intents": floor_data.intents.duplicate(),
        "enemy_intent_idx": 0,

        "deck": [],
        "hand": [],
        "discard": [],

        "energy": 0,
        "block_l": 0,
        "block_r": 0,

        "turn": 1,
        "phase": "player",
        "result": "",

        "next_card_instance_id": 1,
    }

    battle_state["deck"] = _build_initial_deck()
    battle_state["deck"].shuffle()

    _begin_player_turn()
    state_changed.emit()


# --- 초기 덱 빌드 (명세 §5.2) -------------------------------------------------

func _build_initial_deck() -> Array:
    var deck: Array = []
    var sides: Array = [["L", battle_state["arm_l"]], ["R", battle_state["arm_r"]]]
    for pair in sides:
        var side: String = pair[0]
        var arm = pair[1]
        if arm == null:
            continue
        for card_id in arm.card_ids:
            deck.append(_make_card_instance(card_id, side))
    return deck


func _make_card_instance(card_id: String, arm_side: String) -> Dictionary:
    var id: int = battle_state["next_card_instance_id"]
    battle_state["next_card_instance_id"] = id + 1
    return {
        "card_id": card_id,
        "arm_side": arm_side,
        "instance_id": id,
    }


# ============================================================
# 플레이어 턴 시작 (명세 §5.3)
# ============================================================

func _begin_player_turn() -> void:
    _draw_hand()
    battle_state["energy"] = _energy_for_alive_arms()
    battle_state["phase"] = "player"
    turn_began.emit(battle_state["turn"])


func _energy_for_alive_arms() -> int:
    var per_arm: int = GameData.BATTLE_RULES.energy_per_arm
    var e: int = 0
    if _arm_alive("L"):
        e += per_arm
    if _arm_alive("R"):
        e += per_arm
    return e


# --- 드로우 (명세 §5.4) -------------------------------------------------------

func _draw_hand() -> void:
    var per_arm: int = GameData.BATTLE_RULES.hand_size_per_arm
    var target: int = 0
    if _arm_alive("L"):
        target += per_arm
    if _arm_alive("R"):
        target += per_arm

    var drawn: int = 0
    while drawn < target:
        if battle_state["deck"].is_empty():
            if battle_state["discard"].is_empty():
                break
            battle_state["deck"] = battle_state["discard"].duplicate()
            battle_state["deck"].shuffle()
            battle_state["discard"].clear()

        var top = battle_state["deck"].pop_back()
        if not _arm_alive(top.arm_side):
            continue     # 죽은 팔 카드는 증발 (덱·버림 어디로도 안 감)
        battle_state["hand"].append(top)
        drawn += 1


# ============================================================
# 카드 플레이 (명세 §5.5)
# ============================================================

func play_card(hand_idx: int) -> bool:
    if battle_state.is_empty():
        return false
    if battle_state["phase"] != "player" or battle_state["result"] != "":
        return false
    if hand_idx < 0 or hand_idx >= battle_state["hand"].size():
        return false

    var card_inst: Dictionary = battle_state["hand"][hand_idx]
    if not GameData.CARD_TEMPLATES.has(card_inst.card_id):
        push_warning("play_card: unknown card_id %s" % card_inst.card_id)
        return false
    var card_def: Dictionary = GameData.CARD_TEMPLATES[card_inst.card_id]

    if battle_state["energy"] < card_def.cost:
        play_failed.emit("energy_insufficient")
        return false
    # E1: 이미 손에 있는 카드는 팔이 파괴돼도 사용 가능 (드로우 시점에만 스킵)

    _execute_card_effects(card_inst, card_def)
    battle_state["energy"] -= card_def.cost

    battle_state["hand"].remove_at(hand_idx)
    battle_state["discard"].append(card_inst)

    if battle_state["enemy_hp"] <= 0:
        battle_state["enemy_hp"] = 0
        battle_state["result"] = "victory"
        _finalize_battle()

    state_changed.emit()
    return true


# --- 카드 효과 실행 (명세 §7) -------------------------------------------------

func _execute_card_effects(card_inst: Dictionary, card_def: Dictionary) -> void:
    var side: String = card_inst.arm_side
    var mult: float = calc_effective_multiplier(
        card_def.degradation_resistance,
        body_drop(),
        _arm_drop(side)
    )

    for eff in card_def.effects:
        match eff.type:
            "deal_damage":
                var dmg: int = int(round(eff.value * mult))
                battle_state["enemy_hp"] = max(0, battle_state["enemy_hp"] - dmg)
                damage_dealt.emit(dmg)

            "transfer_block":
                var blk: int = int(round(eff.value * mult))
                if side == "L":
                    battle_state["block_l"] += blk
                else:
                    battle_state["block_r"] += blk
                block_added.emit(side, blk)

            "damage_own_arm":
                # 저하 미적용 (고정값, 명세 §7.3)
                var self_dmg: int = int(eff.value)
                arm_self_damaged.emit(side, self_dmg)
                _reduce_arm_hp(side, self_dmg)

            _:
                push_warning("Unknown effect type: %s" % eff.type)


# --- HP 감소 · 파괴 감지 (공용) -----------------------------------------------
# 호출자가 arm_self_damaged / block_absorbed 를 먼저 emit 한 뒤 이 함수를 부른다.
# 여기서는 HP 감소와 파괴 시그널만 담당.

func _reduce_arm_hp(side: String, amount: int) -> void:
    if amount <= 0:
        return
    var key: String = ("arm_l" if side == "L" else "arm_r")
    var arm = battle_state.get(key)
    if arm == null:
        return
    var was_alive: bool = arm.hp > 0
    arm.hp = max(0, arm.hp - amount)
    if was_alive and arm.hp == 0:
        # 팔 파괴 시 해당 팔 블록 즉시 0 (§8.6)
        if side == "L":
            battle_state["block_l"] = 0
        else:
            battle_state["block_r"] = 0
        arm_destroyed.emit(side)


# ============================================================
# 저하 계산 (명세 §6)
# ============================================================

func body_drop() -> float:
    return calc_drop(
        battle_state["body_hp"],
        battle_state["body_max_hp"],
        GameData.INITIAL_BODY.degradation
    )


func _arm_drop(side: String) -> float:
    var key: String = ("arm_l" if side == "L" else "arm_r")
    var arm = battle_state.get(key)
    if arm == null:
        return 0.0
    return calc_drop(arm.hp, arm.max_hp, arm.degradation)


func calc_drop(hp: int, max_hp: int, degradation: Dictionary) -> float:
    if max_hp <= 0:
        return 1.0
    var pct: float = float(hp) / float(max_hp) * 100.0
    for stage in degradation.stages:
        if pct >= stage.hp_min_pct:
            return stage.drop
    return 1.0


func calc_effective_multiplier(card_resistance: float, body_drop_v: float, arm_drop_v: float) -> float:
    var w: Dictionary = GameData.BATTLE_RULES.body_arm_weight
    var combined: float = w.body * body_drop_v + w.arm * arm_drop_v
    return max(0.0, 1.0 - combined * (1.0 - card_resistance))


# ============================================================
# 턴 종료 + 적 턴 (명세 §5.6, §5.7)
# ============================================================

func end_turn() -> void:
    if battle_state.is_empty():
        return
    if battle_state["phase"] != "player" or battle_state["result"] != "":
        return

    # 손패 전부 버림으로
    for c in battle_state["hand"]:
        battle_state["discard"].append(c)
    battle_state["hand"].clear()
    battle_state["phase"] = "enemy"
    player_turn_ended.emit()

    _execute_enemy_turn()


func _execute_enemy_turn() -> void:
    var intents: Array = battle_state["enemy_intents"]
    var intent: int = intents[battle_state["enemy_intent_idx"] % intents.size()]
    _apply_enemy_attack(intent)
    battle_state["enemy_intent_idx"] += 1

    # 블록 소멸 (슬더스식)
    battle_state["block_l"] = 0
    battle_state["block_r"] = 0

    if battle_state["body_hp"] <= 0:
        battle_state["body_hp"] = 0
        battle_state["result"] = "defeat"
        _finalize_battle()
        state_changed.emit()
        return

    battle_state["turn"] += 1
    battle_state["phase"] = "player"
    _begin_player_turn()
    state_changed.emit()


# --- 피격 · 블록 흡수 (명세 §8) -----------------------------------------------
# 좌팔 블록 → 우팔 블록 → 몸 순서로 흡수.

func _apply_enemy_attack(damage: int) -> void:
    var remaining: int = damage

    if battle_state["block_l"] > 0 and remaining > 0:
        var absorbed_l: int = min(battle_state["block_l"], remaining)
        battle_state["block_l"] -= absorbed_l
        block_absorbed.emit("L", absorbed_l)
        _reduce_arm_hp("L", absorbed_l)
        remaining -= absorbed_l

    if battle_state["block_r"] > 0 and remaining > 0:
        var absorbed_r: int = min(battle_state["block_r"], remaining)
        battle_state["block_r"] -= absorbed_r
        block_absorbed.emit("R", absorbed_r)
        _reduce_arm_hp("R", absorbed_r)
        remaining -= absorbed_r

    if remaining > 0:
        battle_state["body_hp"] = max(0, battle_state["body_hp"] - remaining)
        body_damaged.emit(remaining)


# ============================================================
# 인스펙션 (명세 §9, §12)
# ============================================================

func _arm_alive(side: String) -> bool:
    var key: String = ("arm_l" if side == "L" else "arm_r")
    var arm = battle_state.get(key)
    return arm != null and arm.hp > 0


func peek_next_intent() -> int:
    if battle_state.is_empty():
        return 0
    var intents: Array = battle_state["enemy_intents"]
    if intents.is_empty():
        return 0
    return intents[battle_state["enemy_intent_idx"] % intents.size()]


func get_snapshot() -> Dictionary:
    if battle_state.is_empty():
        return {}
    var arm_l = battle_state.get("arm_l")
    var arm_r = battle_state.get("arm_r")
    return {
        "body_hp": battle_state["body_hp"],
        "body_max_hp": battle_state["body_max_hp"],
        "body_drop": body_drop(),

        "arm_l_hp": (0 if arm_l == null else arm_l.hp),
        "arm_l_max_hp": (0 if arm_l == null else arm_l.max_hp),
        "arm_l_drop": (0.0 if arm_l == null else _arm_drop("L")),
        "arm_l_alive": _arm_alive("L"),

        "arm_r_hp": (0 if arm_r == null else arm_r.hp),
        "arm_r_max_hp": (0 if arm_r == null else arm_r.max_hp),
        "arm_r_drop": (0.0 if arm_r == null else _arm_drop("R")),
        "arm_r_alive": _arm_alive("R"),

        "enemy_name": battle_state["enemy_name"],
        "enemy_hp": battle_state["enemy_hp"],
        "enemy_max_hp": battle_state["enemy_max_hp"],
        "next_intent": peek_next_intent(),

        "deck_size": battle_state["deck"].size(),
        "hand_size": battle_state["hand"].size(),
        "discard_size": battle_state["discard"].size(),
        "hand": battle_state["hand"].duplicate(),

        "energy": battle_state["energy"],
        "block_l": battle_state["block_l"],
        "block_r": battle_state["block_r"],

        "turn": battle_state["turn"],
        "phase": battle_state["phase"],
        "result": battle_state["result"],
    }


func get_card_preview(hand_idx: int) -> Dictionary:
    if battle_state.is_empty():
        return {}
    if hand_idx < 0 or hand_idx >= battle_state["hand"].size():
        return {}
    var card_inst: Dictionary = battle_state["hand"][hand_idx]
    if not GameData.CARD_TEMPLATES.has(card_inst.card_id):
        return {}
    var card_def: Dictionary = GameData.CARD_TEMPLATES[card_inst.card_id]
    var mult: float = calc_effective_multiplier(
        card_def.degradation_resistance,
        body_drop(),
        _arm_drop(card_inst.arm_side)
    )
    var preview_effects: Array = []
    for eff in card_def.effects:
        var fv: int = 0
        match eff.type:
            "deal_damage", "transfer_block":
                fv = int(round(eff.value * mult))
            "damage_own_arm":
                fv = int(eff.value)
            _:
                fv = 0
        preview_effects.append({"type": eff.type, "final_value": fv})
    return {
        "effects": preview_effects,
        "multiplier": mult,
    }


# ============================================================
# 전투 종료 · RunManager 로 HP 동기화
# ============================================================

func _finalize_battle() -> void:
    _sync_back_to_run()
    battle_ended.emit(battle_state["result"])


func _sync_back_to_run() -> void:
    var run_data: Dictionary = RunManager.run_data
    run_data["body_hp"] = battle_state["body_hp"]

    var arm_l = battle_state.get("arm_l")
    var arm_r = battle_state.get("arm_r")
    var instances: Dictionary = run_data.get("arm_instances", {})

    if arm_l != null:
        var l_id: int = arm_l.instance_id
        if instances.has(l_id):
            instances[l_id]["hp"] = arm_l.hp
    if arm_r != null:
        var r_id: int = arm_r.instance_id
        if instances.has(r_id):
            instances[r_id]["hp"] = arm_r.hp
