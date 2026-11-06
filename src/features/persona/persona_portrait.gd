class_name PersonaPortrait
extends Control
## Head-and-shoulder presentation of the existing authored identity texture.
## Crop and badge are visual only; this view never infers a member or a recipe.

const BADGES: Dictionary = {
	"稳控": preload("res://assets/persona/trait_aim.svg"),
	"熟练": preload("res://assets/persona/trait_supply.svg"),
	"轻捷": preload("res://assets/persona/trait_move.svg"),
}

var _texture: Texture2D
var _alive: bool = true
var _badge: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func present(picture: Texture2D, alive: bool = true, primary: String = "") -> void:
	_texture = picture
	_alive = alive
	_badge = null
	for prefix: String in BADGES:
		if primary.begins_with(prefix):
			_badge = BADGES[prefix]
			break
	queue_redraw()


func _draw() -> void:
	var frame: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(frame, Color("17333f"))
	if _texture != null and size.x > 0.0 and size.y > 0.0:
		var source_size: Vector2 = _texture.get_size()
		var source: Rect2 = Rect2(source_size * Vector2(0.21, 0.05), source_size * Vector2(0.58, 0.60))
		var tint: Color = Color.WHITE if _alive else Color(0.55, 0.60, 0.63, 1.0)
		draw_texture_rect_region(_texture, frame.grow(-1.0), source, tint)
	else:
		draw_circle(size * Vector2(0.5, 0.36), minf(size.x, size.y) * 0.14, Color("9aafb3"))
		draw_arc(size * Vector2(0.5, 0.86), minf(size.x, size.y) * 0.29, PI, TAU, 16, Color("9aafb3"), 2.0, true)
	if _badge != null:
		var edge: float = clampf(minf(size.x, size.y) * 0.37, 14.0, 26.0)
		draw_texture_rect(_badge, Rect2(size - Vector2.ONE * edge, Vector2.ONE * edge), false)
