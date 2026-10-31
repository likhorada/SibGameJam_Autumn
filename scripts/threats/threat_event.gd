class_name ThreatEvent
extends Node
## Adapter contract. The manager owns phases; adapters own world/audio cleanup.
## No enemy, warning sound, damage or placeholder encounter is implemented here.

signal resolved(outcome: StringName)


func can_start() -> bool:
	# A bare adapter must never become a selectable, invisible threat.
	return false


func can_schedule() -> bool:
	return can_start()


func warning_started() -> void:
	pass


func active_started() -> void:
	pass


func advance(_delta: float) -> void:
	pass


func resolved_started(_outcome: StringName) -> void:
	pass


func ended(_outcome: StringName) -> void:
	# Must also clean up partially started warnings and interrupted encounters.
	pass
