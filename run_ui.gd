extends Node2D

@onready var screens = {
    "title": $title_screen,
    "floor":   $floor_screen,
    "combat":  $combat_screen,
    "reward":  $reward_screen,
    "lose":    $result_screen,
    "victory": $result_screen,
}

func _ready():
    RunManager.state_changed.connect(_on_state_changed)
    $title_screen/Button.pressed.connect(_on_start_button_pressed)
    _on_state_changed()

func _on_state_changed():
    var phase = RunManager.run_data["phase"]
    show_phase(phase)

func show_phase(phase: String):
    for screen in screens.values():
        screen.visible = false
    if phase in screens:
        screens[phase].visible = true
        
func _on_start_button_pressed():
    RunManager.start_run()
