class_name WorldgenDressing
extends RefCounted
## Solid scenery is frozen before interactive props and the final navigation certificate.
## It never supplies loot or a search identity. Rendering cannot invent blockers.

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
			var area: Rect2=WorldLayout.rect(court.rect)
			var kind: String="scrap" if court.kind=="parking" else "cargo" if court.kind=="loading" else "hedge"
			var width: float=132 if kind=="scrap" else 112 if kind=="cargo" else 144
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
	_scatter(data, occupied, reserved)

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
	# Second pass after annexes. Never clears existing dressing or adds collision.
	if data.is_empty() or data.get("seaside_town", false) or not data.has("parcels"):
		return
	var occupied: Array[Rect2] = []
	for entity: Dictionary in data.entities:
		occupied.append(WorldLayout.rect(entity.rect).grow(18))
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
	var random: RandomNumberGenerator = RogueLayout.rng("town-props-more:" + String(data.get("seed", "0")))
	for parcel: Dictionary in data.parcels:
		_street_sets(data, parcel, occupied, reserved, random)
		_edge_furniture(data, parcel, occupied, reserved, random)
		_fill_open(data, parcel, occupied, reserved, random)


static func _scatter(data: Dictionary, occupied: Array[Rect2], reserved: Array[Rect2]) -> void:
	# Visual-only street furniture. No collision, so navigation certificates stay intact.
	var random: RandomNumberGenerator = RogueLayout.rng("town-props:" + String(data.get("seed", "0")))
	for parcel: Dictionary in data.parcels:
		# Give coherent street sets room before scattering the smaller props.
		_street_sets(data, parcel, occupied, reserved, random)
		for court: Dictionary in parcel.courtyards:
			if court.kind in ["garden", "court"]:
				_fill_garden(data, parcel, court, occupied, reserved, random)
			elif court.kind == "parking":
				_fill_yard_edge(data, parcel, court, occupied, reserved, random)
			elif court.kind == "loading":
				_fill_yard_edge(data, parcel, court, occupied, reserved, random)
		_edge_furniture(data, parcel, occupied, reserved, random)
		_fill_open(data, parcel, occupied, reserved, random)


static func _fill_garden(data: Dictionary, parcel: Dictionary, court: Dictionary,
		occupied: Array[Rect2], reserved: Array[Rect2], random: RandomNumberGenerator) -> void:
	var area: Rect2 = WorldLayout.rect(court.rect).grow(-16.0)
	if area.size.x < 48.0 or area.size.y < 48.0:
		return
	_border_garden(data, parcel, court, occupied, reserved, random)
	var kinds: Array[String] = ["tree", "tree_b", "bush", "hedge", "planter", "yard_wall", "bike", "vending", "trash"]
	var budget: int = clampi(int(area.get_area() / 4500.0), 10, 40)
	var added: int = 0
	var attempts: int = 0
	while added < budget and attempts < budget * 10:
		attempts += 1
		var kind: String = kinds[random.randi_range(0, kinds.size() - 1)]
		var point: Vector2 = Vector2(
			random.randf_range(area.position.x + 16.0, area.end.x - 16.0),
			random.randf_range(area.position.y + 16.0, area.end.y - 16.0)
		)
		var mark: Rect2 = _prop_mark(kind, point)
		if not _free(data, parcel, mark, occupied, reserved):
			continue
		parcel.dressing.append({"kind": kind, "point": [point.x, point.y], "variant": random.randi_range(0, 3)})
		# Reserve a tight visual footprint so props do not stack, but do not block walking.
		occupied.append(mark)
		added += 1


static func _edge_furniture(data: Dictionary, parcel: Dictionary, occupied: Array[Rect2],
		reserved: Array[Rect2], random: RandomNumberGenerator) -> void:
	var bounds: Rect2 = WorldLayout.rect(parcel.rect)
	var edges: Array = parcel.get("road_edges", [false, false, false, false])
	# Place along the inner lip of a road frontage, inside the parcel, off the roadway.
	var anchors: Array[Vector2] = []
	if edges.size() > 1 and edges[1]:
		var y: float = bounds.end.y - 20.0
		var x: float = bounds.position.x + 48.0
		while x < bounds.end.x - 48.0:
			anchors.append(Vector2(x, y))
			x += 52.0 + random.randf_range(-6.0, 6.0)
	if edges.size() > 0 and edges[0]:
		var y: float = bounds.position.y + 20.0
		var x: float = bounds.position.x + 48.0
		while x < bounds.end.x - 48.0:
			anchors.append(Vector2(x, y))
			x += 56.0
	var kinds: Array[String] = ["lamp", "pole", "planter", "bike", "bush", "vending", "tree", "crate", "trash", "sign"]
	var added: int = 0
	for point: Vector2 in anchors:
		if added >= 32:
			break
		var kind: String = kinds[random.randi_range(0, kinds.size() - 1)]
		# A frontage lip can itself be a walk. Try the next inner band without
		# weakening any door, pavement, yard or bus reservation.
		var inward: float = 1.0 if point.y < bounds.get_center().y else -1.0
		for offset: float in [0.0, 48.0, 96.0]:
			var candidate: Vector2 = point + Vector2(0, inward * offset)
			var mark: Rect2 = _prop_mark(kind, candidate, 12.0)
			if not _free(data, parcel, mark, occupied, reserved):
				continue
			parcel.dressing.append({"kind": kind, "point": [candidate.x, candidate.y], "variant": random.randi_range(0, 3)})
			occupied.append(mark)
			added += 1
			break


static func _fill_yard_edge(data: Dictionary, parcel: Dictionary, court: Dictionary,
		occupied: Array[Rect2], reserved: Array[Rect2], random: RandomNumberGenerator) -> void:
	var area: Rect2 = WorldLayout.rect(court.rect)
	if area.size.x < 80.0 or area.size.y < 64.0:
		return
	var kinds: Array[String] = ["pole", "lamp", "crate", "planter", "bush", "trash", "sign"]
	var points: Array[Vector2] = [
		Vector2(area.position.x + 24.0, area.position.y + 20.0),
		Vector2(area.end.x - 24.0, area.position.y + 20.0),
		Vector2(area.position.x + 24.0, area.end.y - 16.0),
		Vector2(area.end.x - 24.0, area.end.y - 16.0),
		Vector2(area.get_center().x, area.position.y + 18.0),
		Vector2(area.position.x + area.size.x * 0.33, area.end.y - 16.0),
		Vector2(area.position.x + area.size.x * 0.66, area.position.y + 18.0),
		Vector2(area.end.x - 24.0, area.get_center().y),
	]
	var added: int = 0
	for point: Vector2 in points:
		if added >= 8:
			break
		var kind: String = kinds[random.randi_range(0, kinds.size() - 1)]
		var mark: Rect2 = Rect2(point - Vector2(12, 12), Vector2(24, 24))
		if not _free(data, parcel, mark, occupied, reserved):
			continue
		parcel.dressing.append({"kind": kind, "point": [point.x, point.y], "variant": random.randi_range(0, 3)})
		occupied.append(mark)
		added += 1


static func _fill_open(data: Dictionary, parcel: Dictionary, occupied: Array[Rect2],
		reserved: Array[Rect2], random: RandomNumberGenerator) -> void:
	var area: Rect2 = WorldLayout.rect(parcel.rect).grow(-28.0)
	if area.size.x < 80.0 or area.size.y < 80.0:
		return
	var kinds: Array[String] = ["tree", "tree_b", "bush", "hedge", "planter", "yard_wall", "bike", "pole", "vending", "crate", "trash", "sign"]
	var budget: int = clampi(int(area.get_area() / 6500.0), 10, 44)
	var added: int = 0
	var attempts: int = 0
	while added < budget and attempts < budget * 12:
		attempts += 1
		var kind: String = kinds[random.randi_range(0, kinds.size() - 1)]
		var point: Vector2 = Vector2(
			random.randf_range(area.position.x + 16.0, area.end.x - 16.0),
			random.randf_range(area.position.y + 16.0, area.end.y - 16.0)
		)
		var mark: Rect2 = _prop_mark(kind, point)
		if not _free(data, parcel, mark, occupied, reserved):
			continue
		parcel.dressing.append({"kind": kind, "point": [point.x, point.y], "variant": random.randi_range(0, 3)})
		occupied.append(mark)
		added += 1



static func _street_sets(data: Dictionary, parcel: Dictionary, occupied: Array[Rect2],
		reserved: Array[Rect2], random: RandomNumberGenerator) -> void:
	# Intentional clusters: a parking stall with a car, a vending pair, a bike shelter.
	for court: Dictionary in parcel.get("courtyards", []):
		var kind: String = String(court.get("kind", ""))
		if kind in ["garden", "court", "parking"] and random.randf() < 0.65:
			var area: Rect2 = WorldLayout.rect(court.rect)
			for point: Vector2 in [area.get_center() + Vector2(0, 33),
					Vector2(area.position.x + 72, area.end.y - 24),
					Vector2(area.end.x - 72, area.end.y - 24)]:
				if area.encloses(_prop_mark("bike_shelter", point)) and _place_prop(
						data, parcel, occupied, reserved, random, "bike_shelter", point, 28.0):
					break
		if kind == "parking":
			_fill_parking(data, parcel, court, occupied, reserved, random)
	var bounds: Rect2 = WorldLayout.rect(parcel.rect)
	var edges: Array = parcel.get("road_edges", [false, false, false, false])
	if edges.size() > 1 and edges[1]:
		var lip: float = bounds.end.y - 36.0
		var along: float = bounds.position.x + 96.0
		var pads: int = 0
		while along < bounds.end.x - 80.0 and pads < 4:
			if random.randf() < 0.8:
				var pad: Rect2 = Rect2(along - 40.0, lip - 72.0, 80.0, 64.0)
				if _free(data, parcel, pad, occupied, reserved):
					parcel.dressing.append({"kind": "parking", "point": [pad.get_center().x, pad.get_center().y],
						"surface": [pad.position.x, pad.position.y, pad.size.x, pad.size.y]})
					_place_prop(data, parcel, occupied, reserved, random, "parked_car",
						pad.get_center() + Vector2(0, 8.0), 24.0, random.randf() < 0.5)
					occupied.append(pad)
					pads += 1
					_place_prop(data, parcel, occupied, reserved, random, "sign",
						Vector2(along + 56.0, lip - 8.0), 16.0)
					if random.randf() < 0.75:
						_place_prop(data, parcel, occupied, reserved, random, "vending",
							Vector2(along + 72.0, lip - 6.0), 14.0)
						_place_prop(data, parcel, occupied, reserved, random, "trash",
							Vector2(along + 88.0, lip - 6.0), 12.0)
			along += 152.0


static func _fill_parking(data: Dictionary, parcel: Dictionary, court: Dictionary,
		occupied: Array[Rect2], reserved: Array[Rect2], random: RandomNumberGenerator) -> void:
	var area: Rect2 = WorldLayout.rect(court.rect).grow(-12.0)
	if area.size.x < 72.0 or area.size.y < 56.0:
		return
	var count: int = clampi(int(area.size.x / 88.0), 1, 4)
	var added: int = 0
	var x: float = area.position.x + 8.0
	while added < count and x + 64.0 <= area.end.x:
		# Shallow courts start just below an apron: the old 4-unit margin
		# always failed the 6-unit walk clearance. Keep an 8-unit inset.
		var pad: Rect2 = Rect2(x, area.position.y + 8.0, 64.0, minf(72.0, area.size.y - 16.0))
		if _free(data, parcel, pad, occupied, reserved):
			parcel.dressing.append({"kind": "parking", "point": [pad.get_center().x, pad.get_center().y],
				"surface": [pad.position.x, pad.position.y, pad.size.x, pad.size.y]})
			if random.randf() < 0.85:
				_place_prop(data, parcel, occupied, reserved, random, "parked_car",
					pad.get_center() + Vector2(0, 6.0), 22.0, random.randf() < 0.5)
			else:
				_place_prop(data, parcel, occupied, reserved, random, "bike",
					pad.get_center(), 28.0)
			occupied.append(pad)
			added += 1
		x += 88.0
	if added == 0:
		_place_prop(data, parcel, occupied, reserved, random, "parked_car",
			area.get_center(), 22.0, random.randf() < 0.5)
	_place_prop(data, parcel, occupied, reserved, random, "pole",
		Vector2(area.position.x + 16.0, area.position.y + 12.0), 14.0)
	_place_prop(data, parcel, occupied, reserved, random, "sign",
		Vector2(area.end.x - 16.0, area.position.y + 12.0), 16.0)


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


static func _border_garden(data: Dictionary, parcel: Dictionary, court: Dictionary,
		occupied: Array[Rect2], reserved: Array[Rect2], random: RandomNumberGenerator) -> void:
	# Decorative yard walls and hedges along the rim, leaving the entrance clear.
	var area: Rect2 = WorldLayout.rect(court.rect)
	var entry: Vector2 = WorldLayout.point(court.entrance) if court.has("entrance") else area.get_center()
	var points: Array[Vector2] = []
	var x: float = area.position.x + 20.0
	while x < area.end.x - 20.0:
		points.append(Vector2(x, area.end.y - 14.0))
		points.append(Vector2(x, area.position.y + 16.0))
		x += 56.0
	var y: float = area.position.y + 28.0
	while y < area.end.y - 28.0:
		points.append(Vector2(area.position.x + 16.0, y))
		points.append(Vector2(area.end.x - 16.0, y))
		y += 60.0
	var added: int = 0
	for index: int in range(points.size()):
		if added >= 20:
			break
		var point: Vector2 = points[index]
		if point.distance_to(entry) < 48.0:
			continue
		# Leave extra openings so a yard wall is not a solid fence.
		if index % 4 == 1:
			continue
		var mark: Rect2 = Rect2(point - Vector2(14, 14), Vector2(28, 28))
		if not _free(data, parcel, mark, occupied, reserved):
			continue
		var kind: String = "yard_wall" if index % 3 != 2 else "hedge" if index % 2 == 0 else "bush"
		parcel.dressing.append({"kind": kind, "point": [point.x, point.y], "variant": random.randi_range(0, 3)})
		occupied.append(mark)
		added += 1
