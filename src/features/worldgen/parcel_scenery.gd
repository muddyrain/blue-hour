class_name ParcelScenery
extends RefCounted
## Fit the same site envelopes against each theme's existing building and scenery profiles.

const SETBACK: Vector2 = Vector2(24.0, 24.0)
const DOOR_APRON: float = 88.0
const EDGE_GAP: float = 20.0


static func fit(data: Dictionary) -> void:
	var occupied: Array[Rect2] = WarehouseScenery._occupied(data)
	var reserved: Array[Rect2] = ExplorationLayout._reserved(data)
	if data.has("open_streets"):
		reserved.append(OpenStreetsV1.boarding_paving(data.bus).grow(20.0))
	for point: Array in data.enemy_points:
		reserved.append(Rect2(WorldLayout.point(point) - Vector2.ONE * 32.0, Vector2.ONE * 64.0))
	var by_parcel: Dictionary = {}
	for building: Dictionary in data.entities:
		if not by_parcel.has(building.parcel):
			by_parcel[building.parcel] = []
		by_parcel[building.parcel].append(building)
	for plot: Dictionary in data.parcels:
		var buildings: Array = by_parcel.get(plot.id, [])
		_fit_plot(data, plot, buildings, occupied, reserved)


static func _fit_plot(data: Dictionary, plot: Dictionary, buildings: Array,
		occupied: Array[Rect2], reserved: Array[Rect2]) -> void:
	var bounds: Rect2 = WorldLayout.rect(plot.rect)
	var interior: Rect2 = bounds.grow(-EDGE_GAP)
	var industrial: bool = data.topology == "industrial"
	var random: RandomNumberGenerator = RogueLayout.rng("parcel-scenery:" + data.seed + ":" + plot.id)
	var exclusions: Array[Rect2] = []
	var clear_walks: Array[Rect2] = reserved.duplicate()
	for zone: Rect2 in reserved + occupied:
		if zone.intersects(bounds):
			exclusions.append(zone)
	for wall: Array in data.get("barriers", []):
		var barrier: Rect2 = WorldLayout.rect(wall).grow(16.0)
		if barrier.intersects(bounds):
			exclusions.append(barrier)
	for building: Dictionary in buildings:
		exclusions.append(WorldgenScale.visible_rect(building).grow(16.0))
	for walk: Array in plot.walks:
		exclusions.append(WorldLayout.rect(walk).grow(12.0))
		clear_walks.append(WorldLayout.rect(walk))
	for court: Dictionary in plot.courtyards:
		exclusions.append(WorldLayout.rect(court.rect).grow(12.0))
	var slot: String = WarehouseSlots.END if plot.road_edges[1] else WarehouseSlots.NARROW
	var profile: Vector2 = WarehouseSlots.BUILDINGS[slot].size if industrial else 		Vector2(WorldgenScale.WIDTH.garage, WorldgenScale.visible_height("garage"))
	var minimum: Vector2 = profile + Vector2(SETBACK.x * 2.0, SETBACK.y + DOOR_APRON)
	var candidates: Array[Rect2] = _lots(interior, exclusions, minimum)
	var eligible: bool = not candidates.is_empty()
	var annexes: int = 0
	var budget: int = clampi(int(bounds.get_area() / 520000.0), 1, 4)
	var types: Array[String] = []
	if industrial:
		types.assign(["garage", "warehouse", "convenience_store"])
	elif data.topology == "residential":
		types.assign(["detached_home", "row_house", "garage", "convenience_store"])
	else:
		types.assign(["convenience_store", "eatery", "garage", "row_house"])
	while not candidates.is_empty() and annexes < budget:
		var lot: Rect2 = _near_frontage(candidates, plot, bounds, minimum)
		var typ: String = types[annexes % types.size()]
		var profile_now: Vector2 = Vector2(float(WorldgenScale.WIDTH[typ]), WorldgenScale.visible_height(typ)) if not industrial 			else profile
		var min_now: Vector2 = profile_now + Vector2(SETBACK.x * 2.0, SETBACK.y + DOOR_APRON)
		if lot.size.x < min_now.x or lot.size.y < min_now.y:
			# This envelope was sized for a garage; skip rather than force a too-tall house.
			exclusions.append(lot)
			candidates = _lots(interior, exclusions, minimum)
			continue
		var foot: Vector2 = lot.position + Vector2(SETBACK.x, min_now.y - DOOR_APRON)
		var id: String = "%s_site_annex_%d" % [plot.id, annexes]
		var entity: Dictionary
		if industrial:
			var form: Dictionary = WarehouseSlots.BUILDINGS[slot]
			var block: Rect2 = Rect2(foot - Vector2(0, form.depth), Vector2(profile.x, form.depth))
			var arch: String = typ if typ in ["warehouse", "convenience_store", "garage"] else "garage"
			entity = {"id":id,"archetype":arch,"rect":WarehouseDistrict._rect(block),
				"door":WarehouseDistrict._point(foot + Vector2(form.door,48.0)), "variant":annexes % 3,
				"parcel":plot.id,"art":slot,"service_only":true}
			data.entities.append(entity)
			plot.buildings.append(id)
		else:
			if not WorldgenGeometry._add_building(typ, random.randi_range(0, 2), foot.x, foot.y,
					plot, data.entities, data.roads, data.bus):
				exclusions.append(lot)
				candidates = _lots(interior, exclusions, minimum)
				continue
			entity = data.entities[-1]
			entity.service_only = true
		buildings.append(entity)
		occupied.append(WorldLayout.rect(entity.rect).grow(12.0))
		exclusions.append(lot)
		var door: Vector2 = WorldLayout.point(entity.door)
		WarehouseDistrict._walk(plot, Vector2(lot.position.x + 12.0, door.y),
			Vector2(lot.end.x - 12.0, door.y), 36.0)
		annexes += 1
		candidates = _lots(interior, exclusions, minimum)

	var detail_count: int = plot.dressing.size()
	var rejected: bool = annexes < budget and not candidates.is_empty()
	var purpose: Array[Dictionary] = []
	for court: Dictionary in plot.courtyards:
		var area: Rect2 = WorldLayout.rect(court.rect)
		purpose.append({"use":court.kind, "rect":court.rect})
		if industrial and court.kind == "loading" and area.size.x >= 224.0 and area.size.y >= 72.0:
			_loading(plot, area, occupied, clear_walks, purpose.size())
	if industrial:
		_wall_details(plot, buildings, occupied, clear_walks, random)
	# A frontage with enough space for a wider loading or parking strip gets one.
	# Narrow land can still support a repair or planting pad at its accessible edge.
	for index: int in range(budget):
		var apron_size: Vector2 = Vector2(720.0, 304.0) if industrial else Vector2(448.0, 224.0)
		var pads: Array[Rect2] = _lots(interior, exclusions, apron_size)
		if pads.is_empty():
			apron_size = minimum
			pads = _lots(interior, exclusions, apron_size)
		if pads.is_empty():
			break
		var apron: Rect2 = _near_frontage(pads, plot, bounds, apron_size)
		var use: String = "loading" if industrial and apron.size.x >= 720.0 else \
			"staging" if industrial else "garden" if data.topology == "residential" else "parking"
		if use == "staging":
			WarehouseScenery._surface(plot, "staging_%d" % index, WarehouseSlots.MAT, apron.grow(-10.0))
			WarehouseScenery._upright(plot, "staging_kit_%d" % index, WarehouseSlots.REPAIR,
				apron.position + Vector2(48.0, 40.0), occupied, clear_walks)
		else:
			WarehouseDistrict._court(plot, apron, use, apron.get_center())
			if industrial:
				_loading(plot, apron, occupied, clear_walks, 100 + index)
		purpose.append({"use":use, "rect":WarehouseDistrict._rect(apron)})
		exclusions.append(apron)

	var unused: Array[Rect2] = _lots(interior, exclusions, minimum)
	var largest: Rect2
	for anchors: Rect2 in unused:
		var envelope: Rect2 = Rect2(anchors.position, anchors.size + minimum - Vector2.ONE * 0.004)
		if envelope.get_area() > largest.get_area():
			largest = envelope
	plot.site_fit = {"minimum":WarehouseDistrict._point(minimum), "eligible":eligible, "annexes":annexes,
		"details":plot.dressing.size(), "added_details":plot.dressing.size() - detail_count,
		"purpose":purpose, "unassigned_count":unused.size(), "largest_unassigned":WarehouseDistrict._rect(largest),
		"reason":"no_legal_envelope" if not eligible else "placement_rejected" if rejected 			else "parcel_budget" if not unused.is_empty() else "assigned"}


static func _lots(interior: Rect2, exclusions: Array[Rect2], minimum: Vector2) -> Array[Rect2]:
	# Split the domain of legal top-left anchors, so a rectangle can span the
	# seam between two free pieces of land.
	var domain: Rect2 = Rect2(interior.position, interior.size - minimum + Vector2.ONE * 0.004)
	if not domain.has_area():
		return []
	var options: Array[Rect2] = [domain]
	for zone: Rect2 in exclusions:
		var cut: Rect2 = Rect2(zone.position - minimum + Vector2.ONE * 0.004, zone.size + minimum - Vector2.ONE * 0.004)
		options = WarehouseDistrict._subtract(options, cut, Vector2.ZERO)
	return options


static func _near_frontage(candidates: Array[Rect2], plot: Dictionary, bounds: Rect2, minimum: Vector2) -> Rect2:
	var entry: Vector2 = WorldLayout.point(plot.entrance)
	var preferred: Vector2 = entry - minimum * Vector2(0.5, 1.0)
	var fronts: Array[Vector2] = []
	for face: int in range(4):
		if not plot.road_edges[face]:
			continue
		match face:
			0: fronts.append(Vector2(preferred.x, bounds.position.y))
			1: fronts.append(Vector2(preferred.x, bounds.end.y - minimum.y))
			2: fronts.append(Vector2(bounds.position.x, preferred.y))
			3: fronts.append(Vector2(bounds.end.x - minimum.x, preferred.y))
	if fronts.is_empty():
		fronts.append(preferred)
	var best: Rect2
	var distance: float = INF
	for anchors: Rect2 in candidates:
		var last: Vector2 = (anchors.end - Vector2.ONE * 0.004).max(anchors.position)
		for front: Vector2 in fronts:
			var point: Vector2 = front.clamp(anchors.position, last)
			var score: float = point.distance_to(front) + point.distance_to(preferred) * 0.5
			if score < distance:
				distance = score
				best = Rect2(point, minimum)
	return best


static func _loading(plot: Dictionary, area: Rect2, occupied: Array[Rect2], reserved: Array[Rect2], index: int) -> void:
	WarehouseScenery._surface(plot, "bay_%02d" % index, WarehouseSlots.BAY, area.grow(-4.0))
	WarehouseScenery._surface(plot, "dock_%02d" % index, WarehouseSlots.DOCK,
		Rect2(area.position + Vector2(8.0, 4.0), Vector2(area.size.x - 16.0, 16.0)))
	for side: int in [0, 1]:
		var x: float = area.position.x + 52.0 if side == 0 else area.end.x - 52.0
		WarehouseScenery._upright(plot, "cargo_%02d_%d" % [index, side], WarehouseSlots.CARGO,
			Vector2(x, area.position.y + 46.0), occupied, reserved)


static func _wall_details(plot: Dictionary, buildings: Array, occupied: Array[Rect2], reserved: Array[Rect2],
		random: RandomNumberGenerator) -> void:
	var bound: Rect2 = WorldLayout.rect(plot.rect)
	var added: int = 0
	for building: Dictionary in buildings:
		if added >= clampi(int(bound.get_area() / 450000.0), 1, 5):
			break
		var wall: Rect2 = WorldLayout.rect(building.rect)
		var door: Vector2 = WorldLayout.point(building.door)
		var span: float = maxf(door.x - wall.position.x, wall.end.x - door.x)
		if span < 82.0:
			continue
		var x: float = wall.position.x + span * 0.35 if door.x - wall.position.x > wall.end.x - door.x 			else wall.end.x - span * 0.35
		var point: Vector2 = Vector2(x, wall.end.y + 1.0)
		var slot: String = WarehouseSlots.LAMP if random.randi_range(0, 1) == 0 else WarehouseSlots.EDGE
		if bound.grow(-20.0).has_point(point):
			WarehouseScenery._upright(plot, building.id + "_mount", slot, point, occupied, reserved)
			added += 1
		if span >= 190.0:
			var kit: String = WarehouseSlots.RACK if span >= 228.0 else WarehouseSlots.REPAIR
			WarehouseScenery._upright(plot, building.id + "_wall_kit", kit,
				point + Vector2(0.0, 66.0), occupied, reserved)
