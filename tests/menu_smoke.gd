extends SceneTree

var failures: int = 0
func _initialize() -> void:
	_run.call_deferred()

func expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var prefs := root.get_node("Preferences")
	var old_volume: float = prefs.volume
	var old_sensitivity: float = prefs.sensitivity
	var old_language: String = prefs.language
	var menu = load("res://scenes/menu/menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	var music: AudioStreamPlayer = menu.get_node("MenuMusic")
	var music_ref: WeakRef = weakref(music)
	expect(music.playing and music.stream.resource_path == "res://assets/audio/main_menu.wav", "Menu starts the authored music")
	expect((music.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "Menu music is imported as a forward loop")
	expect(music.bus == &"Ambience", "Menu music uses the master-controlled ambience bus")
	music.play(music.stream.get_length() - 0.05)
	await create_timer(0.2).timeout
	expect(music.playing, "Menu music continues beyond the loop boundary")
	expect(menu.intro.visible and not menu.menu.visible, "Intro is shown first")
	expect(menu.get_node("Background").viewport.get_child_count() == 1, "Only one background instantiated")
	menu._finish_intro()
	menu._open_panel(true)
	menu.volume.value = 0
	expect(is_equal_approx(prefs.volume, 0.05), "Volume floor enforced")
	expect(menu.joke.text == "NO_SILENCE", "Volume floor joke")
	menu.sensitivity.value = 0.003
	prefs.language = "en"
	prefs.apply()
	expect(TranslationServer.translate("PLAY") == "Play", "English translation")
	expect(TranslationServer.translate("Нажми ЛКМ, чтобы осмотреться") == "Click to look around", "Gameplay hint translation")
	prefs.language = "ru"
	prefs.apply()
	expect(TranslationServer.translate("PLAY") == "Играть", "Russian translation")
	prefs.save()
	var saved := ConfigFile.new()
	expect(saved.load("user://settings.cfg") == OK, "Settings file readable")
	expect(saved.get_value("settings", "language") == "ru", "Language persisted")
	expect(is_equal_approx(saved.get_value("settings", "volume"), 0.05), "Minimum volume persisted")
	menu._close_panel()
	menu._open_panel(false)
	expect(menu.credits.visible and not menu.settings.visible, "Credits panel")
	menu._close_panel()
	expect(music.playing, "Menu music continues through settings and credits")
	# Exercise recovery without relying on a deliberately broken game resource.
	menu._music_volume = music.volume_linear
	menu.play_transition = load("res://scripts/ui/menu_transition.gd").new()
	root.add_child(menu.play_transition)
	menu.play_transition.cover(music, 0.1)
	await create_timer(0.15).timeout
	menu._load_failed()
	await create_timer(menu.play_fade_in_seconds + 0.2).timeout
	expect(not menu.loading and not menu.play.disabled, "Loading failure unlocks the menu")
	expect(is_equal_approx(music.volume_linear, menu._music_volume), "Loading failure restores the music volume")
	expect(not is_instance_valid(menu.play_transition), "Loading failure removes the curtain")
	if DisplayServer.get_name() != "headless":
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("LOCALAPPDATA") + "/Temp/opencode/menu.png")
	var starting_volume := music.volume_linear
	menu._play()
	var transition: CanvasLayer = menu.play_transition
	var transition_ref: WeakRef = weakref(transition)
	expect(menu.loading and menu.play.disabled, "Play locks repeat requests during the transition")
	menu._play()
	expect(menu.play_transition == transition, "Repeated Play keeps the same transition")
	await create_timer(menu.play_fade_out_seconds * 0.4).timeout
	expect(current_scene == menu, "The menu stays alive while fading out")
	expect(transition.curtain.modulate.a > 0.0 and transition.curtain.modulate.a < 1.0, "Menu darkens gradually")
	expect(music.volume_linear > 0.0 and music.volume_linear < starting_volume, "Menu music fades gradually with the picture")
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if current_scene != null and current_scene != menu:
			break
	expect(current_scene != null and current_scene != menu, "Play transitions to game")
	if current_scene != null and current_scene != menu:
		expect(transition.curtain.modulate.a > 0.95, "Scene changes behind a black curtain")
		await create_timer(0.4).timeout
		expect(transition.curtain.modulate.a > 0.0 and transition.curtain.modulate.a < 1.0, "Gameplay reveals gradually")
		await create_timer(0.8).timeout
		expect(transition_ref.get_ref() == null, "Transition curtain is freed after revealing gameplay")
		expect(current_scene.get_node_or_null("Apartment/RoomDoor") != null, "Play loads the interactive apartment door")
		expect(current_scene.power._screen != null, "Power system resolves the laptop screen mesh")
		expect(is_equal_approx(current_scene.player.mouse_sensitivity, 0.003), "Sensitivity applied to player")
		expect(root.find_children("Background", "TextureRect", true, false).is_empty(), "Menu background freed")
		expect(music_ref.get_ref() == null, "Menu music player is freed when gameplay starts")
		await physics_frame
		expect(current_scene.hint.text == "Нажми ЛКМ, чтобы осмотреться", "Gameplay hint uses saved Russian locale")
		expect(current_scene.terminal_ui.start_button.text == "Пуск", "Desktop start button localized")
	prefs.volume = old_volume
	prefs.sensitivity = old_sensitivity
	prefs.language = old_language
	prefs.apply()
	prefs.save()
	# Stop mixing before freeing the loaded game's audio resources. The menu
	# transition starts the ambient loops even in a headless smoke test.
	if current_scene != menu:
		current_scene.ambient.set_process(false)
		current_scene.ambient.stop_all()
		await create_timer(0.2).timeout
	current_scene.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("MENU SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
