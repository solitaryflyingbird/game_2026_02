extends Node

# ============================================================
# 전투 초기 데이터 — 스펙 v1.1 기준
# 참조: docs/히로인 및 초기 팔(카드팩) 스펙.md
#       docs/전투_시스템 리뉴얼_구현명세.md
#
# 여기 정의된 값들은 "게임 시작 시점의 기본값·템플릿"이다.
# 런타임에서는 이 데이터를 인스턴스화한 뒤 상태로 보관·변경한다.
#   - HP / 덱 구성 / 팔 장착 상태는 런 중에 변한다
#   - 아래 const 들은 변경되지 않는 정의로만 참조된다
#
# 수치 단위 규약
#   - effects[].value 는 저하 배수(multiplier) 적용 전 기본값
#   - 저하 계수(drop, resistance, body_arm_weight)는 0.0~1.0 비율로 스케일링 제외
# ============================================================


# --- 전투 규칙 (세계 고정) --------------------------------------------------

const BATTLE_RULES = {
    "hand_size_per_arm": 3,
    "energy_per_arm": 2,
    "body_arm_weight": { "body": 0.5, "arm": 0.5 },
}


# --- 주인공 초기 스탯 --------------------------------------------------------

const INITIAL_BODY = {
    "max_hp": 150,
    "degradation": {
        "type": "stepped",
        "stages": [
            { "hp_min_pct": 66, "drop": 0.0 },
            { "hp_min_pct": 33, "drop": 0.2 },
            { "hp_min_pct": 0,  "drop": 0.4 },
        ],
    },
}


# --- 카드 템플릿 6종 ---------------------------------------------------------

const CARD_TEMPLATES = {
    "punch_heavy": {
        "name": "강펀치",
        "cost": 4,
        "category": "attack",
        "effects": [
            { "type": "deal_damage", "value": 40 },
            { "type": "damage_own_arm", "value": 20 },
        ],
        "degradation_resistance": 0.8,
        "description": "",
    },
    "punch_medium": {
        "name": "중펀치",
        "cost": 2,
        "category": "attack",
        "effects": [
            { "type": "deal_damage", "value": 20 },
            { "type": "damage_own_arm", "value": 10 },
        ],
        "degradation_resistance": 0.4,
        "description": "",
    },
    "punch_light": {
        "name": "약펀치",
        "cost": 1,
        "category": "attack",
        "effects": [
            { "type": "deal_damage", "value": 10 },
        ],
        "degradation_resistance": 0.1,
        "description": "",
    },
    "guard_heavy": {
        "name": "강가드",
        "cost": 4,
        "category": "defense",
        "effects": [
            { "type": "transfer_block", "value": 160 },
        ],
        "degradation_resistance": 0.8,
        "description": "",
    },
    "guard_medium": {
        "name": "중가드",
        "cost": 2,
        "category": "defense",
        "effects": [
            { "type": "transfer_block", "value": 80 },
        ],
        "degradation_resistance": 0.4,
        "description": "",
    },
    "guard_light": {
        "name": "약가드",
        "cost": 1,
        "category": "defense",
        "effects": [
            { "type": "transfer_block", "value": 40 },
        ],
        "degradation_resistance": 0.1,
        "description": "",
    },

    # --- 열화 카드 6종 (원본 수치의 80%) ---
    "degraded_punch_heavy": {
        "name": "열화 강펀치",
        "cost": 4,
        "category": "attack",
        "effects": [
            { "type": "deal_damage", "value": 32 },
            { "type": "damage_own_arm", "value": 16 },
        ],
        "degradation_resistance": 0.8,
        "description": "",
    },
    "degraded_punch_medium": {
        "name": "열화 중펀치",
        "cost": 2,
        "category": "attack",
        "effects": [
            { "type": "deal_damage", "value": 16 },
            { "type": "damage_own_arm", "value": 8 },
        ],
        "degradation_resistance": 0.4,
        "description": "",
    },
    "degraded_punch_light": {
        "name": "열화 약펀치",
        "cost": 1,
        "category": "attack",
        "effects": [
            { "type": "deal_damage", "value": 8 },
        ],
        "degradation_resistance": 0.1,
        "description": "",
    },
    "degraded_guard_heavy": {
        "name": "열화 강가드",
        "cost": 4,
        "category": "defense",
        "effects": [
            { "type": "transfer_block", "value": 128 },
        ],
        "degradation_resistance": 0.8,
        "description": "",
    },
    "degraded_guard_medium": {
        "name": "열화 중가드",
        "cost": 2,
        "category": "defense",
        "effects": [
            { "type": "transfer_block", "value": 64 },
        ],
        "degradation_resistance": 0.4,
        "description": "",
    },
    "degraded_guard_light": {
        "name": "열화 약가드",
        "cost": 1,
        "category": "defense",
        "effects": [
            { "type": "transfer_block", "value": 32 },
        ],
        "degradation_resistance": 0.1,
        "description": "",
    },
}


# --- 팔 모듈 (좌·우 슬롯에 장착되는 초기 모듈) ------------------------------

const _DEFAULT_ARM_CARD_IDS = [
    "punch_heavy", "punch_medium", "punch_light",
    "guard_heavy", "guard_medium", "guard_light",
]

const _DEFAULT_ARM_DEGRADATION = {
    "type": "stepped",
    "stages": [
        { "hp_min_pct": 66, "drop": 0.0 },
        { "hp_min_pct": 33, "drop": 0.3 },
        { "hp_min_pct": 0,  "drop": 0.5 },
    ],
}

const _DEGRADED_ARM_CARD_IDS = [
    "degraded_punch_heavy", "degraded_punch_medium", "degraded_punch_light",
    "degraded_guard_heavy", "degraded_guard_medium", "degraded_guard_light",
]

## slot_type 값:
##   "left_arm"  = 좌측 슬롯 전용
##   "right_arm" = 우측 슬롯 전용
##   "any"       = 좌·우 아무 슬롯에 장착 가능

const ARM_MODULES = {
    "left_arm_module": {
        "name": "좌측 원본 팔",
        "slot_type": "left_arm",
        "max_hp": 120,
        "card_ids": _DEFAULT_ARM_CARD_IDS,
        "degradation": _DEFAULT_ARM_DEGRADATION,
    },
    "right_arm_module": {
        "name": "우측 원본 팔",
        "slot_type": "right_arm",
        "max_hp": 120,
        "card_ids": _DEFAULT_ARM_CARD_IDS,
        "degradation": _DEFAULT_ARM_DEGRADATION,
    },
    "degraded_arm_module": {
        "name": "열화 팔",
        "slot_type": "any",
        "max_hp": 96,
        "card_ids": _DEGRADED_ARM_CARD_IDS,
        "degradation": _DEFAULT_ARM_DEGRADATION,
    },
}


# --- 층 데이터 ---------------------------------------------------------------

const FLOORS = [
    { "floor": 1, "name": "훈련용 샌드백", "max_hp": 50,  "intents": [10, 20, 10, 20] },
    { "floor": 2, "name": "경비 드론",    "max_hp": 80,  "intents": [20, 20, 10, 30] },
    { "floor": 3, "name": "중형 로봇",    "max_hp": 120, "intents": [20, 30, 20, 30] },
    { "floor": 4, "name": "돌격병",       "max_hp": 160, "intents": [30, 30, 20, 40] },
    { "floor": 5, "name": "수호자",       "max_hp": 220, "intents": [30, 40, 20, 50, 30] },
]
