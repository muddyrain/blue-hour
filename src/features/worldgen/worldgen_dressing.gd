class_name WorldgenDressing
extends RefCounted
## Solid scenery is frozen before interactive props and the final navigation certificate.
## It never supplies loot or a search identity. Rendering cannot invent blockers.

class ParcelFrontage extends RefCounted:
	var doors: Array[Vector2] = []
	var buildings: Array[Rect2] = []

	func append(entity: Dictionary) -> void:
		doors.append(WorldLayout.point(entity.door))
		buildings.append(WorldgenScale.visible_rect(entity).grow(96.0))


static func freeze(data: Dictionary) -> void:
	var occupied: Array[Rect2]=[]
	for entity: Dictionary in data.entities: occupied.append(WorldLayout.rect(entity.rect).grow(22))
	for wall: Array in data.barriers: occupied.append(WorldLayout.rect(wall).grow(20))
	var reserved: Array[Rect2]=ExplorationLayout._reserved(data)
	var edge_placed: bool=false
	for parcel: Dictionary in data.parcels:
		parcel.dressing=[]
	var ordered: Array=data.parcels.duplicate()
	var bus_point: Vector2=WorldLayout.point(data.bus.door)
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return WorldLayout.point(a.entrance).distance_squared_to(bus_point)<WorldLayout.point(b.entrance).distance_squared_to(bus_point))
	for parcel: Dictionary in ordered:
		if data.get("art_revision")==3 and not edge_placed:
			edge_placed=_courtyard_edge(data,parcel,occupied,reserved)
		var count: int=0
		for court: Dictionary in parcel.courtyards:
			if count>=4:break
			# Parking courts need their usable ground for stalls, not solid scrap scenery.
			if court.kind == "parking":continue
			var area: Rect2=WorldLayout.rect(court.rect)
			var kind: String="cargo" if court.kind=="loading" else "hedge"
			var width: float=112 if kind=="cargo" else 144
			if area.size.x<width+24 or area.size.y<84:continue
			# Place at a court boundary, leaving its entrance and orthogonal footways clear.
			var candidates: Array[Vector2] = [Vector2(area.position.x+width/2+12,area.position.y+52),Vector2(area.end.x-width/2-12,area.end.y-14),Vector2(area.get_center().x,area.position.y+52)]
			if data.has("warehouse_district") and kind == "cargo":
				candidates.append(Vector2(area.position.x + width * 0.5 + 72.0, area.get_center().y + 14.0))
			for point: Vector2 in candidates:
				var block: Rect2=Rect2(point-Vector2(width*0.44,24),Vector2(width*0.88,24))
				var route_clear: bool = not (OpenStreetsV1.intersects_sweep(data.bus, block, 24) if data.has("open_streets")
					else WorldLayout.rect(data.bus.sweep).grow(24).intersects(block))
				var clear: bool = area.encloses(block) and route_clear
				for other: Rect2 in occupied+reserved:clear=clear and not block.grow(20).intersects(other)
				for road: Array in data.roads:clear=clear and not block.grow(24).intersects(WorldLayout.rect(road))
				for walk: Array in parcel.walks:clear=clear and not block.grow(12).intersects(WorldLayout.rect(walk))
				if not clear:continue
				parcel.dressing.append({"kind":kind,"point":[point.x,point.y],"width":width,"collision":[block.position.x,block.position.y,block.size.x,block.size.y]})
				occupied.append(block.grow(20));count+=1
				break

static func _courtyard_edge(data: Dictionary, parcel: Dictionary, occupied: Array[Rect2], reserved: Array[Rect2]) -> bool:
	for court: Dictionary in parcel.courtyards:
		if court.kind not in ["garden","court"]:
			continue
		var area: Rect2=WorldLayout.rect(court.rect)
		var width: float=180.0
		if area.size.x<width+64 or area.size.y<136:
			continue
		var point: Vector2=Vector2(area.position.x+48,area.end.y-12)
		var collisions: Array=StreetModuleArt.courtyard_collisions(point,width)
		var clear: bool=true
		for value: Array in collisions:
			var block: Rect2=WorldLayout.rect(value)
			clear=clear and area.encloses(block)
			for other: Rect2 in occupied+reserved:
				clear=clear and not block.grow(22).intersects(other)
			for walk: Array in parcel.walks:
				clear=clear and not block.grow(16).intersects(WorldLayout.rect(walk))
			clear=clear and not block.grow(48).has_point(WorldLayout.point(court.entrance))
		if not clear:
			continue
		parcel.dressing.append({"kind":"courtyard_edge","point":[point.x,point.y],"width":width,"collisions":collisions})
		for value: Array in collisions:
			occupied.append(WorldLayout.rect(value).grow(22))
		return true
	return false


static func enrich(data: Dictionary) -> void:
	# A single decorative pass after annexes, so small props cannot preempt parking or site fitting.
	if data.is_empty() or data.get("seaside_town", false) or not data.has("parcels"):
		return
	var occupied: Array[Rect2] = []
	for entity: Dictionary in data.entities:
		occupied.append(WorldgenScale.visible_rect(entity).merge(WorldLayout.rect(entity.rect)).grow(18))
	for wall: Array in data.get("barriers", []):
		occupied.append(WorldLayout.rect(wall).grow(16))
	for parcel: Dictionary in data.parcels:
		for detail: Dictionary in parcel.get("dressing", []):
			if detail.has("surface"):
				occupied.append(WorldLayout.rect(detail.surface))
			elif detail.has("point"):
				var point: Vector2 = WorldLayout.point(detail.point)
				occupied.append(_prop_mark(String(detail.get("kind", "")), point))
			for rect: Array in detail.get("collisions", [detail.collision] if detail.has("collision") else []):
				occupied.append(WorldLayout.rect(rect).grow(8))
	var reserved: Array[Rect2] = ExplorationLayout._reserved(data)
	# Keep everyday furniture outside the working loading court, including its cargo apron.
	if data.has("loading_yard"):
		reserved.append(WorldLayout.rect(data.loading_yard.bounds))
	for parcel: Dictionary in data.parcels:
		for court: Dictionary in parcel.courtyards:
			if court.kind == "loading":
				reserved.append(WorldLayout.rect(court.rect))
	_scatter(data, occupied, reserved)


static func _scatter(data: Dictionary, occupied: Array[Rect2], reserved: Array[Rect2]) -> void:
	# Only dressing changes during this pass. Keep each parcel's entity order while
	# projecting its immutable doors/silhouettes once, not for every candidate point.
	var frontages: Dictionary = _frontage_index(data)
	var random: RandomNumberGenerator = RogueLayout.rng("town-props:" + String(data.get("seed", "0")))
	var ordered: Array = data.parcels.duplicate()
	var bus: Vector2 = WorldLayout.point(data.bus.door)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return WorldLayout.point(a.entrance).distance_squared_to(bus) < WorldLayout.point(b.entrance).distance_squared_to(bus))
	# Reserve the large sets across the whole map before any small furniture.
	var stalls: int = {"small":6, "medium":12, "large":24}[data["size"]]
	for parcel: Dictionary in ordered:
		if stalls > 0:
			stalls -= _street_sets(data, parcel, occupied, reserved, random, frontages[parcel.id])
	var shelters: int = {"small":2, "medium":4, "large":10}[data["size"]]
	for parcel: Dictionary in ordered:
		if shelters <= 0:
			break
		for center: Vector2 in _frontage_anchors(data, parcel, Vector2(140, 106), 192.0, frontages[parcel.id]):
			var point: Vector2 = center + Vector2(0, 33)
			if not _near_frontage(data, parcel, point, frontages[parcel.id]):
				continue
			if _place_prop(data, parcel, occupied, reserved, random, "bike_shelter", point, 28.0):
				shelters -= 1
				break
	for parcel: Dictionary in ordered:
		_edge_furniture(data, parcel, occupied, reserved, random, frontages[parcel.id])
		_fill_open(data, parcel, occupied, reserved, random, frontages[parcel.id])


static func _edge_furniture(data: Dictionary, parcel: Dictionary, occupied: Array[Rect2],
		reserved: Array[Rect2], random: RandomNumberGenerator, frontage: ParcelFrontage = null) -> void:
	var kinds: Array[String] = ["planter", "bike", "trash", "sign", "vending", "pole", "lamp"]
	var budget: int = mini(18, maxi(4, parcel.buildings.size()))
	var added: int = 0
	for center: Vector2 in _frontage_anchors(data, parcel, Vector2(60, 32), 112.0, frontage):
		if added >= budget:
			break
		var kind: String = kinds[(added + random.randi_range(0, 2)) % kinds.size()]
		if _place_prop(data, parcel, occupied, reserved, random, kind, center, 16.0):
			added += 1


static func _fill_open(data: Dictionary, parcel: Dictionary, occupied: Array[Rect2],
		reserved: Array[Rect2], random: RandomNumberGenerator, frontage: ParcelFrontage = null) -> void:
	# Lawns stay open. A few plants follow path edges; everyday objects never scatter here.
	var added: int = 0
	var kinds: Array[String] = ["bush", "planter", "tree_b"]
	for center: Vector2 in _frontage_anchors(data, parcel, Vector2(40, 40), 224.0, frontage):
		if added >= 4:
			break
		if _place_prop(data, parcel, occupied, reserved, random, kinds[added % kinds.size()], center, 20.0):
			added += 1


static func _street_sets(data: Dictionary, parcel: Dictionary, occupied: Array[Rect2],
		reserved: Array[Rect2], random: RandomNumberGenerator, frontage: ParcelFrontage = null) -> int:
	for court: Dictionary in parcel.get("courtyards", []):
		if court.kind == "parking" and _fill_parking(data, parcel, court, occupied, reserved, random):
			return 1
	# Residential courts need not be labelled parking: look beside their real access paths.
	for center: Vector2 in _frontage_anchors(data, parcel, Vector2(112, 80), 128.0, frontage):
		if _parking_pad(data, parcel, Rect2(center - Vector2(56, 40), Vector2(112, 80)),
				occupied, reserved, random):
			return 1
	return 0


static func _fill_parking(data: Dictionary, parcel: Dictionary, court: Dictionary,
		occupied: Array[Rect2], reserved: Array[Rect2], random: RandomNumberGenerator) -> bool:
	var area: Rect2 = WorldLayout.rect(court.rect).grow(-8.0)
	var y: float = area.position.y
	while y + 80.0 <= area.end.y:
		var x: float = area.position.x
		while x + 112.0 <= area.end.x:
			if _parking_pad(data, parcel, Rect2(x, y, 112, 80), occupied, reserved, random):
				return true
			x += 128.0
		y += 96.0
	return false


static func _parking_pad(data: Dictionary, parcel: Dictionary, pad: Rect2,
		occupied: Array[Rect2], reserved: Array[Rect2], random: RandomNumberGenerator) -> bool:
	if not _free(data, parcel, pad, occupied, reserved) or not _parking_visible(data, pad):
		return false
	# The car's complete footprint is inside the already validated pad. Reserve them together.
	parcel.dressing.append({"kind":"parking", "point":[pad.get_center().x, pad.get_center().y],
		"surface":[pad.position.x, pad.position.y, pad.size.x, pad.size.y]})
	if random.randf() < 0.9:
		_place_prop(data, parcel, occupied, reserved, random, "parked_car",
			pad.get_center() + Vector2(0, 8), 24.0, random.randf() < 0.5)
	occupied.append(pad)
	return true


static func _parking_visible(data: Dictionary, pad: Rect2) -> bool:
	# Map clearance alone cannot stop a tall, offset isometric facade hiding the entire pad.
	var view: Rect2 = IsoSpace.view_bounds(pad).grow(12.0)
	for entity: Dictionary in data.entities:
		var block: Rect2 = WorldLayout.rect(entity.rect)
		if not block.grow(512.0).intersects(pad):
			continue
		var meta: Dictionary = IsoAtlas.info(IsoBuildingArt.pick(entity))
		if meta.is_empty():
			continue
		var extra: float = 1.0
		var map_size: Array = meta.get("map", [])
		if map_size.size() >= 2:
			extra = clampf((block.size.x + block.size.y) / (float(map_size[0]) + float(map_size[1])), 0.62, 1.22)
		var factor: float = IsoAtlas.art_scale() * extra
		var foot: Vector2 = WorldLayout.point(meta.foot)
		if entity.get("flip", false):
			foot.x = float(meta.w) - foot.x
		var origin: Vector2 = IsoSpace.to_view(Vector2(block.get_center().x, block.end.y)) - foot * factor
		if view.intersects(Rect2(origin, Vector2(meta.w, meta.h) * factor)):
			return false
	return true


static func _frontage_anchors(data: Dictionary, parcel: Dictionary, size: Vector2, step: float,
		frontage: ParcelFrontage = null) -> Array[Vector2]:
	if frontage == null:
		frontage = _parcel_frontage(data, parcel)
	var points: Array[Vector2] = []
	var bounds: Rect2 = WorldLayout.rect(parcel.rect)
	# Follow both sides of all access paths, including north/south and east/west frontages.
	for value: Array in parcel.get("walks", []):
		var walk: Rect2 = WorldLayout.rect(value)
		if walk.size.x >= walk.size.y:
			var x: float = walk.position.x + size.x * 0.5 + 8.0
			while x + size.x * 0.5 < walk.end.x:
				points.append(Vector2(x, walk.position.y - size.y * 0.5 - 8.0))
				points.append(Vector2(x, walk.end.y + size.y * 0.5 + 8.0))
				x += step
		else:
			var y: float = walk.position.y + size.y * 0.5 + 8.0
			while y + size.y * 0.5 < walk.end.y:
				points.append(Vector2(walk.position.x - size.x * 0.5 - 8.0, y))
				points.append(Vector2(walk.end.x + size.x * 0.5 + 8.0, y))
				y += step
	var edges: Array = parcel.get("road_edges", [false, false, false, false])
	for face: int in range(4):
		if not edges[face]:
			continue
		var horizontal: bool = face < 2
		var along: float = (bounds.position.x + size.x * 0.5 if horizontal else bounds.position.y + size.y * 0.5) + 16.0
		var end: float = bounds.end.x - size.x * 0.5 if horizontal else bounds.end.y - size.y * 0.5
		while along < end:
			for inset: float in [16.0, 80.0]:
				match face:
					0: points.append(Vector2(along, bounds.position.y + size.y * 0.5 + inset))
					1: points.append(Vector2(along, bounds.end.y - size.y * 0.5 - inset))
					2: points.append(Vector2(bounds.position.x + size.x * 0.5 + inset, along))
					3: points.append(Vector2(bounds.end.x - size.x * 0.5 - inset, along))
			along += step
	# A path through a large empty field is not a reason to line it with vending machines.
	var anchors: Array[Vector2] = []
	for point: Vector2 in points:
		if bounds.encloses(Rect2(point - size * 0.5, size)) and _near_frontage(data, parcel, point, frontage):
			anchors.append(point)
	return anchors


static func _frontage_index(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for parcel: Dictionary in data.parcels:
		if not result.has(parcel.id):
			result[parcel.id] = ParcelFrontage.new()
	for entity: Dictionary in data.entities:
		if result.has(entity.parcel):
			(result[entity.parcel] as ParcelFrontage).append(entity)
	return result


static func _parcel_frontage(data: Dictionary, parcel: Dictionary) -> ParcelFrontage:
	# Preserve the existing helper entry points without retaining any cross-call cache.
	var frontage: ParcelFrontage = ParcelFrontage.new()
	for entity: Dictionary in data.entities:
		if entity.parcel == parcel.id:
			frontage.append(entity)
	return frontage


static func _near_frontage(data: Dictionary, parcel: Dictionary, point: Vector2,
		frontage: ParcelFrontage = null) -> bool:
	if frontage == null:
		frontage = _parcel_frontage(data, parcel)
	var near_building: bool = false
	for index: int in range(frontage.doors.size()):
		if point.distance_to(frontage.doors[index]) <= 176.0:
			return true
		near_building = near_building or frontage.buildings[index].has_point(point)
	# Unbuilt roadside slivers are still lawns, not destinations for isolated vending or parking.
	if not near_building:
		return false
	var bounds: Rect2 = WorldLayout.rect(parcel.rect)
	var edges: Array = parcel.get("road_edges", [false, false, false, false])
	return ((edges[0] and point.y - bounds.position.y <= 144.0)
		or (edges[1] and bounds.end.y - point.y <= 144.0)
		or (edges[2] and point.x - bounds.position.x <= 144.0)
		or (edges[3] and bounds.end.x - point.x <= 144.0))


static func _place_prop(data: Dictionary, parcel: Dictionary, occupied: Array[Rect2],
		reserved: Array[Rect2], random: RandomNumberGenerator, kind: String, point: Vector2,
		radius: float, flip: bool = false) -> bool:
	var mark: Rect2 = _prop_mark(kind, point, radius)
	if not _free(data, parcel, mark, occupied, reserved):
		return false
	var row: Dictionary = {"kind": kind, "point": [point.x, point.y], "variant": random.randi_range(0, 3)}
	if flip:
		row.flip = true
	parcel.dressing.append(row)
	occupied.append(mark)
	return true


static func _prop_mark(kind: String, point: Vector2, radius: float = 16.0) -> Rect2:
	# These sprites extend beyond the old 32-unit placeholder footprint.
	if kind == "bike_shelter":
		return Rect2(point - Vector2(70, 86), Vector2(140, 106))
	if kind == "bike":
		return Rect2(point - Vector2(30, 8), Vector2(60, 20))
	if kind == "parked_car":
		return Rect2(point - Vector2(48, 40), Vector2(96, 64))
	return Rect2(point - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)


static func _free(data: Dictionary, parcel: Dictionary, mark: Rect2, occupied: Array[Rect2], reserved: Array[Rect2]) -> bool:
	if not WorldLayout.rect(parcel.rect).encloses(mark):
		return false
	if data.has("bus"):
		if data.has("open_streets") and OpenStreetsV1.intersects_sweep(data.bus, mark, 20):
			return false
		if data.bus.has("sweep") and WorldLayout.rect(data.bus.sweep).grow(16).intersects(mark):
			return false
		if data.bus.has("rect") and WorldLayout.rect(data.bus.rect).grow(20).intersects(mark):
			return false
		if data.bus.has("door") and mark.grow(20).has_point(WorldLayout.point(data.bus.door)):
			return false
	# Avoid copying every occupied/reserved rectangle for every rejected candidate.
	for other: Rect2 in occupied:
		if mark.grow(6).intersects(other):
			return false
	for other: Rect2 in reserved:
		if mark.grow(6).intersects(other):
			return false
	for road: Array in data.get("roads", []):
		if mark.grow(8).intersects(WorldLayout.rect(road)):
			return false
	for walk: Array in parcel.get("walks", []):
		if mark.grow(6).intersects(WorldLayout.rect(walk)):
			return false
	return true
