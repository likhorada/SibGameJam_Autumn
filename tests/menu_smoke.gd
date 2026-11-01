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
	if DisplayServer.get_name() != "headless":
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("LOCALAPPDATA") + "/Temp/opencode/menu.png")
	menu._play()
	for frame: int in 300:
		await process_frame
		if current_scene != menu:
			break
	expect(current_scene != menu, "Play transitions to game")
	if current_scene != menu:
		expect(current_scene.get_node_or_null("Apartment/RoomDoor") != null, "Play loads the interactive apartment door")
		expect(current_scene.power._screen != null, "Power system resolves the laptop screen mesh")
		expect(is_equal_approx(current_scene.player.mouse_sensitivity, 0.003), "Sensitivity applied to player")
		expect(root.find_children("Background", "TextureRect", true, false).is_empty(), "Menu background freed")
		await physics_frame
		expect(current_scene.hint.text == "Нажми ЛКМ, чтобы осмотреться", "Gameplay hint uses saved Russian locale")
		expect(current_scene.terminal_ui.start_button.text == "Пуск", "Desktop start button localized")
	prefs.volume = old_volume
	prefs.sensitivity = old_sensitivity
	prefs.language = old_language
	prefs.apply()
	prefs.save()
	print("MENU SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
