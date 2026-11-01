extends CanvasLayer
## Root-owned curtain survives the menu scene until the apartment is ready.
var covered: bool = false
var curtain: ColorRect
var fade: Tween


func _ready() -> void:
	layer = 100
	curtain = ColorRect.new()
	curtain.color = Color.BLACK
	curtain.modulate.a = 0.0
	add_child(curtain)
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()


func cover(music: AudioStreamPlayer, seconds: float) -> void:
	fade = create_tween().set_parallel(true)
	fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade.tween_property(curtain, "modulate:a", 1.0, seconds)
	fade.tween_property(music, "volume_linear", 0.0, seconds)
	fade.chain().tween_callback(func(): covered = true)


func reveal(seconds: float) -> void:
	if fade != null:
		fade.kill()
	# Scene changes are deferred. Hold black through setup and the first frame.
	await get_tree().process_frame
	await get_tree().process_frame
	fade = create_tween()
	fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade.tween_property(curtain, "modulate:a", 0.0, seconds)
	fade.tween_callback(queue_free)
