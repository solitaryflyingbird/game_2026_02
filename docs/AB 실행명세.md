# Phase AB 실행 명세

> 2026-04-12 실행. 주사위 시스템 → 카드 시스템 전환의 첫 단계.

---

## 변경된 파일 (5개)

### 1. `game_data.gd` — 전면 재작성

**삭제:**
- `starting_data.dice` (주사위 4종 등급/경험치)
- `GRADE_FACES` (주사위 눈 테이블)
- `ENEMIES` (정찰 드론, 강습 드론, 중장갑 메카)
- `FLOOR_ENCOUNTERS` (층별 적 조합)

**추가:**
- `CARDS` — 카드 2종 정의:
  - `atk_basic`: 기본 공격, 코스트 1, 데미지 6
  - `blk_basic`: 기본 방어, 코스트 1, 방어 5
- `STARTING_DECK` — 시작 덱 10장 (공격 5 + 방어 5)
- `starting_data` — 시작 HP 50, deck 필드 추가 (init_run에서 채움)
- `get_card(card_id)` — 카드 ID로 데이터 조회 헬퍼

### 2. `battle_manager.gd` — 전삭

**삭제:** 전체 (310줄 → 3줄)
- 주사위 덱 빌드, 콤보 판정, 효과 처리, 적 턴, 자동 전투, 테스트 전부

**현재 상태:** 빈 Node. Phase C에서 새 전투 로직 작성 예정.

### 3. `combat_screen.gd` — 전삭 후 덱 표시로 교체

**삭제:** 전체 (273줄 → 20줄)
- 핸드 UI, 카드 선택, 콤보 확인, 타겟 선택, 적 표시, 시그널 핸들링

**현재 동작:**
- `begin_combat()` 호출 시 현재 `run_data["deck"]` 를 읽어서 각 카드 정보를 문자열로 조합
- `deck_label`에 텍스트로 표시
- 2초 후 자동 승리 처리 (`combat_finished` emit)
- 전투 로직은 없음 — **흐름 검증용 스텁**

### 4. `run_manager.gd` — 정리

**삭제:**
- `reward_heal()`, `reward_max_hp()`, `reward_upgrade()` — 구 보상 3종
- `finish_reward_heal()`, `finish_reward_maxhp()`, `finish_reward_upgrade()` — 구 보상 핸들러
- `test_run()` — 구 BattleManager 참조 테스트

**수정:**
- `init_run()` — `run_data["deck"]`을 `STARTING_DECK.duplicate()`로 초기화
- `_on_combat_finished()` — 승리 조건을 `floor >= 6`으로 하드코딩 (구 FLOOR_ENCOUNTERS 참조 제거)

**유지 (변경 없음):**
- `state_changed` 시그널
- `start_run()`, `start_combat()`, `return_to_title()`, `advance_floor()`

### 5. `run_ui.gd` — 정리

**삭제:**
- 보상 3종 시그널 연결 (heal_button, maxhp_button, upgrade_button)
- 보상 서브패널 4종 시그널 (dice_select_panel)
- `_on_upgrade_button()`, `_update_dice_buttons()` 함수
- `_update_enemy_preview()` 함수 (구 ENEMIES/FLOOR_ENCOUNTERS 참조)

**수정:**
- 보상 화면: `next_floor_button.pressed → RunManager.advance_floor`만 연결
- `update_labels()`: floor_screen의 enemy_label은 덱 장수 표시로 변경
- `show_phase()`: dice_select_panel 참조 제거
- 결과 텍스트: "임무 완료\n낙원 도달." / "기동 정지\n임무 실패."

### 6. `main.tscn` — UI 노드 정리

**combat_screen 자식 변경:**
- 삭제: `floor_label`, `hp_label`, `stub_label`, `stub_result`
- 추가: `deck_label` (전투 시 덱 목록 표시용 대형 Label)

**reward_screen 자식 변경:**
- 삭제: `info_label`, `title_label`, `upgrade_button`, `heal_button`, `maxhp_button`, `dice_select_panel` (및 4개 서브 버튼)
- 추가: `reward_label` ("전투 승리"), `next_floor_button` ("다음 층으로")

---

## 예상 동작 (Godot Play 시)

### 타이틀
- 변화 없음. 시작/불러오기/설정/종료 4버튼 + 로고 + 캐릭터 + 와이어프레임 배경.

### 시작 클릭 → 층 화면
- "FLOOR 01" 표시
- "HP 50 / 50"
- "덱: 10장"
- "전투 개시" 버튼

### 전투 개시 → 전투 화면
- 화면에 텍스트로 덱 목록 출력:
  ```
  === 현재 덱 (10장) ===
    [ATTACK] 기본 공격 — 코스트 1 / 데미지 6 / 방어 0
    [ATTACK] 기본 공격 — 코스트 1 / 데미지 6 / 방어 0
    [ATTACK] 기본 공격 — 코스트 1 / 데미지 6 / 방어 0
    [ATTACK] 기본 공격 — 코스트 1 / 데미지 6 / 방어 0
    [ATTACK] 기본 공격 — 코스트 1 / 데미지 6 / 방어 0
    [BLOCK] 기본 방어 — 코스트 1 / 데미지 0 / 방어 5
    [BLOCK] 기본 방어 — 코스트 1 / 데미지 0 / 방어 5
    [BLOCK] 기본 방어 — 코스트 1 / 데미지 0 / 방어 5
    [BLOCK] 기본 방어 — 코스트 1 / 데미지 0 / 방어 5
    [BLOCK] 기본 방어 — 코스트 1 / 데미지 0 / 방어 5

  (전투 시스템 미구현 — 임시로 승리 처리)
  ```
- 2초 후 자동으로 보상 화면으로 전환

### 보상 화면
- "전투 승리" 텍스트
- "다음 층으로" 버튼만

### 다음 층 클릭 → 층 2
- "FLOOR 02" 표시
- 다시 전투 → 2초 대기 → 보상 → 반복

### Floor 6 전투 승리 시
- 결과 화면: "임무 완료\n낙원 도달."
- "타이틀로" 버튼 → 타이틀

### 전체 루프
```
타이틀 → 층 1 → 전투(덱 표시, 2초) → 보상 → 층 2 → ... → 층 6 → 전투 → "임무 완료" → 타이틀
```

---

## 건드리지 않은 것

- 타이틀 화면 전체 (로고, 캐릭터, 셰이더, 버튼)
- 결과 화면 구조 (result_label + title_button)
- 캐릭터 idle 애니메이션, 셰이더, 에셋
- ui/ 폴더 (title_button, title_grid, character_edge)
- project.godot autoload 설정

---

## 다음 단계 (Phase C)

이 상태에서 다음으로 할 일:
1. `CombatState` 클래스 신규 작성 (드로우/핸드/플레이/적 턴)
2. `combat_screen.gd`를 CombatState 기반 카드 플레이 UI로 교체
3. 적 1종 추가 (test_dummy)
4. 실제로 카드를 클릭해서 적에게 데미지 주는 전투 루프 구현
