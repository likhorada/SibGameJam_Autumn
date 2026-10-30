extends "res://scripts/main.gd"
## F6: a long test space using the actual game/player/HUD. Never exported in release.
## A dedicated test-only Web export exposes telemetry; production has no JS bridge.

var _telemetry_time: float = 0.0


func _ready() -> void:
	super._ready()
	var origin := Vector3(100, 0, 100)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(60, 0.2, 80)
	collision.shape = shape
	floor_body.add_child(collision)
	add_child(floor_body)
	floor_body.position = origin + Vector3(0, -0.1, -15)
	_box(floor_body.position, shape.size, Color("252a26"))
	_box(origin + Vector3(0, 2, -30), Vector3(12, 4, 0.2), Color("8b9185"))
	for index: int in 24:
		_box(origin + Vector3((index - 12) * 0.4, 2, -29.85), Vector3(0.15, 4, 0.1), Color("242b29"))
	for index: int in 7:
		for side: float in [-1.0, 1.0]:
			_box(origin + Vector3(side * 2.8, 1.5, -index * 4.0), Vector3(0.25, 3, 0.25), Color("b3b7ab"))
	player.position = origin + Vector3(0, 0.02, 0)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.stop_motion(true)
	transition_seconds = 0.1


func _box(at: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	box.material = material
	mesh.mesh = box
	add_child(mesh)
	mesh.position = at


func _process(delta: float) -> void:
	if not OS.has_feature("web"):
		return
	var command = JavaScriptBridge.eval("window.staminaFixtureCommand || ''")
	if command is String and not command.is_empty():
		JavaScriptBridge.eval("window.staminaFixtureCommand = ''")
		match command:
			"pc": enter_computer()
			"leave": leave_computer(false)
	_telemetry_time += delta
	if _telemetry_time < 0.05:
		return
	_telemetry_time = 0.0
	var data := {
		"value": player.stamina.value,
		"exhausted": player.stamina.exhausted,
		"sprinting": player.is_sprinting,
		"speed": Vector2(player.velocity.x, player.velocity.z).length(),
		"fatigue": player.stamina.fatigue_amount(),
		"smear_pixels": (hud.smear_uv * get_viewport().get_visible_rect().size).length(),
		"effect_visible": hud.fatigue.visible,
		"bar_ratio": hud.displayed_ratio,
		"bar_alpha": hud.bar_alpha,
		"bar_center": hud.bar.get_global_rect().get_center().x,
		"screen_center": get_viewport().get_visible_rect().size.x * 0.5,
		"hud_visible": hud.visible,
		"mode": int(mode),
	}
	JavaScriptBridge.eval("window.staminaTelemetry = " + JSON.stringify(data))
