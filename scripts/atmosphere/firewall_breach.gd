class_name FirewallBreach
extends AtmosphereEvent
## Local fictional minigame. No sockets, network requests or OS firewall operations.
const VIEW := preload("res://scripts/atmosphere/firewall_breach_view.gd")
const CLICK := preload("res://assets/audio/mouse_click1.wav")
const RESULT_SECONDS: float = 1.0

@export var settings: FirewallBreachConfig = preload("res://data/atmosphere/firewall_settings.tres")
var game: Node3D
var round_state := FirewallRound.new()
var overlay: ColorRect
var view: FirewallBreachView
var audio: AudioStreamPlayer3D
var victory_left: float = -1.0
var _ended: bool = false


func start(value: Node3D) -> bool:
	game = value
	if game.mode != game.Mode.COMPUTER or not game.terminal_ui.is_visible_in_tree() or game.terminal_ui.has_modal():
		return false
	round_state.begin(settings)
	overlay = ColorRect.new()
	overlay.name = "FirewallBreachOverlay"
	overlay.color = Color(0.015, 0.01, 0.015, 0.72)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	game.terminal_ui.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view = VIEW.new()
	overlay.add_child(view)
	view.port_pressed.connect(_on_port_pressed)
	view.block_pressed.connect(_on_block_pressed)
	overlay.resized.connect(_fit_view)
	_fit_view()
	game.terminal_ui.set_modal_overlay(overlay)
	audio = AudioStreamPlayer3D.new()
	audio.name = "FirewallClicks"
	audio.stream = CLICK
	audio.bus = &"SFX"
	audio.volume_db = -18.0
	audio.max_db = -18.0
	audio.unit_size = 2.5
	audio.max_distance = 18.0
	game.terminal.get_node("Monitor").add_child(audio)
	audio.position = Vector3(0, 0, 0.25)
	_present()
	return true


func _fit_view() -> void:
	view.fit_to_area(overlay.size)


func _can_click() -> bool:
	return not _ended and victory_left < 0.0 and game.mode == game.Mode.COMPUTER and overlay.is_visible_in_tree() and not game.dev_menu.is_open


func _on_port_pressed(index: int) -> void:
	if _can_click() and round_state.toggle_port(index):
		audio.play()
		_present()


func _on_block_pressed() -> void:
	if _can_click() and round_state.block_connection():
		audio.play()
		victory_left = RESULT_SECONDS
		_present()


func _present() -> void:
	view.present(round_state, victory_left >= 0.0)


func advance(delta: float) -> void:
	if _ended or delta < 0.0:
		return
	if victory_left >= 0.0:
		victory_left = maxf(0.0, victory_left - delta)
		if victory_left <= 0.0:
			finished.emit(&"won")
		return
	round_state.advance(delta)
	if round_state.state == FirewallRound.State.LOST:
		# Only an actual puzzle deadline applies this reversible inconvenience.
		game.terminal_ui.close_all_windows()
		finished.emit(&"lost")
		return
	_present()


func ended(_outcome: StringName) -> void:
	if _ended:
		return
	_ended = true
	if is_instance_valid(overlay):
		overlay.hide()
		overlay.queue_free()
	if is_instance_valid(game) and is_instance_valid(game.terminal_ui):
		game.terminal_ui.clear_modal_overlay(overlay)
	if is_instance_valid(audio):
		audio.stop()
		audio.queue_free()


func _exit_tree() -> void:
	ended(&"teardown")
