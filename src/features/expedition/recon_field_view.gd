class_name ReconFieldView
extends Node2D
## One world-space canvas item for the fog, coarse region and known pins.

const FOG: Color = Color(0.025, 0.08, 0.12, 0.48)
const GOLD: Color = Color("ffcf86")
const TEAL: Color = Color("8be4d2")
const SHADOW: Color = Color("12262e")

var world: Expedition


func _draw() -> void:
	var knowledge: ReconKnowledge = world.recon_knowledge
	for y: int in range(knowledge.rows):
		var start: int = -1
		for x: int in range(knowledge.columns + 1):
			var unknown: bool = x < knowledge.columns and not knowledge.is_cell_explored(y * knowledge.columns + x)
			if unknown and start < 0:
				start = x
			elif not unknown and start >= 0:
				var first: Rect2 = knowledge.cell_rect(y * knowledge.columns + start)
				var last: Rect2 = knowledge.cell_rect(y * knowledge.columns + x - 1)
				draw_rect(first.merge(last), FOG)
				start = -1

	var marker: Dictionary = world.supply.generated.recon
	var primary: Expedition.SearchSite = world.search_site(StringName(marker.primary_id))
	if world.site_discovered(primary):
		_pin(primary.door, "主装备点", GOLD)
	else:
		var region: Rect2 = world.recon_region()
		draw_rect(region, Color(1.0, 0.69, 0.35, 0.10))
		draw_rect(region.grow(-2.0), Color(1.0, 0.77, 0.49, 0.72), false, 3.0)
		_text(region.get_center() - Vector2(0, 14), "装备区域 · 位置待发现", GOLD)

	var optional: Expedition.SearchSite = world.search_site(StringName(marker.optional_id))
	if world.site_discovered(optional):
		_pin(optional.door, "可搜建筑", TEAL)
	_pin(world.recon_site.door, "侦察完成" if world.recon_site.searched else "侦察点", TEAL, true)


func _pin(point: Vector2, title: String, colour: Color, station: bool = false) -> void:
	var center: Vector2 = point - Vector2(0, 30 if station else 18)
	var radius: float = 11.0 if station else 6.0
	draw_line(point, center, SHADOW, 4.0, true)
	draw_circle(center, radius + 3.0, SHADOW, true, -1.0, true)
	draw_circle(center, radius, colour, true, -1.0, true)
	if station:
		if world.recon_site.searched:
			draw_polyline(PackedVector2Array([center + Vector2(-5, 0), center + Vector2(-1, 4), center + Vector2(6, -4)]), SHADOW, 2.0, true)
		else:
			draw_line(center - Vector2(5, 0), center + Vector2(5, 0), SHADOW, 2.0, true)
			draw_line(center - Vector2(0, 5), center + Vector2(0, 5), SHADOW, 2.0, true)
		_text(center - Vector2(0, 18), title, colour)
	else:
		_text(center - Vector2(0, 12), title, colour)


func _text(point: Vector2, title: String, colour: Color) -> void:
	var font: Font = world.ui_theme.default_font if world.ui_theme != null and world.ui_theme.default_font != null else ThemeDB.fallback_font
	var width: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var origin: Vector2 = point - Vector2(width * 0.5, 0)
	draw_rect(Rect2(origin + Vector2(-6, -18), Vector2(width + 12, 25)), Color(0.045, 0.10, 0.14, 0.90))
	draw_string(font, origin, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, colour)
