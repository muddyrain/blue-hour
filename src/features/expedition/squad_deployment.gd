class_name SquadDeployment
extends RefCounted
## Share departure positions with evidence validators; never mutate map receipts.


static func arrival(index: int, arrivals: Array[Vector2], occupied: Array[Vector2], navigation: FieldNavigation) -> Vector2:
	if index < arrivals.size():
		return arrivals[index]
	var anchor: Vector2 = arrivals[0]
	for ring: int in range(1, 17):
		for x: int in range(-ring, ring + 1):
			for y: int in range(-ring, ring + 1):
				var point: Vector2 = anchor + Vector2(x, y) * 48.0
				if not navigation.is_clear(point) or occupied.any(func(at: Vector2) -> bool: return at.distance_to(point) < 32.0):
					continue
				if not navigation.path_between(anchor, point).is_empty():
					return point
	return Vector2.INF


static func positions(raw: Array, count: int, navigation: FieldNavigation) -> Array[Vector2]:
	var arrivals: Array[Vector2] = []
	for point: Array in raw:
		arrivals.append(WorldLayout.point(point))
	var result: Array[Vector2] = []
	for index: int in range(count):
		var point: Vector2 = arrival(index, arrivals, result, navigation)
		if point == Vector2.INF:
			return []
		result.append(point)
	return result
