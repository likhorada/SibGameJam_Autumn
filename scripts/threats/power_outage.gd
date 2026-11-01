class_name PowerOutage
extends ThreatEvent
## The blackout and all repeated corridor encounters own ONE slot until real repair.
@export var settings: CorridorEntityConfig = preload("res://data/threats/corridor_entity.tres")
var game: Node3D
var entity: CorridorEntity
var entity_enabled: bool = true
var _running: bool = false
var spark_audio: AudioStreamPlayer3D


func bind(value: Node3D) -> void:
	game = value
	game.power.power_changed.connect(_on_power_changed)


func _ready() -> void:
	spark_audio = AudioStreamPlayer3D.new()
	spark_audio.name = "FuseboxSparkAudio"
	spark_audio.stream = preload("res://assets/audio/spark.wav")
	spark_audio.bus = &"SFX"
	spark_audio.volume_db = -6.0
	spark_audio.unit_size = 7.0
	spark_audio.max_distance = 22.0
	add_child(spark_audio)
	spark_audio.global_position = game.power.board.global_position
	entity_enabled = settings.enabled
	entity = CorridorEntity.new()
	entity.settings = settings
	entity.bind(game)
	add_child(entity)


func can_start() -> bool:
	return is_instance_valid(game) and game.power.powered and not game.run_ended


func can_schedule() -> bool:
	return can_start() and game.mode == game.Mode.COMPUTER


func warning_started() -> void:
	_running = true
	if not game.power.cut_power():
		_running = false
		resolved.emit(&"cancelled")
		return
	spark_audio.play()
	if entity_enabled:
		entity.start()


func advance(delta: float) -> void:
	if _running and entity_enabled and not game.power.powered:
		entity.advance(delta)


func set_entity_enabled(value: bool) -> void:
	entity_enabled = value
	entity.stop()
	if _running and value and not game.power.powered:
		entity.start()


func has_active_encounter() -> bool:
	return entity.phase in [CorridorEntity.Phase.WARNING, CorridorEntity.Phase.ACTIVE, CorridorEntity.Phase.RETREATING]


func _on_power_changed(powered: bool) -> void:
	if powered and _running:
		_running = false
		entity.stop()
		resolved.emit(&"repaired")


func ended(_outcome: StringName) -> void:
	_running = false
	if is_instance_valid(spark_audio):
		spark_audio.stop()
	if is_instance_valid(entity):
		entity.stop()
	if is_instance_valid(game) and game.is_inside_tree() and is_instance_valid(game.power) and game.power.is_inside_tree() and not game.run_ended:
		game.power.restore_power()
