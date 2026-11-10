class_name WorldgenFurniture
extends Node2D
## Static frozen scenery, no input, timers, search sites or gameplay state.
var detail: Dictionary

func _draw() -> void:
	if detail.has("slot"):
		var sprite: Texture2D = WarehouseDressingArt.texture(detail.slot)
		if sprite != null:
			var width: float = float(detail.get("width", sprite.get_width()))
			var height: float = width * sprite.get_height() / sprite.get_width()
			draw_texture_rect(sprite, Rect2(-width * 0.5, -height, width, height), false)
		return
	var texture: Texture2D=WorldgenArt.texture(detail.kind)
	var width: float=float(detail.width)
	if detail.kind == "courtyard_edge":
		# Source padding and the open interior never become a solid rectangle.
		var ratio: float = width / StreetModuleArt.COURTYARD_REFERENCE_WIDTH
		var origin: Vector2 = -StreetModuleArt.COURTYARD_ANCHOR * ratio
		draw_texture_rect(texture, Rect2(origin, StreetModuleArt.COURTYARD_NATIVE * ratio), false)
		return
	var height: float=width*texture.get_height()/texture.get_width()
	draw_set_transform(Vector2(5,-2),0,Vector2(1,0.2))
	draw_circle(Vector2.ZERO,width*0.48,Color(0.07,0.12,0.14,0.22))
	draw_set_transform(Vector2.ZERO)
	draw_texture_rect(texture,Rect2(-width/2,-height,width,height),false)
