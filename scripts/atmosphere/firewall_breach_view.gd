class_name FirewallBreachView
extends Control
## A stable clickable layout; only the decorative border/header may pulse or glitch.
signal port_pressed(index: int)
signal block_pressed

const BASE_SIZE := Vector2(620, 548)
var port_buttons: Array[Button] = []
var block_button: Button
var instruction: Label
var _font: Font = ThemeDB.fallback_font
var _ports: Array[bool] = []
var _seconds: float = 15.0
var _duration: float = 15.0
var _elapsed: float = 0.0
var _won: bool = false
var _styles: Dictionary = {}


func _ready() -> void:
	size = BASE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_styles()
	instruction = Label.new()
	instruction.position = Vector2(36, 95)
	instruction.size = Vector2(548, 44)
	instruction.text = tr("FW_INSTRUCTIONS")
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction.mouse_filter = Control.MOUSE_FILTER_IGNORE
	instruction.add_theme_font_override("font", _font)
	instruction.add_theme_font_size_override("font_size", 15)
	instruction.add_theme_color_override("font_color", Color("d2d7d8"))
	add_child(instruction)
	for i: int in 9:
		var button := Button.new()
		button.name = "Port%d" % FirewallBreachConfig.PORT_NUMBERS[i]
		button.position = Vector2(36 + (i % 3) * (560.0 / 3.0), 168 + int(i / 3) * 88)
		button.size = Vector2(524.0 / 3.0, 76)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_override("font", _font)
		button.add_theme_font_size_override("font_size", 21)
		button.pressed.connect(port_pressed.emit.bind(i))
		add_child(button)
		port_buttons.append(button)
	block_button = Button.new()
	block_button.name = "BlockConnection"
	block_button.text = "BLOCK CONNECTION"
	block_button.position = Vector2(36, 448)
	block_button.size = Vector2(548, 46)
	block_button.focus_mode = Control.FOCUS_NONE
	block_button.add_theme_font_override("font", _font)
	block_button.add_theme_font_size_override("font_size", 20)
	block_button.pressed.connect(block_pressed.emit)
	add_child(block_button)


func _build_styles() -> void:
	for state: String in ["open", "closed"]:
		var palette := Color("d84e4e") if state == "open" else Color("69cd89")
		for variant: String in ["normal", "hover", "pressed", "disabled"]:
			var style := StyleBoxFlat.new()
			style.bg_color = palette.darkened(0.72 if variant == "normal" else 0.6)
			style.border_color = palette
			style.set_border_width_all(2)
			style.set_content_margin_all(2.0)
			_styles[state + variant] = style


func fit_to_area(area: Vector2) -> void:
	var factor := maxf(0.01, minf(1.0, minf((area.x - 24) / BASE_SIZE.x, (area.y - 24) / BASE_SIZE.y)))
	scale = Vector2.ONE * factor
	position = ((area - BASE_SIZE * factor) * 0.5).max(Vector2.ZERO)


func present(round_state: FirewallRound, won: bool = false) -> void:
	_seconds = round_state.seconds_left()
	_duration = round_state.duration
	_elapsed = round_state.elapsed
	_won = won
	for i: int in port_buttons.size():
		var button := port_buttons[i]
		button.visible = not won
		var is_open := round_state.ports[i]
		if _ports.size() != 9 or _ports[i] != is_open:
			var state := "open" if is_open else "closed"
			button.text = "%d\n%s" % [FirewallBreachConfig.PORT_NUMBERS[i], tr("FW_OPEN" if is_open else "FW_CLOSED")]
			for variant: String in ["normal", "hover", "pressed", "disabled"]:
				button.add_theme_stylebox_override(variant, _styles[state + variant])
			for variant: String in ["font_color", "font_hover_color", "font_pressed_color"]:
				button.add_theme_color_override(variant, Color("ffb5b5") if is_open else Color("b4f2c7"))
	_ports.assign(round_state.ports)
	block_button.visible = not won
	block_button.disabled = round_state.open_count() != 0
	instruction.visible = not won
	queue_redraw()


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_elapsed * TAU * 0.7)
	var accent := Color("69cd89") if _won else Color("a83939").lerp(Color("d45d5d"), pulse)
	draw_rect(Rect2(Vector2.ZERO, BASE_SIZE), Color("bcc1c5"))
	draw_rect(Rect2(4, 4, 612, 30), Color("394959") if _won else Color("762b32"))
	draw_string(_font, Vector2(16, 26), "FIREWALL BREACH", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color.WHITE)
	draw_rect(Rect2(6, 38, 608, 504), Color("111719"))
	draw_rect(Rect2(6, 38, 608, 504), accent, false, 2.0)
	if _won:
		draw_string(_font, Vector2(24, 270), "CONNECTION BLOCKED", HORIZONTAL_ALIGNMENT_CENTER, 572, 31, accent)
		draw_string(_font, Vector2(24, 309), tr("FW_RESTORED"), HORIZONTAL_ALIGNMENT_CENTER, 572, 16, Color("d2d7d8"))
		return
	draw_string(_font, Vector2(36, 78), tr("FW_INTRUSION"), HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("f0bbbb"))
	draw_string(_font, Vector2(410, 78), "%.1f s" % _seconds, HORIZONTAL_ALIGNMENT_RIGHT, 174, 27, Color.WHITE)
	draw_string(_font, Vector2(36, 152), tr("FW_OPEN_COUNT") % _ports.count(true), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("b2bcc0"))
	draw_rect(Rect2(36, 157, 548, 3), Color("303b40"))
	draw_rect(Rect2(36, 157, 548 * clampf(_seconds / _duration, 0, 1), 3), accent)
	var ready := _ports.size() == 9 and not _ports.has(true)
	draw_string(_font, Vector2(36, 438), tr("FW_READY" if ready else "FW_WATCH_PORTS"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("8ed4a5") if ready else Color("aab4b8"))
	draw_string(_font, Vector2(36, 522), tr("FW_ESCAPE"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("aab4b8"))
	# Small header-only scan fragments, never on the numbers or hit targets. No strobe.
	if fmod(_elapsed, 3.1) < 0.09:
		draw_rect(Rect2(348, 12, 40, 2), Color(0.8, 0.5, 0.5, 0.35))
		draw_rect(Rect2(470, 27, 72, 1), Color(0.8, 0.5, 0.5, 0.25))
