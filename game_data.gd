extends Node

# ============================================================
# 카드 정의
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

const STARTING_DECK = [
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
    "deck": [],   # init_run 시 STARTING_DECK 복사
    "phase": "title",
}

# ============================================================
# 헬퍼
# ============================================================

static func get_card(card_id: String) -> Dictionary:
    if card_id in CARDS:
        return CARDS[card_id]
    push_warning("unknown card id: %s" % card_id)
    return {}
