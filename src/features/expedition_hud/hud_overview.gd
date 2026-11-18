class_name ExpeditionHudOverview
extends Control
## Small read-only map: world bounds, building footprints, living members and bus.
var world: Expedition

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(120, 90)

func _draw() -> void:
	if world == null: return
	var bounds: Rect2 = world.layout.world_bounds
	if bounds.size.x <= 0 or bounds.size.y <= 0: return
	var factor: float = minf((size.x - 8) / bounds.size.x, (size.y - 8) / bounds.size.y)
	var origin: Vector2 = (size - bounds.size * factor) * 0.5
	draw_rect(Rect2(origin, bounds.size * factor), CampStyle.EDGE, false, 1)
	if HarborWarehouse.is_layout(world.layout):
		for surface: String in ["harbor_water", "harbor_wood"]:
			for row: Array in world.layout.world_data.grounds[surface]:
				var area: Rect2 = WorldLayout.rect(row)
				draw_rect(Rect2(origin + (area.position - bounds.position) * factor, area.size * factor), Color("278ca3") if surface == "harbor_water" else CampStyle.SURFACE)
	for entity: Dictionary in world.layout.world_data.get("entities", []):
		var footprint: Rect2 = WorldLayout.rect(entity.rect)
		draw_rect(Rect2(origin + (footprint.position - bounds.position) * factor, footprint.size * factor), CampStyle.SURFACE)
	for actor: FieldActor in world.survivors:
		if actor.health > 0:
			draw_rect(Rect2((origin + (actor.position - bounds.position) * factor).round() - Vector2(2, 2), Vector2(5, 5)), ExpeditionHudTheme.SAGE)
	var bus_point: Vector2 = (origin + (IsoSpace.map_of(world._bus_sprite) - bounds.position) * factor).round()
	draw_rect(Rect2(bus_point - Vector2(4, 3), Vector2(9, 6)), CampStyle.TEXT)
	draw_rect(Rect2(bus_point - Vector2(2, 2), Vector2(4, 2)), CampStyle.INK)
