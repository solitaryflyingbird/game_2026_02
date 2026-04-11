class_name TitleButton
extends Button

const ACCENT := Color("5BC0EC")
const BAR_W := 4.0
const BAR_NORMAL_RATIO := 0.40
const ANIM_TIME := 0.12

@onready var bar: ColorRect = $bar

var _tween: Tween
var _hovered := false

func _ready() -> void:
    bar.color = ACCENT
    resized.connect(_apply_layout)
    mouse_entered.connect(_on_mouse_entered)
    mouse_exited.connect(_on_mouse_exited)
    focus_entered.connect(_on_mouse_entered)
    focus_exited.connect(_on_mouse_exited)
    _apply_layout()

func _apply_layout() -> void:
    if _hovered:
        bar.position = Vector2(0, 0)
        bar.size = Vector2(BAR_W, size.y)
    else:
        var h: float = size.y * BAR_NORMAL_RATIO
        bar.position = Vector2(0, (size.y - h) / 2.0)
        bar.size = Vector2(BAR_W, h)

func _on_mouse_entered() -> void:
    _hovered = true
    _animate_bar(0.0, size.y)

func _on_mouse_exited() -> void:
    _hovered = false
    var h: float = size.y * BAR_NORMAL_RATIO
    _animate_bar((size.y - h) / 2.0, h)

func _animate_bar(target_y: float, target_h: float) -> void:
    if _tween and _tween.is_valid():
        _tween.kill()
    _tween = create_tween().set_parallel(true)
    _tween.tween_property(bar, "position:y", target_y, ANIM_TIME) \
        .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    _tween.tween_property(bar, "size:y", target_h, ANIM_TIME) \
        .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
