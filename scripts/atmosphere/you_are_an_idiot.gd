class_name YouAreAnIdiot
extends AtmosphereEvent
## Pure in-game fiction: Control popups and one positional sound. No OS/browser APIs.
const POPUP := preload("res://scripts/atmosphere/idiot_popup.gd")
const LAUGH := preload("res://assets/audio/creep_laugh.wav")
const FADE_SECONDS: float = 0.2

@export_range(1.0, 60.0) var duration_seconds: float = 15.0
@export_range(2, 8) var max_popups: int = 8
@export_range(-40.0, 0.0) var laugh_volume_db: float = -10.0
var game: Node3D
var overlay: Control
var audio: AudioStreamPlayer3D
var popups: Array[IdiotPopup] = []
var elapsed: float = 0.0
var chaotic: bool = false
var closing_mode: bool = false
var _early_fade: bool = false
var _fade_elapsed: float = 0.0
var _ended: bool = false
var _rng := RandomNumberGenerator.new()


func start(value: Node3D) -> bool:
	game = value
	if game.mode != game.Mode.COMPUTER or not game.terminal_ui.is_visible_in_tree():
		return false
	_rng.randomize()
	overlay = Control.new()
	overlay.name = "IdiotPopups"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.clip_contents = true
	game.terminal_ui.workspace.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.terminal_ui.transient_overlay = overlay
	overlay.resized.connect(_fit_popups)
	var first := _spawn_popup(Vector2.ZERO)
	first.position = ((overlay.size - first.size) * Vector2(0.5, 0.42)).max(Vector2.ZERO)
	audio = AudioStreamPlayer3D.new()
	audio.name = "IdiotLaugh"
	audio.stream = LAUGH
	audio.bus = &"SFX"
	audio.volume_db = laugh_volume_db
	audio.max_db = laugh_volume_db
	audio.unit_size = 2.5
	audio.max_distance = 18.0
	audio.panning_strength = 0.6
	game.terminal.get_node("Monitor").add_child(audio)
	audio.position = Vector3(0, 0, 0.25)
	audio.finished.connect(_repeat_laugh)
	audio.play()
	return true


func _spawn_popup(at: Vector2) -> IdiotPopup:
	var popup: IdiotPopup = POPUP.new()
	overlay.add_child(popup)
	popup.position = at
	popup.fit_to_area(overlay.size)
	popup.close_attempted.connect(_on_close_attempt)
	popups.append(popup)
	if chaotic:
		_set_moving(popup)
	return popup


func _set_moving(popup: IdiotPopup) -> void:
	popup.draggable = false
	popup.cancel_drag()
	popup.velocity = Vector2(_rng.randf_range(170.0, 240.0), _rng.randf_range(130.0, 190.0))
	if _rng.randf() < 0.5:
		popup.velocity.x *= -1.0
	if _rng.randf() < 0.5:
		popup.velocity.y *= -1.0


func _on_close_attempt(popup: IdiotPopup) -> void:
	if _ended or _early_fade or popup not in popups:
		return
	if closing_mode:
		popups.erase(popup)
		popup.hide()
		popup.queue_free()
		if popups.is_empty():
			_early_fade = true
		return
	if not chaotic:
		chaotic = true
		for existing: IdiotPopup in popups:
			_set_moving(existing)
	_spawn_popup(popup.position + Vector2(24, 20))
	# Once reached, this latch never resets: every subsequent cross really closes.
	closing_mode = popups.size() >= max_popups


func _fit_popups() -> void:
	for popup: IdiotPopup in popups:
		popup.fit_to_area(overlay.size)


func _repeat_laugh() -> void:
	if not _ended and not _early_fade and elapsed < duration_seconds and is_instance_valid(audio):
		audio.play()


func advance(delta: float) -> void:
	if _ended or delta < 0.0:
		return
	elapsed += delta
	if _early_fade:
		_fade_elapsed += delta
	var remaining := minf(duration_seconds - elapsed, FADE_SECONDS - _fade_elapsed if _early_fade else FADE_SECONDS)
	if remaining <= 0.0:
		finished.emit(&"closed" if _early_fade else &"completed")
		return
	if is_instance_valid(audio):
		audio.volume_db = laugh_volume_db + linear_to_db(clampf(remaining / FADE_SECONDS, 0.0001, 1.0))
		# Near the monitor, spatial gain is capped: fade that cap as well.
		audio.max_db = audio.volume_db
	for popup: IdiotPopup in popups:
		popup.advance(delta, overlay.size)


func ended(_outcome: StringName) -> void:
	if _ended:
		return
	_ended = true
	if is_instance_valid(game) and is_instance_valid(game.terminal_ui) and game.terminal_ui.transient_overlay == overlay:
		game.terminal_ui.transient_overlay = null
	if is_instance_valid(overlay):
		overlay.hide()
		overlay.queue_free()
	if is_instance_valid(audio):
		audio.stop()
		audio.queue_free()
	popups.clear()


func _exit_tree() -> void:
	ended(&"teardown")
