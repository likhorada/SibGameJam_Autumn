extends Node
## Small shared settings store. Fullscreen is deliberately requested only by a click.
var volume: float = 1.0
var sensitivity: float = 0.0022
var language: String = "en"
var _save_timer: Timer

func _ready() -> void:
	language = "ru" if OS.get_locale_language() == "ru" else "en"
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		volume = clampf(float(config.get_value("settings", "volume", volume)), 0.05, 1.0)
		sensitivity = clampf(float(config.get_value("settings", "sensitivity", sensitivity)), 0.0005, 0.006)
		var saved := str(config.get_value("settings", "language", language))
		if saved in ["en", "ru"]:
			language = saved
	TranslationServer.set_locale(language)
	AudioServer.set_bus_volume_db(0, linear_to_db(volume))
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.3
	_save_timer.timeout.connect(save)
	add_child(_save_timer)

func apply() -> void:
	volume = clampf(volume, 0.05, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(volume))
	TranslationServer.set_locale(language)
	_save_timer.start()

func save() -> void:
	var config := ConfigFile.new()
	config.set_value("settings", "volume", volume)
	config.set_value("settings", "sensitivity", sensitivity)
	config.set_value("settings", "language", language)
	if config.save("user://settings.cfg") != OK:
		push_warning("Could not save settings")
