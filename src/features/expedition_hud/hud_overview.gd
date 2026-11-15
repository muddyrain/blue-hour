class_name ExpeditionHudOverview
extends Control
## Small read-only map: world bounds, building footprints, living members and bus.
var world: Expedition

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(140, 140)

func _draw() -> void:
	if world == null: return
	var bounds: Rect2 = world.layout.world_bounds
	if bounds.size.x <= 0 or bounds.size.y <= 0: return
	var factor: float = minf((size.x - 16) / bounds.size.x, (size.y - 16) / bounds.size.y)
	var origin: Vector2 = (size - bounds.size * factor) * 0.5
	draw_rect(Rect2(origin, bounds.size * factor), Color("b8ac96", 0.6), false, 1)
	if HarborWarehouse.is_layout(world.layout):
		for surface: String in ["harbor_water", "harbor_wood"]:
			for row: Array in world.layout.world_data.grounds[surface]:
				var area: Rect2 = WorldLayout.rect(row)
				draw_rect(Rect2(origin + (area.position - bounds.position) * factor, area.size * factor), Color("527f89") if surface == "harbor_water" else Color("b09b76"))
	for entity: Dictionary in world.layout.world_data.get("entities", []):
		var footprint: Rect2 = WorldLayout.rect(entity.rect)
		draw_rect(Rect2(origin + (footprint.position - bounds.position) * factor, footprint.size * factor), Color("b8ac96", 0.3))
	for actor: FieldActor in world.survivors:
		if actor.health > 0:
			draw_circle(origin + (actor.position - bounds.position) * factor, 2.5, ExpeditionHudTheme.SAGE)
	draw_circle(origin + (IsoSpace.map_of(world._bus_sprite) - bounds.position) * factor, 4, ExpeditionHudTheme.AMBER)
