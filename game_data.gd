extends Node

# ============================================================
# 카드 템플릿 (불변)
# ============================================================

const CARDS = {
    "atk_basic": {
        "name": "기본 공격",
        "type": "ATTACK",
        "cost": 1,
        "damage": 6,
        "block": 0,
        "desc": "적에게 6 데미지.",
    },
    "blk_basic": {
        "name": "기본 방어",
        "type": "BLOCK",
        "cost": 1,
        "damage": 0,
        "block": 5,
        "desc": "방어력 5 획득.",
    },
}

# ============================================================
# 적 템플릿
# ============================================================

const ENEMIES = {
    "test_dummy": {
        "name": "테스트 더미",
        "max_hp": 20,
        "actions": [
            {"kind": "attack", "value": 5},
        ],
    },
}

# ============================================================
# 시작 덱 (카드 인스턴스 배열)
# ============================================================

const STARTING_DECK_IDS = [
    "atk_basic", "atk_basic", "atk_basic", "atk_basic", "atk_basic",
    "blk_basic", "blk_basic", "blk_basic", "blk_basic", "blk_basic",
]

# ============================================================
# 런 초기 데이터
# ============================================================

const starting_data = {
    "hp": 50,
    "max_hp": 50,
    "floor": 1,
    "deck": [],
    "phase": "title",
}

# ============================================================
# 헬퍼
# ============================================================

## 카드 인스턴스 1장 생성
static func make_card_instance(card_id: String) -> Dictionary:
    return {
        "id": card_id,
        "upgraded": false,
        "damaged": false,
    }

## 시작 덱 인스턴스 배열 생성
static func make_starting_deck() -> Array:
    var deck := []
    for card_id in STARTING_DECK_IDS:
        deck.append(make_card_instance(card_id))
    return deck

## 카드 인스턴스의 최종 스탯 계산 (템플릿 + 보정)
static func get_card_stats(card_inst: Dictionary) -> Dictionary:
    var base = CARDS[card_inst["id"]].duplicate()
    if card_inst.get("upgraded", false):
        base["damage"] = base.get("damage", 0) + 3
        base["block"] = base.get("block", 0) + 3
    if card_inst.get("damaged", false):
        base["damage"] = max(0, base.get("damage", 0) - 2)
        base["block"] = max(0, base.get("block", 0) - 2)
        base["cost"] = base.get("cost", 0) + 1
    return base
