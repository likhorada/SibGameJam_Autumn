extends Control

const GAME_PATH := "res://scenes/main.tscn"
@export var intro_seconds: float = 3.0
var intro: ColorRect
var intro_label: Label
var intro_time: float = 0.0
var menu: Control
var panel: PanelContainer
var settings: VBoxContainer
var credits: VBoxContainer
var play: Button
var volume: HSlider
var sensitivity: HSlider
var language: OptionButton
var fullscreen: CheckButton
var joke: Label
var volume_value: Label
var timecode: Label
var loading: bool = false
var _return_focus: Control
var title: Label

func _exit_tree() -> void:
	$MenuMusic.stop()

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_theme()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.48)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu = Control.new()
	add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title = _label(menu, "Mutual Observer", 48)
	title.position = Vector2(44, 35)
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var column := VBoxContainer.new()
	menu.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	column.offset_left = 44
	column.offset_top = -260
	column.offset_right = 330
	column.offset_bottom = -40
	column.add_theme_constant_override("separation", 12)
	play = _button(column, "PLAY", _play)
	_button(column, "SETTINGS", _open_panel.bind(true))
	_button(column, "CREDITS", _open_panel.bind(false))
	var exit := _button(column, "EXIT", func(): Preferences.save(); get_tree().quit())
	exit.visible = not OS.has_feature("web")
	timecode = _label(self, "", 16)
	timecode.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	timecode.offset_left = -305
	timecode.offset_top = 115
	timecode.offset_right = -32
	_build_panel()
	intro = ColorRect.new()
	intro.color = Color.BLACK
	add_child(intro)
	intro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	intro_label = _label(intro, "sample intro", 30)
	intro_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	intro_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	intro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	intro_label.modulate.a = 0.0
	menu.hide()
	resized.connect(_fit_panel)
	_fit_panel.call_deferred()

func _fit_panel() -> void:
	var factor := minf(1.0, minf((size.x - 32.0) / panel.size.x, (size.y - 32.0) / panel.size.y))
	panel.scale = Vector2.ONE * factor
	panel.position = (size - panel.size * factor) * 0.5
	title.add_theme_font_size_override("font_size", 32 if size.x < 800 else 48)

func _build_theme() -> void:
	theme = Theme.new()
	# Artist-supplied pixel font for the game UI outside the PC desktop.
	theme.default_font = preload("res://assets/fonts/static/Handjet-SemiBold.ttf")
	theme.default_font_size = 22
	var empty := StyleBoxFlat.new()
	empty.bg_color = Color(0, 0, 0, 0)
	empty.content_margin_left = 10
	empty.content_margin_right = 10
	empty.content_margin_top = 6
	empty.content_margin_bottom = 6
	var hover := empty.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.75, 0.8, 0.75, 0.13)
	for kind: String in ["Button", "CheckButton", "OptionButton"]:
		theme.set_stylebox("normal", kind, empty)
		theme.set_stylebox("hover", kind, hover)
		theme.set_stylebox("pressed", kind, hover)
		theme.set_stylebox("focus", kind, hover)
		theme.set_color("font_color", kind, Color("c8cec5"))
	theme.set_color("font_color", "Label", Color("c8cec5"))
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.025, 0.035, 0.03, 0.97)
	box.content_margin_left = 24
	box.content_margin_right = 24
	box.content_margin_top = 20
	box.content_margin_bottom = 20
	theme.set_stylebox("panel", "PanelContainer", box)

func _label(parent: Node, text: String, font_size: int = 22) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.name = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _build_panel() -> void:
	panel = PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -270
	panel.offset_right = 270
	panel.offset_top = -250
	panel.offset_bottom = 250
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	settings = VBoxContainer.new()
	settings.add_theme_constant_override("separation", 10)
	column.add_child(settings)
	_label(settings, "SETTINGS", 28)
	_label(settings, "VOLUME")
	volume = HSlider.new()
	volume.max_value = 100
	volume.value = Preferences.volume * 100.0
	volume.custom_minimum_size.y = 26
	settings.add_child(volume)
	volume_value = _label(settings, "%d%%" % volume.value, 16)
	volume.value_changed.connect(_volume_changed)
	_label(settings, "SENSITIVITY")
	sensitivity = HSlider.new()
	sensitivity.min_value = 0.0005
	sensitivity.max_value = 0.006
	sensitivity.step = 0.0001
	sensitivity.value = Preferences.sensitivity
	sensitivity.custom_minimum_size.y = 26
	settings.add_child(sensitivity)
	sensitivity.value_changed.connect(func(value: float): Preferences.sensitivity = value; Preferences.apply())
	fullscreen = CheckButton.new()
	fullscreen.text = "FULLSCREEN"
	settings.add_child(fullscreen)
	fullscreen.toggled.connect(_fullscreen)
	_label(settings, "LANGUAGE")
	language = OptionButton.new()
	language.add_item("English")
	language.add_item("Русский")
	language.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	language.select(1 if Preferences.language == "ru" else 0)
	settings.add_child(language)
	language.item_selected.connect(func(index: int): Preferences.language = "ru" if index == 1 else "en"; Preferences.apply())
	joke = _label(settings, "", 16)
	joke.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	joke.custom_minimum_size.y = 42
	credits = VBoxContainer.new()
	column.add_child(credits)
	_label(credits, "CREDITS", 28)
	var placeholder := _label(credits, "to be filled")
	placeholder.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_button(column, "BACK", _close_panel)
	panel.hide()

func _volume_changed(value: float) -> void:
	if value < 5.0:
		volume.set_value_no_signal(5.0)
		joke.text = "NO_SILENCE"
	else:
		joke.text = ""
	Preferences.volume = maxf(value, 5.0) / 100.0
	volume_value.text = "%d%%" % (Preferences.volume * 100.0)
	Preferences.apply()

func _fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)

func _open_panel(show_settings: bool) -> void:
	_return_focus = get_viewport().gui_get_focus_owner()
	menu.hide()
	settings.visible = show_settings
	credits.visible = not show_settings
	panel.show()
	_fit_panel.call_deferred()
	if show_settings:
		volume.grab_focus()
	else:
		panel.find_child("BACK", true, false).grab_focus()

func _close_panel() -> void:
	Preferences.save()
	panel.hide()
	menu.show()
	if is_instance_valid(_return_focus):
		_return_focus.grab_focus()

func _finish_intro() -> void:
	intro.hide()
	menu.show()
	play.grab_focus()

func _input(event: InputEvent) -> void:
	if intro.visible and ((event is InputEventMouseButton and event.pressed) or event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel")):
		_finish_intro()
		get_viewport().set_input_as_handled()
	elif panel.visible and event.is_action_pressed("ui_cancel"):
		_close_panel()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if intro.visible:
		intro_time += delta
		intro_label.modulate.a = clampf(minf(intro_time / 0.6, (intro_seconds - intro_time) / 0.6), 0.0, 1.0)
		if intro_time >= intro_seconds:
			_finish_intro()
	var seconds := int($Background.elapsed)
	timecode.text = "CAM-%02d   %s REC\n1998-10-30  %02d:%02d:%02d" % [$Background.selected_index + 1, "*" if seconds % 2 == 0 else " ", (seconds / 3600) % 24, (seconds / 60) % 60, seconds % 60]
	fullscreen.set_pressed_no_signal(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	if loading:
		var status := ResourceLoader.load_threaded_get_status(GAME_PATH)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			loading = false
			var scene := ResourceLoader.load_threaded_get(GAME_PATH) as PackedScene
			if get_tree().change_scene_to_packed(scene) != OK:
				_load_failed()
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_load_failed()

func _play() -> void:
	if loading:
		return
	Preferences.save()
	play.text = "LOADING"
	play.disabled = true
	loading = ResourceLoader.load_threaded_request(GAME_PATH) == OK
	if not loading:
		_load_failed()

func _load_failed() -> void:
	loading = false
	play.disabled = false
	play.text = "LOAD_FAILED"
