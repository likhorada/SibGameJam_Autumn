class_name NightNoteApp
extends RichTextLabel
## A virtual, read-only desktop file, not an OS file or an editable player note.


func _ready() -> void:
	selection_enabled = true
	add_theme_color_override("default_color", Color("232a31"))
	add_theme_stylebox_override("normal", _paper())
	_refresh()


func _paper() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("dddccb")
	style.set_content_margin_all(12.0)
	return style


func _refresh() -> void:
	text = tr("NIGHT_NOTE_TEXT")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()
