class_name LevelPolicy
extends RefCounted
## Local task preferences only. Final geometry/navigation and reward owners remain authoritative.

const HOME_TYPES: Array[String] = ["detached_home", "row_house", "small_apartment"]
const FOOD_PAIR_LIMIT: float = 960.0


static func prepare(parcels: Array, type: String, seed: String) -> void:
	if type not in ["supply", "equipment", "rescue"]:
		return
	var candidates: Array[Dictionary] = []
	for parcel: Dictionary in parcels:
		var box: Rect2 = WorldLayout.rect(parcel.rect)
		if box.size.x >= 736.0 and box.size.y >= 432.0:
			candidates.append(parcel)
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		# A food frontage needs two real shop widths; a rescue court needs room for a house.
		var a_south: bool = bool(a.road_edges[1])
		var b_south: bool = bool(b.road_edges[1])
		if type == "supply" and a_south != b_south:
			return a_south
		var a_key: String = ("BH_LEVEL_V1|parcel|" + seed + "|" + type + "|" + String(a.id)).sha256_text()
		var b_key: String = ("BH_LEVEL_V1|parcel|" + seed + "|" + type + "|" + String(b.id)).sha256_text()
		return a_key < b_key if a_key != b_key else String(a.id) < String(b.id)
	)
	# Garden uses the existing house pool in every surrounding theme; commercial
	# courtyards alone may legitimately contain only shops.
	candidates[0].kind = {"supply":"shopfront", "equipment":"loading", "rescue":"garden"}[type]


static func choose(candidates: Array[Dictionary], routing: Dictionary, type: String, kind: String, index: int, chosen: Array[Dictionary], layout: Dictionary) -> Dictionary:
	if candidates.is_empty():
		return {}
	if type == "supply" and kind == "food":
		if index == 0:
			return _supply_first(candidates, routing, layout)
		if not chosen.is_empty():
			return _supply_neighbor(candidates, chosen[0], routing)
	var target: Dictionary = _gear_target(candidates if kind == "cash" and index == 0 else _gear_entities(layout), routing)
	if type == "equipment" and not target.is_empty():
		if kind == "cash" and index == 0:
			return target
		return _short_branch(candidates, WorldLayout.point(target.door), routing, layout)
	if type == "rescue":
		return _short_branch(candidates, WorldLayout.point(layout.rescue), routing, layout)
	var ranked: Array[Dictionary] = candidates.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_distance: float = float(routing.doors[a.id].length)
		var b_distance: float = float(routing.doors[b.id].length)
		if a_distance != b_distance:
			return a_distance > b_distance if index == 0 else a_distance < b_distance
		return String(a.id) < String(b.id)
	)
	return ranked[0]


static func rescue_point(data: Dictionary) -> Array:
	var bus: Vector2 = WorldLayout.point(data.bus.door)
	var candidates: Array[Dictionary] = []
	var parcels: Dictionary = {}
	for parcel: Dictionary in data.parcels:
		parcels[parcel.id] = parcel
	for entity: Dictionary in data.entities:
		if entity.archetype not in HOME_TYPES:
			continue
		var parcel: Dictionary = parcels.get(entity.parcel, {})
		if parcel.get("kind") in ["courtyard", "garden", "homes"] and parcel.buildings.size() >= 2:
			candidates.append(entity)
	if candidates.is_empty():
		return []
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_distance: float = WorldLayout.point(a.door).distance_squared_to(bus)
		var b_distance: float = WorldLayout.point(b.door).distance_squared_to(bus)
		if a_distance != b_distance:
			return a_distance > b_distance
		return String(a.id) < String(b.id)
	)
	# A real cluster door is already part of the generator's reserved clearance set.
	# The post-dressing certificate must still prove this same point is reachable.
	return candidates[0].door.duplicate()


static func _supply_first(candidates: Array[Dictionary], routing: Dictionary, layout: Dictionary) -> Dictionary:
	if candidates.size() == 1:
		return candidates[0]
	var best: Dictionary = {}
	var best_score: float = INF
	var best_key: String = ""
	var nav: FieldNavigation = routing.nav
	for first: Dictionary in candidates:
		var first_distance: float = float(routing.doors[first.id].length)
		if first_distance <= float(routing.dmax) * 0.35:
			continue
		for second: Dictionary in candidates:
			if first.id == second.id:
				continue
			var first_point: Vector2 = WorldLayout.point(first.door)
			var second_point: Vector2 = WorldLayout.point(second.door)
			if first_point.distance_to(second_point) > FOOD_PAIR_LIMIT:
				continue
			var distance: float = _distance(nav, first_point, second_point)
			if distance > FOOD_PAIR_LIMIT:
				continue
			var score: float = distance + (0.0 if first.parcel == second.parcel else 240.0)
			if absf(first_point.y - second_point.y) > 64.0:
				score += 96.0
			# Middle-distance groups leave a reason to visit the remaining far sites.
			score += absf(first_distance - float(routing.dmax) * 0.58) * 0.15
			var key: String = (String(layout.seed) + "|" + String(first.id) + "|" + String(second.id)).sha256_text()
			if score < best_score or (score == best_score and (best_key.is_empty() or key < best_key)):
				best = first
				best_score = score
				best_key = key
	return best


static func _supply_neighbor(candidates: Array[Dictionary], first: Dictionary, routing: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = INF
	var nav: FieldNavigation = routing.nav
	var point: Vector2 = WorldLayout.point(first.door)
	for candidate: Dictionary in candidates:
		var next: Vector2 = WorldLayout.point(candidate.door)
		if point.distance_to(next) > FOOD_PAIR_LIMIT:
			continue
		var distance: float = _distance(nav, point, next)
		if distance > FOOD_PAIR_LIMIT:
			continue
		var score: float = distance + (0.0 if first.parcel == candidate.parcel else 240.0)
		if absf(point.y - next.y) > 64.0:
			score += 96.0
		if score < best_score or (score == best_score and (best.is_empty() or String(candidate.id) < String(best.id))):
			best = candidate
			best_score = score
	return best


static func _gear_entities(layout: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entity: Dictionary in layout.entities:
		if entity.archetype in TaskActions.GEAR_TYPES:
			result.append(entity)
	return result


static func _gear_target(candidates: Array[Dictionary], routing: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = INF
	for candidate: Dictionary in candidates:
		if candidate.archetype not in TaskActions.GEAR_TYPES:
			continue
		var distance: float = float(routing.doors[candidate.id].length)
		var score: float = absf(distance - float(routing.dmax) * 0.68)
		if distance <= float(routing.dmax) * 0.5:
			score += float(routing.dmax)
		if score < best_score or (score == best_score and (best.is_empty() or String(candidate.id) < String(best.id))):
			best = candidate
			best_score = score
	return best


static func _short_branch(candidates: Array[Dictionary], target: Vector2, routing: Dictionary, layout: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = INF
	var nav: FieldNavigation = routing.nav
	var direct: float = _distance(nav, WorldLayout.point(layout.bus.door), target)
	for candidate: Dictionary in candidates:
		var outgoing: float = float(routing.doors[candidate.id].length)
		var onward: float = _distance(nav, WorldLayout.point(candidate.door), target)
		if not is_finite(onward):
			continue
		var detour: float = maxf(0.0, outgoing + onward - direct)
		var score: float = detour + outgoing * 0.1
		if score < best_score or (score == best_score and (best.is_empty() or String(candidate.id) < String(best.id))):
			best = candidate
			best_score = score
	return best


static func _distance(nav: FieldNavigation, from: Vector2, to: Vector2) -> float:
	if not nav.is_clear(from) or not nav.is_clear(to):
		return INF
	var path: PackedVector2Array = nav.path_between(from, to)
	if path.is_empty() or path[-1].distance_to(to) > 14.0:
		return INF
	var result: float = 0.0
	for index: int in range(1, path.size()):
		result += path[index - 1].distance_to(path[index])
	return result
