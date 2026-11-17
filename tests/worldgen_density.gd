extends SceneTree
## Pure geometry comparisons against PR #83's complete pre-filter density algorithm.

const Oracle = preload("res://tests/support/density_oracle.gd")
var checks: int = 0
var failures: int = 0
var fixtures: int = 0


func _initialize() -> void:
	_generated()
	_focused()
	_cross_parcel()
	print("BH_WORLDGEN_DENSITY ", JSON.stringify({"checks":checks, "failures":failures, "fixtures":fixtures}))
	quit(1 if failures else 0)


func _expect(valid: bool, label: String) -> void:
	checks += 1
	if not valid:
		failures += 1
		printerr("BH_WORLDGEN_DENSITY_FAIL ", label)


func _generated() -> void:
	for topology: String in ["commercial", "residential", "industrial"]:
		for size: String in ["small", "medium", "large"]:
			var seed: String = "density-parcels:" + topology + ":" + size
			var task: String = "airdrop" if topology == "industrial" else "rescue" if topology == "residential" else "supply"
			var data: Dictionary = WorldgenGeometry.assemble(seed, size, topology, 1, false, task)
			_compare_fill(data, seed)
		# Includes old wide/compact streets and current seeded districts. Some
		# district types intentionally skip density and must remain untouched.
		for revision: int in [OpenStreetsV1.WIDE_VERSION, OpenStreetsV1.COMPACT_VERSION, OpenStreetsV1.SEEDED_VERSION]:
			var seed: String = "density-open:" + topology + ":" + str(revision)
			var data: Dictionary = WorldgenGeometry.assemble(seed, "large", topology, 2, false, "supply", false, false, revision)
			_compare_fill(data, seed)
	for topology: String in ["commercial", "residential", "industrial"]:
		_compare_fill(WorldgenGeometry.assemble("density-fallback", "medium", topology, 0, true, "supply"), "fallback:" + topology)


func _compare_fill(data: Dictionary, label: String) -> void:
	_expect(not data.is_empty(), "real geometry exists: " + label)
	if data.is_empty():
		return
	var expected: Dictionary = data.duplicate(true)
	var actual: Dictionary = data.duplicate(true)
	Oracle.fill(expected)
	WorldgenDensity.fill(actual)
	fixtures += 1
	_expect(RecordEncoding.fingerprint(actual) == RecordEncoding.fingerprint(expected),
		"complete geometry, entity IDs, variants, walks and random choices: " + label)


func _parcel(id: String, box: Rect2) -> Dictionary:
	return {"id":id, "rect":[box.position.x, box.position.y, box.size.x, box.size.y],
		"buildings":[], "walks":[], "courtyards":[], "entrance":[-4096.0, -4096.0]}


func _data(parcels: Array) -> Dictionary:
	return {"seed":"density-boundaries", "topology":"industrial", "entities":[], "parcels":parcels,
		"roads":[], "bus":{"sweep":[-8192.0, -8192.0, 64.0, 64.0], "door":[-8192.0, -8192.0]}}


func _obstacles() -> Dictionary:
	var reserved: Array[Rect2] = []
	var silhouettes: Array[Rect2] = []
	var doors: Array[Vector2] = []
	var fences: Array[Rect2] = []
	var door_fences: Array[Rect2] = []
	return {"reserved":reserved, "silhouettes":silhouettes, "doors":doors,
		"fences":fences, "door_fences":door_fences}


func _run_parcels(input: Dictionary, obstacles: Dictionary, oracle: bool) -> Dictionary:
	var data: Dictionary = input.duplicate(true)
	var values: Dictionary = obstacles.duplicate(true)
	for parcel: Dictionary in data.parcels:
		if oracle:
			Oracle._fill_parcel(data, parcel, values.reserved, values.silhouettes, values.doors,
				values.fences, values.door_fences)
		else:
			WorldgenDensity._fill_parcel(data, parcel, values.reserved, values.silhouettes, values.doors,
				values.fences, values.door_fences)
	return {"data":data, "obstacles":values}


func _compare_parcels(input: Dictionary, obstacles: Dictionary, label: String) -> Dictionary:
	var expected: Dictionary = _run_parcels(input, obstacles, true)
	var actual: Dictionary = _run_parcels(input, obstacles, false)
	fixtures += 1
	_expect(RecordEncoding.fingerprint(actual.data) == RecordEncoding.fingerprint(expected.data), label + ": full output")
	_expect(actual.obstacles == expected.obstacles, label + ": ordered propagated obstacles")
	return expected


func _focused() -> void:
	var box: Rect2 = Rect2(100.25, 200.5, 960.0, 768.0)
	var input: Dictionary = _data([_parcel("fractional", box)])
	var clean: Dictionary = _compare_parcels(input, _obstacles(), "fractional parcel with multiple infills")
	_expect(clean.data.entities.size() >= 2, "fixture adds multiple buildings, exercising same-parcel appended obstacles")
	if clean.data.entities.is_empty():
		return
	var first: Dictionary = clean.data.entities[0]
	var doorway: Vector2 = WorldLayout.point(first.door)
	var silhouette: Rect2 = WorldgenScale.visible_rect(first).grow(8.0)
	var far: Rect2 = Rect2(90000.0, 90000.0, 10.0, 10.0)
	var base: Dictionary = _obstacles()
	# Boundaries, points, lines and fractional crossings retain the old
	# Rect2 narrow-phase behavior. They are synthetic geometry only.
	for offset: float in [-64.01, -64.0, -63.99, 0.0, 63.99, 64.0, 64.01]:
		base.reserved.append(Rect2(Vector2(box.position.x + offset, doorway.y), Vector2.ZERO))
		base.reserved.append(Rect2(Vector2(box.end.x + offset, doorway.y), Vector2(0.0, 48.25)))
	base.reserved.append(Rect2(Vector2(box.end.x + 63.75, doorway.y), Vector2(0.5, 0.25)))
	for index: int in range(120):
		base.reserved.append(Rect2(20000.0 + index * 100.0, -20000.0, 8.0, 16.0))
	var boundary: Dictionary = _compare_parcels(input, base, "64-unit boundaries and degenerate reservations")
	_expect(RecordEncoding.fingerprint(boundary.data) == RecordEncoding.fingerprint(clean.data),
		"distant and 64-unit boundary obstacles do not affect accepted placements")
	for extent: Vector2 in [Vector2.ZERO, Vector2(0.0, 4.5), Vector2(4.5, 0.0)]:
		var degenerate: Dictionary = _obstacles()
		degenerate.reserved.append(Rect2(doorway, extent))
		_compare_parcels(input, degenerate, "near degenerate extent " + str(extent))
	# Godot rejects negative Rect2 extents in the narrow phase. The broad phase
	# conservatively retains them without invoking those engine operations.
	for extent: Vector2 in [Vector2(-4.5, 5.0), Vector2(4.5, -5.0), Vector2(-4.5, -5.0)]:
		_expect(WorldgenDensity._could_overlap(box.grow(64.0), Rect2(far.position, extent)),
			"negative extent is conservatively retained before the unsupported narrow phase")
	# Each member of a pair independently keeps the pair in the broad phase.
	for kind: String in ["silhouette", "door", "fence", "door_fence", "reservation"]:
		var values: Dictionary = base.duplicate(true)
		if kind in ["silhouette", "door"]:
			values.silhouettes.append(silhouette if kind == "silhouette" else far)
			values.doors.append(doorway if kind == "door" else far.position)
		elif kind in ["fence", "door_fence"]:
			values.fences.append(WorldLayout.rect(first.rect) if kind == "fence" else far)
			# _add_building may flip the final entity door after _fits checked its
			# unflipped candidate. Cover the parcel to hit every legal candidate door.
			values.door_fences.append(box if kind == "door_fence" else far)
		else:
			values.reserved.append(Rect2(doorway - Vector2(20, 20), Vector2(40, 40)))
		var expected: Dictionary = _compare_parcels(input, values, "near " + kind + " paired with distant geometry")
		_expect(RecordEncoding.fingerprint(expected.data) != RecordEncoding.fingerprint(clean.data),
			"targeted " + kind + " actually rejects an otherwise accepted placement")
		if kind == "door_fence":
			_expect(expected.data.entities.is_empty(), "door fence alone rejects all legal candidate doors")


func _cross_parcel() -> void:
	var exercised: bool = false
	for shift: float in [-128.0, -192.0, -256.0, 128.0, 256.0]:
		# Overlapping geometry is deliberate: the earlier parcel's roof/door
		# reservations must influence the later fill, even outside its physical wall.
		var input: Dictionary = _data([_parcel("first", Rect2(100, 200, 960, 768)),
			_parcel("second", Rect2(100, 200 + shift, 960, 768))])
		var expected: Dictionary = _compare_parcels(input, _obstacles(), "cross-parcel append shift " + str(shift))
		var stale: Dictionary = input.duplicate(true)
		for parcel: Dictionary in stale.parcels:
			var empty: Dictionary = _obstacles()
			Oracle._fill_parcel(stale, parcel, empty.reserved, empty.silhouettes, empty.doors, empty.fences, empty.door_fences)
		exercised = exercised or RecordEncoding.fingerprint(stale) != RecordEncoding.fingerprint(expected.data)
	_expect(exercised, "a stale per-parcel obstacle snapshot would change at least one complete result")
