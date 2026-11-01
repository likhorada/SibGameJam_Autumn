extends SceneTree
## Run in a temporary copy of the project, NOT the working project.

func _initialize() -> void:
	assert(ProjectSettings.globalize_path("res://").contains("cctv-animation-web"))
	var project := ConfigFile.new()
	assert(project.load("res://project.godot") == OK)
	project.set_value("application", "run/main_scene", "res://tests/cctv_animation_fixture.tscn")
	assert(project.save("res://project.godot") == OK)
	var presets := ConfigFile.new()
	assert(presets.load("res://export_presets.cfg") == OK)
	presets.set_value("preset.0", "exclude_filter", "doc/*,tools/*,assets/models/*.blend,assets/textures/*.psd")
	assert(presets.save("res://export_presets.cfg") == OK)
	quit()
