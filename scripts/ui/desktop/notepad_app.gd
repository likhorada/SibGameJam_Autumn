class_name NotepadApp
extends VBoxContainer

signal leave_requested

@onready var editor: TextEdit = $Editor
@onready var status: Label = $Status


func _ready() -> void:
	editor.text_changed.connect(_update_status)
	editor.get_menu().window_input.connect(_context_input)


func focus_editor() -> void:
	editor.grab_focus()


func _update_status() -> void:
	status.text = "Только текущая попытка · %d символов" % editor.text.length()


func _context_input(event: InputEvent) -> void:
	# The embedded TextEdit popup has its own viewport and can consume Esc first.
	if event.is_action_pressed("back") and not event.is_echo():
		editor.get_menu().hide()
		leave_requested.emit()
