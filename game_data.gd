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
        "max_hp": 48,
        "card_ids": _DEGRADED_ARM_CARD_IDS,
        "degradation": _DEFAULT_ARM_DEGRADATION,
    },
}


# --- 주인공의 연구 — 회귀 직전 강화 옵션 풀 ---------------------------------
# `_generate_research_offers` 가 이 풀을 셔플해 무작위 2개를 골라 제시.
# 효과 적용은 RunManager._apply_research_effect → _apply_<type> 분기.
# type 에 따른 params 스키마:
#   body_boost          { amount: int }  — body_max_hp / body_hp 둘 다 += amount
#   arm_attack_boost    { amount: int }  — 보유 모든 팔 인스턴스의 cards[*].effects[*]
#                                          중 deal_damage value 에 직접 += amount
#   arm_durability_boost{ amount: int }  — 보유 모든 팔 인스턴스 max_hp / hp 둘 다 += amount

const RESEARCH_OPTIONS = {
    "body_boost_basic": {
        "type": "body_boost",
        "name": "신체 강화 연구",
        "description": "몸 최대 HP +20",
        "base_price": 15,
        "params": { "amount": 20 },
    },
    "arm_attack_basic": {
        "type": "arm_attack_boost",
        "name": "공격 출력 해석",
        "description": "양팔 공격력 +1 (좌·우 모두)",
        "base_price": 15,
        "params": { "amount": 1 },
    },
    "arm_durability_basic": {
        "type": "arm_durability_boost",
        "name": "내구 구조 해석",
        "description": "양팔 내구도 +20 (좌·우 모두)",
        "base_price": 15,
        "params": { "amount": 20 },
    },
}


# --- 몬스터 데이터 -----------------------------------------------------------
# enemy_id 로 조회. 노드에 enemy_id 를 두고 조우 시 여기를 참조.

const ENEMIES = {
    "larva":            { "name": "에벌레",   "max_hp": 50,  "intents": [10, 20, 10, 20],
                          "data_drop": 10 },
    "big_worm":         { "name": "큰벌레",   "max_hp": 80,  "intents": [20, 20, 10, 30],
                          "data_drop": 15 },
    "soldier":          { "name": "병사",     "max_hp": 120, "intents": [20, 30, 20, 30],
                          "data_drop": 25 },
    "assault_trooper":  { "name": "돌격병",   "max_hp": 160, "intents": [30, 30, 20, 40],
                          "data_drop": 40 },
    "guardian":         { "name": "수호자",   "max_hp": 220, "intents": [30, 40, 20, 50, 30],
                          "data_drop": 100 },
}


# --- 그리드 월드 (좌표 기반 맵) ---------------------------------------------
# 16 × 12 그리드. 각 칸은 지형 코드 (G/P/F/C/W) 1자.
# 외곽 한 줄은 벽 (F = 숲) — 통과 불가.
#
# 지형 규칙: TERRAIN_RULES — passable 여부.
# 칸 위 조우: TILE_ENCOUNTERS — Vector2i 키. on_enter / explore 슬롯.
# 스폰: SPAWN_POS. 행동/일자: ACTIONS_PER_DAY / DAY_MAX.

const WORLD_TERRAIN: Array = [
    "FFFFFFFFFFFFFFFF",
    "FGGGGGGGGGGGGGGF",
    "FGGGGGGGGGGGGGGF",
    "FGGGGGGGGGGGGGGF",
    "FGGGGGGGGGGGGGGF",
    "FGGGGGGGGGGGGGGF",
    "FGGGGGGGGGGGGGGF",
    "FGGGGGGGGGGGGGGF",
    "FGGGGGGGGGGGGGGF",
    "FGGGGGGGGGGGGGGF",
    "FGGGGGGGGGGGGGGF",
    "FFFFFFFFFFFFFFFF",
]

const TERRAIN_RULES: Dictionary = {
    "G": { "name": "풀밭", "passable": true },
    "P": { "name": "길",   "passable": true },
    "F": { "name": "숲",   "passable": false },
    "C": { "name": "절벽", "passable": false },
    "W": { "name": "물",   "passable": false },
}

# 스폰 위치 — 거점.
const SPAWN_POS: Vector2i = Vector2i(1, 6)

# 일자 흐름. ACTIONS_PER_DAY 은 매 일자 시작 시 actions_remaining 리셋값.
# DAY_MAX 는 서사 표시용 (자동 강제 종료 X).
const ACTIONS_PER_DAY: int = 8
const DAY_MAX: int = 10

# --- 타일 조우 (Vector2i 키) ------------------------------------------------
# 슬롯 스키마:
#   on_enter / explore: {
#       id:        String,        # 추적 키 (event 의 경우 = event_id)
#       kind:      "event" | "combat" | "research",
#       event_id:  String,         # kind == "event" 만
#       enemy_id:  String,         # kind == "combat" 만
#       once_per:  "internal_run" | "big_run" | (없음 = 매번)
#   }
# event 슬롯 — 진입/탐험 시 EventManager.begin_event(event_id) 직접 호출.
# combat 슬롯 — phase = "battle_preview" 전환 + run_data["pending_combat"] 채움.
# research 슬롯 — phase = "research" 전환 (기존 _enter_research 결).
const TILE_ENCOUNTERS: Dictionary = {
    Vector2i(3, 6): {
        "on_enter": {
            "id": "regression_speech",
            "kind": "event",
            "event_id": "regression_speech",
            "once_per": "internal_run",
        },
    },
    Vector2i(5, 6): {
        "on_enter": {
            "id": "repair_choice",
            "kind": "event",
            "event_id": "repair_choice",
            "once_per": "internal_run",
        },
    },
    Vector2i(7, 6): {
        "on_enter": {
            "id": "research_node",
            "kind": "research",
        },
    },
    Vector2i(4, 4): {
        "on_enter": {
            "id": "larva_combat_4_4",
            "kind": "combat",
            "enemy_id": "larva",
            "once_per": "internal_run",
        },
    },
    Vector2i(4, 8): {
        "explore": {
            "id": "found_letter",
            "kind": "event",
            "event_id": "found_letter",
            "once_per": "internal_run",
        },
    },
}


# --- 이벤트 풀 (안 4 — kind 분리 + chain) -----------------------------------
# 글로벌 트리거 (run_start / on_rest) — EventManager.resolve_event 가 트리거 매치 +
# once_per 필터 + 가중치 추첨으로 선정. 라이브러리 결 (트리거 필드 없음) — 타일
# 슬롯이 event_id 로 직접 호출 (resolve_event 미경유, 슬롯 자체의 once_per 적용).
#   id           — 전역 유일 키 (seen_events 카운트 + chain id)
#   kind         — "dialogue" | "effect" | "choice" | (movie 미구현)
#   trigger      — 글로벌 트리거 이벤트만. {type: "run_start" | "on_rest"}.
#   once_per     — "big_run" / "internal_run" / 생략 (= 매번)
#   weight       — 동일 트리거 충돌 시 가중치.
#   lines        — dialogue kind 전용. [{speaker, text}].

const EVENTS = {
    "intro_speech": {
        "id": "intro_speech",
        "kind": "dialogue",
        "trigger": {"type": "run_start"},
        "weight": 10,
        "lines": [
            {"speaker": "히로인", "text": "시작합니다."},
            {"speaker": "히로인", "text": "환경을 확인합니다."},
        ],
    },
    # 라이브러리 — 트리거 필드 없음. 타일 조우 슬롯이 event_id 로 직접 호출.
    "regression_speech": {
        "id": "regression_speech",
        "kind": "dialogue",
        "lines": [
            {"speaker": "히로인", "text": "회귀합니다."},
        ],
    },

    # === Stage 2 (effect + chain + choice) — 수리 chain ===
    # 타일 (5, 6) 진입 → repair_choice (선택지) → 가지의 next →
    # repair_arm/repair_body (effect) → repair_done_arm/body (dialogue) → chain 종료.
    # chain_root_id = "repair_choice" — seen_events 카운트는 root 만.
    "repair_choice": {
        "id": "repair_choice",
        "kind": "choice",
        "prompt": {"speaker": "히로인", "text": "어디를 수리할까."},
        "choices": [
            {"label": "팔 수리", "next": "repair_arm"},
            {"label": "몸 수리", "next": "repair_body"},
        ],
    },
    "repair_arm": {
        "id": "repair_arm",
        "kind": "effect",
        "effects": [{"type": "arm_durability_boost", "params": {"amount": 20}}],
        "next": "repair_done_arm",
    },
    "repair_body": {
        "id": "repair_body",
        "kind": "effect",
        "effects": [{"type": "body_boost", "params": {"amount": 20}}],
        "next": "repair_done_body",
    },
    "repair_done_arm": {
        "id": "repair_done_arm",
        "kind": "dialogue",
        "lines": [{"speaker": "히로인", "text": "팔 수리 완료."}],
    },
    "repair_done_body": {
        "id": "repair_done_body",
        "kind": "dialogue",
        "lines": [{"speaker": "히로인", "text": "몸 수리 완료."}],
    },

    # 탐험 슬롯용 라이브러리 — 타일 (4, 8) 의 explore 슬롯이 호출.
    "found_letter": {
        "id": "found_letter",
        "kind": "dialogue",
        "lines": [
            {"speaker": "히로인", "text": "...편지. 알 수 없는 글자."},
            {"speaker": "히로인", "text": "...누군가의 흔적입니다."},
        ],
    },

    # 휴식 트리거. 매 휴식마다 발화 (반복 컷씬). once_per 없음 — 단일 라인이라도
    # "휴식이 일어났다" 는 시각 신호로 매번 노출. 풀 다양화는 컨텐츠 차로.
    "rest_dream_1": {
        "id": "rest_dream_1",
        "kind": "dialogue",
        "trigger": {"type": "on_rest"},
        "weight": 5,
        "lines": [
            {"speaker": "히로인", "text": "...밤이. 짧다."},
        ],
    },
}
