class_name RoomCameraPopup
extends DesktopAppWindow
## Fixed, silent view of the apartment. The window itself can move, not aim.
signal dismissed(reason: StringName)

var feed_texture: Texture2D
var close_button: Button
var feed: TextureRect
var _dismissed: bool = false


func _ready() -> void:
	window_title = "ROOM_CAMERA_TITLE"
	minimum_window_size = Vector2(360, 260)
	super._ready()
	for child: Node in title_bar.get_child(0).get_children():
		if child is Button:
			if child.text == "×":
				close_button = child
			else:
				child.hide()
	resize_grip.hide()
	content.add_theme_constant_override("margin_left", 7)
	content.add_theme_constant_override("margin_right", 7)
	content.add_theme_constant_override("margin_top", 7)
	content.add_theme_constant_override("margin_bottom", 7)
	feed = TextureRect.new()
	feed.name = "SilentMonochromeFeed"
	feed.texture = feed_texture
	feed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	feed.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	feed.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	feed.mouse_filter = Control.MOUSE_FILTER_STOP
	feed.focus_mode = Control.FOCUS_NONE
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/monochrome.gdshader")
	feed.material = material
	content.add_child(feed)
	size = Vector2(580, 390)
	open_window()
	set_active(true)


func close_window() -> void:
	dismiss(&"closed")


func dismiss(reason: StringName) -> void:
	if _dismissed:
		return
	_dismissed = true
	super.close_window()
	dismissed.emit(reason)


func _edges_at(_point: Vector2) -> Vector2i:
	return Vector2i.ZERO
