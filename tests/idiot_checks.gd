extends Node
var failures: int = 0
var game: Node3D
var director: AtmosphereDirector


func expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("IDIOT: " + message)


func frames(count: int = 3) -> void:
	for i: int in count:
		await get_tree().process_frame


func make_game() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	# Isolate this event's single-candidate fallback from new production content.
	game.atmosphere_config = AtmosphereConfig.new()
	game.atmosphere_config.events.append(load("res://data/atmosphere/you_are_an_idiot.tres"))
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	game.transition_seconds = 0.02
	game.shift.set_process(false)
	game.threats.set_process(false)
	director = game.atmosphere
	director.set_process(false)


func sit() -> void:
	game.enter_computer()
	await get_tree().create_timer(0.2).timeout
	expect(game.mode == game.Mode.COMPUTER, "Real seat transition reaches PC")
	game.terminal_ui.launch_app(&"notepad")
	await frames()


func mouse_button(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_tree().root.push_input(event)


func motion(at: Vector2, relative: Vector2 = Vector2.ZERO, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	get_tree().root.push_input(event)


func click_close(event: YouAreAnIdiot) -> void:
	var popup: IdiotPopup = event.popups.back()
	var at := popup.close_button.get_global_rect().get_center()
	motion(at)
	mouse_button(at, true)
	mouse_button(at, false)
	await frames(1)


func snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("LOCALAPPDATA") + "/Temp/opencode/idiot_" + name + ".png")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	make_game()
	var profile: AtmosphereProfile = game.atmosphere_config.events[0]
	expect(profile.id == &"you_are_an_idiot" and profile.random_trigger and profile.transition_trigger and not profile.walking, "Real content is registered for both triggers, PC only")
	expect(not director.request_event(profile.id, true), "Cannot start while walking")
	await sit()
	game.terminal_ui.notepad.editor.text = "my evidence stays intact"
	var trigger: Button
	for button: Button in game.dev_menu._overlay.find_children("*", "Button", true, false):
		if button.text == "TriggerYouAreAnIdiot":
			trigger = button
	expect(trigger != null, "Dedicated dev trigger exists")
	game.dev_menu.open_menu()
	trigger.pressed.emit()
	await frames()
	var event: YouAreAnIdiot = director._active as YouAreAnIdiot
	expect(event != null and not game.dev_menu.is_open, "Dev trigger closes menu and starts event")
	if event == null:
		get_tree().quit(1)
		return
	expect(event.popups.size() == 1 and not event.chaotic and event.popups[0].velocity == Vector2.ZERO, "Initial popup stays still")
	expect(event.audio.playing and event.audio.get_parent() == game.terminal.get_node("Monitor"), "One positional laugh belongs to computer")
	event.audio.stop()
	event.audio.finished.emit()
	expect(event.audio.playing, "Finished laugh repeats on the same source")
	expect(not game.trigger_police() and not game.trigger_power_outage(), "Atmosphere blocks new threats and blackout")
	var popup := event.popups[0]
	var old_position := popup.position
	var header := popup.global_position + Vector2(100, 15)
	motion(header)
	mouse_button(header, true)
	motion(header + Vector2(45, 25), Vector2(45, 25), true)
	mouse_button(header + Vector2(45, 25), false)
	await frames()
	expect(popup.position.distance_to(old_position) > 20.0, "Initial title bar really drags")
	await snapshot("single")
	await click_close(event)
	expect(event.popups.size() == 2 and event.chaotic, "Real GUI cross adds one copy and starts chaos")
	expect(game.terminal_ui.active_app == &"notepad", "Popup click does not activate underlying app")
	old_position = popup.position
	director.advance(0.15)
	expect(popup.position != old_position and not popup.draggable, "All popups bounce and stop accepting drags")
	for i: int in 6:
		await click_close(event)
	expect(event.popups.size() == 8 and event.closing_mode, "Exactly eight popups permanently unlock closing")
	expect(game.terminal_ui.notepad.editor.text == "my evidence stays intact", "Event never changes notes")
	director.advance(0.7)
	await snapshot("eight")
	event.overlay.size = Vector2(250, 180)
	event._fit_popups()
	director.advance(0.5)
	for item: IdiotPopup in event.popups:
		expect(Rect2(Vector2.ZERO, event.overlay.size + Vector2(0.01, 0.01)).encloses(Rect2(item.position, item.size)), "Resize/bounce keeps every popup in workspace")
	event.overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	event._fit_popups()
	game.leave_computer(false)
	await get_tree().create_timer(0.2).timeout
	var before := event.elapsed
	director.advance(1.0)
	expect(game.mode == game.Mode.WALKING and not event.overlay.is_visible_in_tree(), "Leaving PC hides all popups")
	expect(event.elapsed > before and event.audio.playing, "Timer and positional sound continue outside PC")
	await sit()
	expect(event.overlay.is_visible_in_tree() and event.popups.size() == 8, "Returning restores surviving popups")
	await click_close(event)
	expect(event.popups.size() == 7 and event.closing_mode, "After eight, cross really closes instead of copying")
	for i: int in 7:
		await click_close(event)
	expect(event.popups.is_empty(), "Every popup can be closed")
	var audio: AudioStreamPlayer3D = event.audio
	var overlay_ref: WeakRef = weakref(event.overlay)
	director.advance(0.1)
	expect(audio.volume_db < event.laugh_volume_db, "Early completion fades sound")
	director.advance(0.11)
	expect(not director.is_busy() and not audio.playing, "Last closed popup completes early after short fade")
	await frames()
	expect(overlay_ref.get_ref() == null and game.terminal_ui.transient_overlay == null, "Completion removes overlay and input registration")

	expect(director.request_event(profile.id, true), "Dev replay is allowed")
	event = director._active as YouAreAnIdiot
	director.advance(14.9)
	expect(director.is_busy() and event.popups.size() == 1 and not event.chaotic, "Ignoring popup never multiplies it")
	expect(event.audio.volume_db < event.laugh_volume_db, "Natural expiry also fades sound")
	director.advance(0.11)
	expect(not director.is_busy(), "Ignored event expires fifteen seconds from appearance")
	await frames()

	director.request_event(profile.id, true)
	game.shift._finish_stage()
	expect(game.shift.state == ShiftDirector.State.EVENT and game.mode == game.Mode.COMPUTER, "Active event fulfils transition without ejection")
	director.advance(15)
	game.shift._process(0)
	expect(game.shift.stage == 1 and game.shift.state == ShiftDirector.State.ROUTE, "Completed event releases next route")
	game.shift._finish_stage()
	expect(director.active_id == profile.id, "Exhausted single-event pool can repeat on guaranteed transition")
	director.cancel()
	game.shift._process(0)

	director.used.clear()
	director.reserves = [&"", &""]
	director.start_run()
	director.reserves = [&"", &""]
	game.shift.state = ShiftDirector.State.ROUTE
	director.clear_cooldown()
	director.advance(1)
	expect(director.active_id == profile.id and director.random_count == 1, "Same real handler supports random scheduling")
	event = director._active as YouAreAnIdiot
	audio = event.audio
	game.shift.state = ShiftDirector.State.REPORT
	game.shift._process(0)
	expect(not director.is_busy() and not audio.playing and game.terminal_ui.chat.session.quiz_started, "Report cancels windows and laugh immediately")
	game.queue_free()
	await frames()

	make_game()
	await sit()
	expect(director.used.is_empty(), "Restart resets used-event state")
	director.request_event(profile.id, true)
	event = director._active as YouAreAnIdiot
	audio = event.audio
	director.enabled = false
	expect(not director.is_busy() and not audio.playing, "Disable cancels real event safely")
	director.enabled = true
	director.request_event(profile.id, true)
	event = director._active as YouAreAnIdiot
	event.duration_seconds = 30.0
	audio = event.audio
	director.advance(17.01)
	expect(not director.is_busy() and not audio.playing, "Watchdog cleans real content even if its duration is misconfigured")
	director.request_event(profile.id, true)
	event = director._active as YouAreAnIdiot
	var audio_ref: WeakRef = weakref(event.audio)
	overlay_ref = weakref(event.overlay)
	game.queue_free()
	await frames()
	expect(audio_ref.get_ref() == null and overlay_ref.get_ref() == null, "Live teardown leaves no audio or UI nodes")
	print("IDIOT SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.threatTestResult = " + JSON.stringify({"failures": failures}))
	else:
		await get_tree().create_timer(0.3).timeout
		get_tree().quit(0 if failures == 0 else 1)
