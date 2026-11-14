class_name WorldgenDensity
extends RefCounted
## Fill leftover generated parcels with mixed service buildings.
## Does not touch authored seaside town. Doors stay reachable; props stay decorative.

static func fill(data: Dictionary) -> void:
	if data.is_empty() or data.get("seaside_town", false):
		return
	if not data.has("parcels") or not data.has("entities"):
		return
	var reserved: Array[Rect2] = ExplorationLayout._reserved(data)
	if data.has("open_streets"):
		reserved.append(OpenStreetsV1.boarding_paving(data.bus).grow(24.0))
	for point: Array in data.get("enemy_points", []):
		reserved.append(Rect2(WorldLayout.point(point) - Vector2.ONE * 32.0, Vector2.ONE * 64.0))
	for parcel: Dictionary in data.parcels:
		_fill_parcel(data, parcel, reserved)


static func _fill_parcel(data: Dictionary, parcel: Dictionary, reserved: Array[Rect2]) -> void:
	var box: Rect2 = WorldLayout.rect(parcel.rect)
	if box.size.x < 280.0 or box.size.y < 280.0:
		return
	var existing: int = int(parcel.get("buildings", []).size())
	var topology: String = String(data.get("topology", "residential"))
	var industrial: bool = topology == "industrial" or data.has("warehouse_district") or data.has("loading_yard")
	var pool: Array[String] = _pool(topology, industrial)
	# Keep a small budget even on already-occupied plots, so a large leftover lawn can still take a couple of fillers.
	var budget: int = clampi(int(box.get_area() / 500000.0), 1, 2)
	if existing >= 8:
		budget = mini(budget, 1)
	var added: int = 0
	var last: String = ""
	var index: int = parcel.get("buildings", []).size()
	var south: float = box.end.y - 72.0
	var north_limit: float = box.position.y + 150.0
	var foot: float = south
	while foot > north_limit and added < budget:
		var cursor: float = box.position.x + 40.0
		var row_placed: bool = false
		var guard: int = 0
		while cursor + 200.0 < box.end.x - 24.0 and added < budget and guard < 24:
			guard += 1
			var placed: bool = false
			for offset: int in range(pool.size()):
				var typ: String = pool[(index + offset) % pool.size()]
				if typ == last and pool.size() > 1:
					continue
				var width: float = float(WorldgenScale.WIDTH[typ])
				if cursor + width > box.end.x - 32.0:
					continue
				var variant: int = _variant(typ, data.seed, parcel.id, added)
				if not _fits(data, parcel, typ, variant, cursor, foot, reserved):
					continue
				if not WorldgenGeometry._add_building(typ, variant, cursor, foot, parcel, data.entities, data.roads, data.bus):
					continue
				var entity: Dictionary = data.entities[-1]
				entity.service_only = true
				WarehouseDistrict._walk(parcel, Vector2(cursor + 8.0, foot + 24.0),
					Vector2(cursor + width - 8.0, foot + 24.0), 40.0)
				reserved.append(WorldgenScale.visible_rect(entity).grow(12.0))
				reserved.append(Rect2(WorldLayout.point(entity.door) - Vector2(28, 28), Vector2(56, 56)))
				cursor += width + 48.0
				last = typ
				added += 1
				index += 1
				placed = true
				row_placed = true
				break
			if not placed:
				cursor += 80.0
		# Short buildings can take a tighter next row; tall roofs need more air.
		foot -= 260.0 if row_placed else 220.0


static func _pool(topology: String, industrial: bool) -> Array[String]:
	if industrial:
		return ["garage", "warehouse", "convenience_store", "eatery", "garage", "row_house"]
	if topology == "commercial":
		return ["convenience_store", "eatery", "garage", "row_house", "detached_home", "convenience_store"]
	return ["detached_home", "row_house", "garage", "convenience_store", "eatery", "detached_home"]


static func _variant(typ: String, seed: String, parcel_id: String, added: int) -> int:
	var random: RandomNumberGenerator = RogueLayout.rng("gen-density:%s:%s:%d" % [seed, parcel_id, added])
	if typ == "detached_home":
		return 3 if random.randi_range(0, 2) == 0 else random.randi_range(0, 2)
	return random.randi_range(0, 2)


static func _fits(data: Dictionary, parcel: Dictionary, typ: String, variant: int, x: float, foot: float,
		reserved: Array[Rect2]) -> bool:
	var width: float = float(WorldgenScale.WIDTH[typ])
	var depth: float = float(WorldgenScale.DEPTH[typ])
	var block: Rect2 = Rect2(x, foot - depth, width, depth)
	var visible: Rect2 = Rect2(x, foot - WorldgenScale.visible_height(typ, variant), width,
		WorldgenScale.visible_height(typ, variant))
	var door: Vector2 = Vector2(x + width * 0.5, foot + 48.0)
	var apron: Rect2 = Rect2(door - Vector2(28, 28), Vector2(56, 56))
	var box: Rect2 = WorldLayout.rect(parcel.rect)
	if not box.grow(-28.0).encloses(block):
		return false
	if visible.position.y < box.position.y + 12.0:
		return false
	for wall: Array in data.get("barriers", []):
		if WorldLayout.rect(wall).grow(16.0).intersects(block):
			return false
	for zone: Rect2 in reserved:
		if block.grow(24.0).intersects(zone) or apron.grow(16.0).intersects(zone):
			return false
	for walk: Array in parcel.get("walks", []):
		# Keep existing lanes open; a new front apron may sit on leftover grass.
		var lane: Rect2 = WorldLayout.rect(walk)
		if lane.size.y >= 80.0 and block.grow(8.0).intersects(lane):
			return false
	for court: Dictionary in parcel.get("courtyards", []):
		if court.kind in ["loading", "parking"] and WorldLayout.rect(court.rect).intersects(block.grow(8.0)):
			return false
		if court.has("entrance") and apron.grow(12.0).has_point(WorldLayout.point(court.entrance)):
			return false
	if parcel.has("entrance") and apron.grow(16.0).has_point(WorldLayout.point(parcel.entrance)):
		return false
	for entity: Dictionary in data.entities:
		if visible.grow(20.0).intersects(WorldgenScale.visible_rect(entity).grow(12.0)):
			return false
		if apron.grow(28.0).has_point(WorldLayout.point(entity.door)):
			return false
	return true
