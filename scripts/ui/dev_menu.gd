extends CanvasLayer
## Deliberately available in release. Disable Enabled on the scene node for publishing.
signal opened
signal closed

@export var enabled: bool = true
@export_range(0.1, 10.0) var hold_seconds: float = 5.0
var game: Node3D
var is_open: bool = false
var _holding: bool = false
var _held_seconds: float = 0.0
var _overlay: ColorRect
var _status: Label
var _unlimited: CheckButton
var _noclip_toggle: CheckButton
var _debug_hud_toggle: CheckButton
var _debug_hud_panel: PanelContainer
var _debug_hud_label: Label
var _debug_hud_enabled: bool = false
var _close_button: Button
var _neighbor_enabled: CheckButton
var _trigger_neighbor: Button
var _police_enabled: CheckButton
var _trigger_police: Button
var _outage_enabled: CheckButton
var _entity_enabled: CheckButton
var _trigger_outage: Button
var _scroll: ScrollContainer
var _atmosphere_enabled: CheckButton
var _atmosphere_list: OptionButton
var _atmosphere_status: Label


func bind(value: Node3D) -> void:
	game = value
	layer = 30
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.85)
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var menu_theme := Theme.new()
	# Same artist font as the menu; the desktop apps keep their own fonts.
	menu_theme.default_font = preload("res://assets/fonts/static/Handjet-SemiBold.ttf")
	_overlay.theme = menu_theme
	var center := CenterContainer.new()
	_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	center.add_child(panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	_scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	var title := Label.new()
	title.text = "DEV MENU"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	_status = Label.new()
	_status.custom_minimum_size = Vector2(420, 42)
	column.add_child(_status)
	_unlimited = CheckButton.new()
	_unlimited.text = "DEV_UNLIMITED"
	_unlimited.toggled.connect(func(value_enabled: bool): game.player.stamina.set_unlimited(value_enabled))
	column.add_child(_unlimited)
	_noclip_toggle = CheckButton.new()
	_noclip_toggle.text = "Noclip (Space/C: fly)"
	_noclip_toggle.toggled.connect(game.player.set_noclip_enabled)
	column.add_child(_noclip_toggle)
	_debug_hud_toggle = CheckButton.new()
	_debug_hud_toggle.text = "DEV_DEBUG_HUD"
	_debug_hud_toggle.toggled.connect(set_debug_hud_enabled)
	column.add_child(_debug_hud_toggle)
	_button(column, "DEV_POWER_OFF", func(): game.power.trigger_outage())
	_button(column, "DEV_POWER_ON", func(): game.power.restore_power())
	_button(column, "DEV_CLEAR_COOLDOWN", func(): game.threats.clear_cooldown())
	_neighbor_enabled = CheckButton.new()
	_neighbor_enabled.text = "PsychNeighbor"
	_neighbor_enabled.toggled.connect(func(value_enabled: bool): game.threats.set_event_enabled(&"psych_neighbor", value_enabled))
	column.add_child(_neighbor_enabled)
	_trigger_neighbor = _button(column, "TriggerNeighbor", func():
		close_menu()
		game.trigger_neighbor())
	_police_enabled = CheckButton.new()
	_police_enabled.text = "PoliceRaid"
	_police_enabled.toggled.connect(func(value_enabled: bool): game.threats.set_event_enabled(&"police_raid", value_enabled))
	column.add_child(_police_enabled)
	_trigger_police = _button(column, "TriggerPolice", func():
		close_menu()
		game.trigger_police())
	_outage_enabled = CheckButton.new()
	_outage_enabled.text = "PowerOutage"
	_outage_enabled.toggled.connect(func(value_enabled: bool): game.threats.set_event_enabled(&"power_outage", value_enabled))
	column.add_child(_outage_enabled)
	_entity_enabled = CheckButton.new()
	_entity_enabled.text = "CorridorEntity"
	_entity_enabled.toggled.connect(func(value_enabled: bool): game.outage.set_entity_enabled(value_enabled))
	column.add_child(_entity_enabled)
	_trigger_outage = _button(column, "TriggerPowerOutage", func():
		close_menu()
		game.trigger_power_outage())
	_button(column, "DisableThreats", func(): game.disable_threats())
	_atmosphere_enabled = CheckButton.new()
	_atmosphere_enabled.text = "Atmosphere events"
	_atmosphere_enabled.toggled.connect(func(value_enabled: bool): game.atmosphere.enabled = value_enabled)
	column.add_child(_atmosphere_enabled)
	_atmosphere_list = OptionButton.new()
	for id: StringName in game.atmosphere.event_ids():
		_atmosphere_list.add_item(String(id))
	column.add_child(_atmosphere_list)
	_button(column, "TriggerYouAreAnIdiot", func():
		close_menu()
		if not game.atmosphere.request_event(&"you_are_an_idiot", true):
			game.atmosphere.note("YouAreAnIdiot rejected: sit at PC; " + game.atmosphere.blocked_reason()))
	_button(column, "TriggerFirewallBreach", func():
		close_menu()
		if not game.atmosphere.request_event(&"firewall_breach", true):
			game.atmosphere.note("FirewallBreach rejected: sit at PC; " + game.atmosphere.blocked_reason()))
	_button(column, "TriggerQuestionPopup", func():
		close_menu()
		if not game.atmosphere.request_event(&"question_popup", true):
			game.atmosphere.note("Question rejected: PC / open question / empty deck; " + game.atmosphere.blocked_reason()))
	_button(column, "TriggerBathroomApparition", func():
		close_menu()
		if not game.atmosphere.request_event(&"bathroom_apparition", true):
			game.atmosphere.note("Bathroom rejected: already present / visible spawn / world blocked; " + game.atmosphere.blocked_reason()))
	_button(column, "TriggerRoomCamera", func():
		close_menu()
		if not game.atmosphere.request_event(&"room_camera_feed", true):
			game.atmosphere.note("Room camera rejected: sit at PC / already open / modal; " + game.atmosphere.blocked_reason()))
	_button(column, "Atmosphere: trigger selected", func():
		if _atmosphere_list.selected < 0:
			game.atmosphere.note("Dev start: empty pool")
			return
		var id := StringName(_atmosphere_list.get_item_text(_atmosphere_list.selected))
		close_menu()
		if not game.atmosphere.request_event(id, true):
			game.atmosphere.note("Dev start rejected: %s / %s" % [id, game.atmosphere.blocked_reason()]))
	_button(column, "Atmosphere: complete", func(): game.atmosphere.complete_event())
	_button(column, "Atmosphere: cancel", func(): game.atmosphere.cancel())
	_button(column, "Atmosphere: clear cooldown", func(): game.atmosphere.clear_cooldown())
	_atmosphere_status = Label.new()
	_atmosphere_status.custom_minimum_size.x = 420
	_atmosphere_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_atmosphere_status)
	_button(column, "OBS_DEV_NEXT", func():
		close_menu()
		if not is_instance_valid(game.shift):
			return
		if game.shift.state == ShiftDirector.State.ROUTE:
			game.shift.advance(300.0)
		elif game.shift.state == ShiftDirector.State.EVENT:
			game.shift.complete_event())
	_button(column, "DEV_CHAT_REPORT", func():
		if not game.power.powered or game.threats.is_busy() or game.mode not in [game.Mode.WALKING, game.Mode.COMPUTER]:
			return
		close_menu()
		game.atmosphere.cancel(&"quiz_started")
		if is_instance_valid(game.shift):
			game.shift.state = ShiftDirector.State.ENDED
		game.terminal_ui.chat.session.live_report = false
		game.terminal_ui.chat.session.start_quiz()
		game.terminal_ui.launch_app(&"chat")
		if game.mode == game.Mode.WALKING:
			game.enter_computer())
	_close_button = _button(column, "BACK", close_menu)
	_overlay.hide()
	_create_debug_hud()


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 30
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _create_debug_hud() -> void:
	_debug_hud_panel = PanelContainer.new()
	_debug_hud_panel.position = Vector2(12, 12)
	_debug_hud_panel.custom_minimum_size = Vector2(430, 0)
	_debug_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.02, 0.015, 0.88)
	style.border_color = Color(0.53, 0.66, 0.38, 0.85)
	style.set_border_width_all(1)
	style.set_content_margin(SIDE_LEFT, 10.0)
	style.set_content_margin(SIDE_RIGHT, 10.0)
	style.set_content_margin(SIDE_TOP, 8.0)
	style.set_content_margin(SIDE_BOTTOM, 8.0)
	_debug_hud_panel.add_theme_stylebox_override("panel", style)
	_debug_hud_label = Label.new()
	_debug_hud_label.custom_minimum_size.x = 408
	_debug_hud_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_debug_hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_hud_label.add_theme_font_size_override("font_size", 16)
	_debug_hud_panel.add_child(_debug_hud_label)
	add_child(_debug_hud_panel)
	_debug_hud_panel.hide()


func set_debug_hud_enabled(value: bool) -> void:
	_debug_hud_enabled = value
	if is_instance_valid(_debug_hud_toggle):
		_debug_hud_toggle.set_pressed_no_signal(value)
	if is_instance_valid(_debug_hud_panel):
		_debug_hud_panel.visible = value and not is_open
	if value:
		_update_debug_hud()


func _update_debug_hud() -> void:
	if not is_instance_valid(game) or not is_instance_valid(_debug_hud_label):
		return
	var threat_id := String(game.threats.active_id).to_upper().replace("_", " ")
	if threat_id.is_empty():
		threat_id = "—"
	var entity: CorridorEntity = game.outage.entity
	var entity_phase: String = CorridorEntity.Phase.keys()[entity.phase]
	var danger_text: String
	if entity.is_chasing:
		danger_text = tr("DEBUG_HUD_CHASING")
	elif entity.phase == CorridorEntity.Phase.ACTIVE:
		danger_text = tr("DEBUG_HUD_DANGER")
	else:
		danger_text = tr("DEBUG_HUD_NO_DANGER")
	var lines := PackedStringArray([
		tr("DEBUG_HUD_TITLE"),
		tr("DEBUG_HUD_THREATS") % [ThreatManager.State.keys()[game.threats.state], threat_id, game.threats.phase_seconds_left],
		tr("DEBUG_HUD_NEIGHBOR") % PsychNeighbor.Visit.keys()[game.neighbor.visit],
		tr("DEBUG_HUD_POLICE") % PoliceRaid.Visit.keys()[game.police.visit],
		tr("DEBUG_HUD_ENTITY") % [entity_phase, danger_text],
	])
	lines.append(game.atmosphere.debug_status())
	if entity.phase != CorridorEntity.Phase.DORMANT:
		lines.append(tr("DEBUG_HUD_ENTITY_TIMER") % _entity_time_left(entity))
	if entity.phase == CorridorEntity.Phase.ACTIVE:
		var distance := Vector2(
			game.player.global_position.x - entity.visual.global_position.x,
			game.player.global_position.z - entity.visual.global_position.z
		).length()
		lines.append(tr("DEBUG_HUD_ENTITY_ERROR") % [entity.error_seconds, entity.settings.error_budget_seconds])
		lines.append(tr("DEBUG_HUD_ENTITY_DISTANCE") % distance)
		var beam_hits_entity := entity.beam_hits()
		lines.append(tr("DEBUG_HUD_ENTITY_BEAM") % tr("DEBUG_HUD_YES" if beam_hits_entity else "DEBUG_HUD_NO"))
	_debug_hud_label.text = "\n".join(lines)


func _entity_time_left(entity: CorridorEntity) -> float:
	match entity.phase:
		CorridorEntity.Phase.WAITING:
			return maxf(0.0, entity.repeat_left)
		CorridorEntity.Phase.WARNING:
			return maxf(0.0, entity.settings.warning_seconds - entity.elapsed)
		CorridorEntity.Phase.ACTIVE:
			return maxf(0.0, entity.duration - entity.elapsed)
	return 0.0


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_F7:
		if not event.echo:
			_holding = event.pressed and enabled and not is_open
			_held_seconds = 0.0
		get_viewport().set_input_as_handled()
	elif is_open and event.is_action_pressed("back"):
		close_menu()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not enabled:
		_holding = false
		_held_seconds = 0.0
		if is_open:
			close_menu()
		return
	if _holding:
		_held_seconds += delta
		if _held_seconds >= hold_seconds and game.mode in [game.Mode.WALKING, game.Mode.COMPUTER, game.Mode.FUSEBOX, game.Mode.HIDING]:
			open_menu()
	if _debug_hud_enabled and not is_open:
		_update_debug_hud()
	if is_open:
		_atmosphere_enabled.set_pressed_no_signal(game.atmosphere.enabled)
		_atmosphere_status.text = game.atmosphere.debug_status()
		_scroll.custom_minimum_size = Vector2(470, minf(620.0, maxf(180.0, get_viewport().get_visible_rect().size.y - 36.0)))
		_status.text = tr("DEV_STATUS") % ["POWER_ON" if game.power.powered else "POWER_OFF", game.threats.wait_seconds_left, str(game.power.board.latched)]
		_status.text += "\nThreats: %s / %s\nDoor: %s" % [ThreatManager.State.keys()[game.threats.state], game.threats.active_id, "OPEN" if game.room_door.is_open else "CLOSED"]
		_unlimited.set_pressed_no_signal(game.player.stamina.unlimited)
		_noclip_toggle.set_pressed_no_signal(game.player.noclip_enabled)
		_neighbor_enabled.set_pressed_no_signal(game.threats.is_event_enabled(&"psych_neighbor"))
		_trigger_neighbor.disabled = not game.threats.can_start_external_event() or not game.threats.is_event_enabled(&"psych_neighbor")
		_police_enabled.set_pressed_no_signal(game.threats.is_event_enabled(&"police_raid"))
		_trigger_police.disabled = not game.threats.can_start_external_event() or not game.threats.is_event_enabled(&"police_raid")
		_outage_enabled.set_pressed_no_signal(game.threats.is_event_enabled(&"power_outage"))
		_entity_enabled.set_pressed_no_signal(game.outage.entity_enabled)
		_trigger_outage.disabled = not game.threats.can_start_external_event() or not game.threats.is_event_enabled(&"power_outage")


func open_menu() -> void:
	if not enabled or is_open:
		return
	_holding = false
	_held_seconds = 0.0
	is_open = true
	_overlay.show()
	_debug_hud_panel.hide()
	opened.emit()
	_close_button.grab_focus()


func close_menu() -> void:
	if not is_open:
		return
	is_open = false
	_holding = false
	_held_seconds = 0.0
	_overlay.hide()
	_debug_hud_panel.visible = _debug_hud_enabled
	closed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_holding = false
		_held_seconds = 0.0
