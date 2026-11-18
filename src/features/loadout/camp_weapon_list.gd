class_name CampWeaponList
extends ItemList
## Native inventory selection/scrolling with independent two-line presentation.
## ItemList itself only supports one text line; labels share its real row rectangles.
var captions: Array[Dictionary] = []
var _labels: Control

func _ready() -> void:
	for key: String in ["font_color", "font_selected_color", "font_hovered_color", "font_hovered_selected_color"]:
		add_theme_color_override(key, Color.TRANSPARENT)
	_labels = Control.new()
	_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_labels.clip_contents = true
	add_child(_labels)
	_labels.draw.connect(_draw_labels)

func _process(_delta: float) -> void:
	if not is_visible_in_tree(): return
	_labels.size = Vector2(size.x - (get_v_scroll_bar().size.x if get_v_scroll_bar().visible else 0.0), size.y)
	_labels.queue_redraw()

func _draw_labels() -> void:
	var font: Font = CampStyle.BOLD_FONT
	var scroll: float = get_v_scroll_bar().value
	for index: int in range(mini(item_count, captions.size())):
		var bounds: Rect2 = get_item_rect(index)
		bounds.position.y -= scroll
		if bounds.end.y < 0 or bounds.position.y > size.y: continue
		var origin: Vector2 = Vector2(bounds.position.x + fixed_icon_size.x + 20, bounds.position.y + bounds.size.y * 0.5)
		var caption: Dictionary = captions[index]
		_labels.draw_string(font, origin + Vector2(0, -3), caption.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, CampStyle.TEXT)
		_labels.draw_string(font, origin + Vector2(0, 26), caption.state, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, caption.colour)
