class_name WorldgenDensity
extends RefCounted
## Fill leftover generated parcels with mixed service buildings.
## Does not touch authored seaside town. Doors stay reachable; props stay decorative.

static func fill(data: Dictionary) -> void:
	if data.is_empty() or data.get("seaside_town", false):
		return
	if not data.has("parcels") or not data.has("entities"):
		return
	# Seeded warehouse and commercial landmark plots already have certified
	# approaches; leftover lawns are filled later by ParcelScenery.
	if data.has("warehouse_district") or (data.has("themed_district") and data.get("topology") == "commercial"):
		return
	var reserved: Array[Rect2] = ExplorationLayout._reserved(data)
	if data.has("open_streets"):
		reserved.append(OpenStreetsV1.boarding_paving(data.bus).grow(24.0))
	for point: Array in data.get("enemy_points", []):
		reserved.append(Rect2(WorldLayout.point(point) - Vector2.ONE * 32.0, Vector2.ONE * 64.0))
	# Existing entities do not move during this fill. Project their
	# collision silhouettes once, and append each new entity immediately.
	var silhouettes: Array[Rect2] = []
	var doors: Array[Vector2] = []
	var fences: Array[Rect2] = []
	var door_fences: Array[Rect2] = []
	for wall: Array in data.get("barriers", []):
		var fence: Rect2 = WorldLayout.rect(wall)
		fences.append(fence.grow(16.0))
		door_fences.append(fence.grow(20.0))
	for entity: Dictionary in data.entities:
		silhouettes.append(WorldgenScale.visible_rect(entity).grow(8.0))
		doors.append(WorldLayout.point(entity.door))
	for parcel: Dictionary in data.parcels:
		_fill_parcel(data, parcel, reserved, silhouettes, doors, fences, door_fences)


static func _fill_parcel(data: Dictionary, parcel: Dictionary, reserved: Array[Rect2],
		silhouettes: Array[Rect2], doors: Array[Vector2], fences: Array[Rect2], door_fences: Array[Rect2]) -> void:
	var box: Rect2 = WorldLayout.rect(parcel.rect)
	if box.size.x < 220.0 or box.size.y < 220.0:
		return
	# _fits accepts only a block inset by 24 and a door inset by 16.
	# Its largest door envelope has radius 52, extending at most 36 beyond
	# this parcel. Keep a conservative 64-unit broad phase, then run every
	# original narrow-phase formula in its original order below.
	var vicinity: Rect2 = box.grow(64.0)
	var local_reserved: Array[Rect2] = []
	var local_silhouettes: Array[Rect2] = []
	var local_doors: Array[Vector2] = []
	var local_fences: Array[Rect2] = []
	var local_door_fences: Array[Rect2] = []
	for zone: Rect2 in reserved:
		if _could_overlap(vicinity, zone):
			local_reserved.append(zone)
	for pair: int in range(silhouettes.size()):
		if _could_overlap(vicinity, silhouettes[pair]) or vicinity.intersects(Rect2(doors[pair], Vector2.ZERO), true):
			local_silhouettes.append(silhouettes[pair])
			local_doors.append(doors[pair])
	for pair: int in range(fences.size()):
		if _could_overlap(vicinity, fences[pair]) or _could_overlap(vicinity, door_fences[pair]):
			local_fences.append(fences[pair])
			local_door_fences.append(door_fences[pair])
	var existing: int = int(parcel.get("buildings", []).size())
	var topology: String = String(data.get("topology", "residential"))
	var industrial: bool = topology == "industrial" or data.has("warehouse_district") or data.has("loading_yard")
	var pool: Array[String] = _pool(topology, industrial)
	# Spend leftover lawns on several fillers so a wide grass belt does not remain between houses.
	var budget: int = clampi(int(box.get_area() / 220000.0), 1, 5)
	if existing >= 8:
		budget = mini(budget, 2)
	var added: int = 0
	var last: String = ""
	var index: int = parcel.get("buildings", []).size()
	var random: RandomNumberGenerator = RogueLayout.rng("gen-density-row:" + String(data.get("seed", "0")) + ":" + parcel.id)
	var variants: Dictionary = {}
	var south: float = box.end.y - 56.0
	var north_limit: float = box.position.y + 120.0
	var foot: float = south
	while foot > north_limit and added < budget:
		var cursor: float = box.position.x + 24.0
		var row_placed: bool = false
		var guard: int = 0
		while cursor + 160.0 < box.end.x - 16.0 and added < budget and guard < 36:
			guard += 1
			var placed: bool = false
			for offset: int in range(pool.size()):
				var typ: String = pool[(index + offset) % pool.size()]
				if typ == last and pool.size() > 1:
					continue
				var width: float = float(WorldgenScale.WIDTH[typ])
				if cursor + width > box.end.x - 20.0:
					continue
				if not variants.has(typ):
					variants[typ] = _variant(typ, data.seed, parcel.id, added)
				var variant: int = variants[typ]
				if not _fits(parcel, typ, variant, cursor, foot, local_reserved, local_silhouettes, local_doors, local_fences, local_door_fences):
					continue
				if not WorldgenGeometry._add_building(typ, variant, cursor, foot, parcel, data.entities, data.roads, data.bus):
					continue
				var entity: Dictionary = data.entities[-1]
				entity.service_only = true
				var silhouette: Rect2 = WorldgenScale.visible_rect(entity).grow(8.0)
				var doorway: Vector2 = WorldLayout.point(entity.door)
				silhouettes.append(silhouette)
				doors.append(doorway)
				local_silhouettes.append(silhouette)
				local_doors.append(doorway)
				WarehouseDistrict._walk(parcel, Vector2(cursor + 8.0, foot + 24.0),
					Vector2(cursor + width - 8.0, foot + 24.0), 56.0)
				var apron: Rect2 = Rect2(doorway - Vector2(24, 24), Vector2(48, 48))
				reserved.append(silhouette)
				reserved.append(apron)
				local_reserved.append(silhouette)
				local_reserved.append(apron)
				cursor += width + 20.0 + 8.0 * float(random.randi_range(0, 1))
				last = typ
				added += 1
				variants.clear() # _variant's added ordinal is part of its seed.
				index += 1
				placed = true
				row_placed = true
				break
			if not placed:
				cursor += 48.0
		# Step by a short-shop roof when the row is empty, otherwise leave a narrow service strip.
		foot -= 200.0 if row_placed else 128.0


static func _could_overlap(area: Rect2, obstacle: Rect2) -> bool:
	# Keep boundaries and degenerate rectangles conservatively. Negative extents
	# are not generated, but retaining them leaves their old narrow phase intact.
	return obstacle.size.x < 0.0 or obstacle.size.y < 0.0 or area.intersects(obstacle, true)


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


static func _fits(parcel: Dictionary, typ: String, variant: int, x: float, foot: float,
		reserved: Array[Rect2], silhouettes: Array[Rect2], doors: Array[Vector2],
		fences: Array[Rect2], door_fences: Array[Rect2]) -> bool:
	var width: float = float(WorldgenScale.WIDTH[typ])
	var depth: float = float(WorldgenScale.DEPTH[typ])
	var block: Rect2 = Rect2(x, foot - depth, width, depth)
	var visible: Rect2 = Rect2(x, foot - WorldgenScale.visible_height(typ, variant), width,
		WorldgenScale.visible_height(typ, variant))
	var door_x: float = x + width * 0.5 + (WorldgenScale.door_x(typ, variant) - 256.0) * width / 448.0
	var door: Vector2 = Vector2(door_x, foot + 48.0)
	var apron: Rect2 = Rect2(door - Vector2(28, 28), Vector2(56, 56))
	var box: Rect2 = WorldLayout.rect(parcel.rect)
	if not box.grow(-24.0).encloses(block):
		return false
	if visible.position.y < box.position.y + 12.0:
		return false
	if not box.grow(-16.0).has_point(door):
		return false
	for index: int in range(fences.size()):
		if fences[index].intersects(block) or door_fences[index].has_point(door):
			return false
	var reserved_block: Rect2 = block.grow(16.0)
	var reserved_apron: Rect2 = apron.grow(14.0)
	for zone: Rect2 in reserved:
		if reserved_block.intersects(zone) or reserved_apron.intersects(zone):
			return false
	for walk: Array in parcel.get("walks", []):
		# Keep existing lanes open; a new front apron may sit on leftover grass.
		var lane: Rect2 = WorldLayout.rect(walk)
		if lane.size.y >= 80.0 and block.grow(6.0).intersects(lane):
			return false
	for court: Dictionary in parcel.get("courtyards", []):
		if court.kind in ["loading", "parking"] and WorldLayout.rect(court.rect).intersects(block.grow(8.0)):
			return false
		if court.has("entrance") and apron.grow(10.0).has_point(WorldLayout.point(court.entrance)):
			return false
	if parcel.has("entrance") and apron.grow(12.0).has_point(WorldLayout.point(parcel.entrance)):
		return false
	var silhouette: Rect2 = visible.grow(8.0)
	var entry: Rect2 = apron.grow(24.0)
	for index: int in range(silhouettes.size()):
		if silhouette.intersects(silhouettes[index]):
			return false
		if entry.has_point(doors[index]):
			return false
	return true
