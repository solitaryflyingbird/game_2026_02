extends Control

signal combat_finished(result: Dictionary)

func begin_combat():
    var deck = RunManager.run_data["deck"]
    var lines := PackedStringArray()
    lines.append("=== 현재 덱 (%d장) ===" % deck.size())
    for card_id in deck:
        var c = GameData.get_card(card_id)
        lines.append("  [%s] %s — 코스트 %d / 데미지 %d / 방어 %d" % [
            c.get("type", "?"), c.get("name", card_id),
            c.get("cost", 0), c.get("damage", 0), c.get("block", 0),
        ])
    lines.append("")
    lines.append("(전투 시스템 미구현 — 임시로 승리 처리)")

    $deck_label.text = "\n".join(lines)
    print("\n".join(lines))

    # 2초 후 자동 승리 처리 (전투 로직 미구현이므로 흐름 테스트용)
    await get_tree().create_timer(2.0).timeout
    combat_finished.emit({"hp": RunManager.run_data["hp"], "outcome": "win"})
