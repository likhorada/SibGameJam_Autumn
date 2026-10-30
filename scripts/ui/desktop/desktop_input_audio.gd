extends Node
## One randomized sound per physical press, never per generated chat character.
var keyboard: Array[AudioStream] = []
var clicks: Array[AudioStream] = []
var voices: Array[AudioStreamPlayer] = []
var next_voice: int = 0
var enabled: bool = false
var presses_played: int = 0


func _ready() -> void:
	for index: int in range(1, 10):
		keyboard.append(load("res://assets/audio/keystroke%d.wav" % index))
	for index: int in range(1, 3):
		clicks.append(load("res://assets/audio/mouse_click%d.wav" % index))
	for index: int in 6:
		var voice := AudioStreamPlayer.new()
		voice.bus = &"SFX"
		voice.volume_db = -12.0
		add_child(voice)
		voices.append(voice)


func _input(event: InputEvent) -> void:
	if not enabled or not get_parent().is_visible_in_tree():
		return
	var pool: Array[AudioStream] = []
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		pool = clicks
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode not in [KEY_F7, KEY_ESCAPE]:
		pool = keyboard
	if pool.is_empty():
		return
	var voice := voices[next_voice]
	next_voice = (next_voice + 1) % voices.size()
	voice.stream = pool.pick_random()
	voice.play()
	presses_played += 1


func stop() -> void:
	enabled = false
	for voice: AudioStreamPlayer in voices:
		voice.stop()
