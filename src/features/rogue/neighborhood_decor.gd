class_name NeighborhoodDecor
extends RefCounted
## Small traversable details derive from saved geometry, never consume gameplay RNG.


static func placements(layout: StreetLayout) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var random: RandomNumberGenerator = RogueLayout.rng("street-detail-r1:" + String(layout.id))
	var horizontal: Array[Rect2] = []
	for road: Rect2 in layout.roads:
		if road.size.x > road.size.y and road.size.x > layout.world_bounds.size.x * 0.5:
			horizontal.append(road)
	horizontal.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.y > b.position.y)
	var count: int = mini(horizontal.size(), 2 if layout.world_data["size"] != "large" else 3)
	for i: int in range(count):
		var road: Rect2 = horizontal[i]
		for fraction: float in [0.22, 0.77]:
			var point: Vector2 = Vector2(road.position.x + road.size.x * fraction + random.randi_range(-24, 24), road.position.y - 18)
			if _clear(layout, point):
				result.append({"kind":"lamp", "position":point, "variant":random.randi_range(0, 3)})
	var remaining: int = maxi(1, layout.world_data.entities.size() / 4)
	for entity: Dictionary in layout.world_data.entities:
		if remaining == 0:
			break
		if entity.archetype not in ["convenience_store", "eatery", "detached_home", "row_house"] or random.randf() > 0.38:
			continue
		var side: float = -1 if random.randi_range(0, 1) == 0 else 1
		var point: Vector2 = WorldLayout.point(entity.door) + Vector2(side * 120, -16)
		if _clear(layout, point):
			result.append({"kind":"planter", "position":point, "variant":random.randi_range(0, 3)})
			remaining -= 1
	return result


static func _clear(layout: StreetLayout, point: Vector2) -> bool:
	if not layout.world_bounds.grow(-28).has_point(point) or layout.bus_block.grow(72).has_point(point):
		return false
	if WorldLayout.rect(layout.world_data.bus.sweep).grow(12).has_point(point):
		return false
	for block: Rect2 in layout.blockers():
		if block.grow(22).has_point(point):
			return false
	for entity: Dictionary in layout.world_data.entities:
		if point.distance_to(WorldLayout.point(entity.door)) < 96:
			return false
	for gate: Array in layout.world_data.gates:
		if point.distance_to(WorldLayout.point(gate)) < 88:
			return false
	return true
