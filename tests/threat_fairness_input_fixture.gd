extends Node
## Test-only JS bridge. Commands arrange encounters; E, mouse and F use real input.
var game: Node3D
var clicks: int = 0


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		clicks += 1


func _ready() -> void:
	if OS.has_feature("web"):
		var locale := str(JavaScriptBridge.eval("new URL(location.href).searchParams.get('lang') || 'en'"))
		TranslationServer.set_locale(locale)
	_setup()


func _setup() -> void:
	if is_instance_valid(game):
		game.queue_free()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	game.threats.set_process(false)
	game.shift.set_process(false)
	game.ambient.random_chance = 0.0
	game.transition_seconds = 0.05
	game.terminal_ui.notepad.editor.text = "web evidence"


func _process(_delta: float) -> void:
	if not OS.has_feature("web"):
		return
	var command = JavaScriptBridge.eval("window.fairnessCommand || null")
	if command != null:
		JavaScriptBridge.eval("window.fairnessCommand = null")
		match str(command):
			"pc": game.enter_computer()
			"police": game.trigger_police()
			"wardrobe":
				game.player.position = Vector3(-1.85, 0.03, 1.35)
				game.player.rotation = Vector3(0, PI, 0)
				game.player.head.rotation = Vector3(-0.25, 0, 0)
				game.player.stop_motion(true)
			"search": game.threats.advance(12.0)
			"departure": game.threats.advance(6.0)
			"gone":
				game.threats.advance(3.01)
				game.threats.advance(1.01)
			"detect":
				game.player.position = Vector3(0, 0.03, 1.1)
				game.police.visual.global_position = Vector3(1.4, 0, 1.1)
				game.police.visual.look_at(Vector3(0, 0, 1.1), Vector3.UP)
				game.threats.set_process(true)
			"blackout":
				_setup()
				game.trigger_power_outage()
				game.player.position = Vector3(4.2, 0.03, -5.0)
			"fusebox": game.enter_fusebox()
			"encounter": game.outage.entity._try_encounter()
			"active": game.threats.advance(game.outage.entity.warning_duration)
			"reset": _setup()
	var entity: CorridorEntity = game.outage.entity
	var telemetry := {
		"clicks": clicks,
		"focus": game._focus_active,
		"retry": game.pointer_retry_after_msec - Time.get_ticks_msec(),
		"mode": game.mode,
		"captured": Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"hidden": game.is_hidden(),
		"warning": game.hud.threat_hint.text,
		"warning_visible": game.hud.threat_hint.is_visible_in_tree(),
		"police_visible": game.police.visual.visible,
		"held_door": game.room_door.held_by_police,
		"ended": game.run_ended,
		"capture": game.capture_reason,
		"reason": game.failure_reason,
		"notes": game.terminal_ui.notepad.editor.text,
		"entity_phase": entity.phase,
		"warning_duration": entity.warning_duration,
		"flashlight": game.power.flashlight_on,
		"width": game.get_viewport().get_visible_rect().size.x,
		"warning_y": game.hud.threat_hint.get_global_rect().position.y,
	}
	JavaScriptBridge.eval("window.fairnessTelemetry = " + JSON.stringify(telemetry))
