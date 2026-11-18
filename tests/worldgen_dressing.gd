extends SceneTree
## Same real geometry inputs, complete output equality against the frozen PR #83 pass.

const Oracle = preload("res://tests/support/dressing_oracle.gd")
var checks: int = 0
var failures: int = 0
var added_details: int = 0
var boundary_source: Dictionary = {}

func _initialize() -> void:
	var fixtures: Array = [
		["density-small", "small", "commercial", 0, false, "supply", 0],
		["density-large", "large", "residential", 1, false, "rescue", 0],
		["density-industry", "large", "industrial", 2, false, "airdrop", 0],
		["dressing-fallback", "medium", "commercial", 0, true, "supply", 0],
		["astar-commercial", "large", "commercial", 0, false, "supply", OpenStreetsV1.VERSION],
		["astar-residential", "large", "residential", 0, false, "supply", OpenStreetsV1.VERSION],
		["astar-industrial", "large", "industrial", 0, false, "supply", OpenStreetsV1.VERSION]]
	for fixture: Array in fixtures:
		_generated(fixture)
	_expect(added_details > 0, "real geometry comparisons include newly placed decorative props")
	if not boundary_source.is_empty():
		_frontage_boundaries(boundary_source)
	var skipped: Dictionary = {"seaside_town":true}
	WorldgenDressing.enrich(skipped)
	_expect(skipped == {"seaside_town":true}, "authored seaside remains untouched")
	print("BH_WORLDGEN_DRESSING ", JSON.stringify({"checks":checks, "failures":failures,
		"fixtures":fixtures.size(), "new_details":added_details}))
	quit(0 if failures == 0 else 1)

func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("BH_WORLDGEN_DRESSING_FAIL ", label)

func _generated(fixture: Array) -> void:
	var data: Dictionary = WorldgenGeometry.assemble(fixture[0], fixture[1], fixture[2], fixture[3],
		fixture[4], fixture[5], false, false, fixture[6])
	_expect(not data.is_empty(), "real geometry exists " + fixture[0])
	if data.is_empty():
		return
	WorldgenDensity.fill(data)
	WorldgenDressing.freeze(data)
	_expect(not data.entities.is_empty() and not data.parcels.is_empty(), "populated parcels " + fixture[0])
	if boundary_source.is_empty():
		boundary_source = data.duplicate(true)
	var expected: Dictionary = data.duplicate(true)
	var actual: Dictionary = data.duplicate(true)
	var before: int = _detail_count(data)
	Oracle.enrich(expected)
	FreezeProfile.enabled = true
	FreezeProfile.start({"scope":"single-dressing-pass", "fixture":fixture[0]})
	WorldgenDressing.enrich(actual)
	FreezeProfile.finish()
	FreezeProfile.enabled = false
	var projections: int = int(FreezeProfile.latest.metadata.get("worldgen_visible_rects", 0))
	_expect(projections > 0 and projections <= 2 * data.entities.size(),
		"silhouettes project for occupied bounds and frontage once, not per candidate " + fixture[0])
	var actual_hash: String = RecordEncoding.fingerprint(actual)
	_expect(not actual_hash.is_empty() and actual_hash == RecordEncoding.fingerprint(expected),
		"complete geometry, dressing order and random variants match frozen pass " + fixture[0])
	_expect(actual.entities == data.entities and actual.roads == data.roads and actual.bus == data.bus,
		"decoration does not modify geometry " + fixture[0])
	var added: int = _detail_count(actual) - before
	_expect(added > 0, "comparison exercises newly placed props " + fixture[0])
	added_details += added
	# A subsequent call must recompute its local projection and respect new occupied props.
	Oracle.enrich(expected)
	WorldgenDressing.enrich(actual)
	_expect(RecordEncoding.fingerprint(actual) == RecordEncoding.fingerprint(expected),
		"second pass has no retained projection/output cache " + fixture[0])

func _detail_count(data: Dictionary) -> int:
	var count: int = 0
	for parcel: Dictionary in data.parcels:
		count += parcel.get("dressing", []).size()
	return count

func _frontage_boundaries(source: Dictionary) -> void:
	var first: Dictionary = source.entities[0].duplicate(true)
	first.parcel = "shared"
	var second: Dictionary = first.duplicate(true)
	second.door = [float(first.door[0]) + 400.0, float(first.door[1]) + 96.0]
	var unrelated: Dictionary = first.duplicate(true)
	unrelated.parcel = "unrelated"
	var area: Rect2 = WorldgenScale.visible_rect(first).grow(300.0)
	var parcel: Dictionary = {"id":"shared", "rect":[area.position.x, area.position.y, area.size.x, area.size.y],
		"walks":[[area.position.x, area.get_center().y, area.size.x, 48.0],
			[area.get_center().x, area.position.y, 48.0, area.size.y]], "road_edges":[true, true, true, true]}
	var duplicate_id: Dictionary = parcel.duplicate(true)
	duplicate_id.rect[0] += 32.0
	duplicate_id.road_edges = [false, true, false, false]
	var no_edges: Dictionary = parcel.duplicate(true)
	no_edges.road_edges = [false, false, false, false]
	var empty: Dictionary = parcel.duplicate(true)
	empty.id = "no-buildings"
	# Repeated IDs use the same entity association, but keep each parcel's own bounds/edges.
	var data: Dictionary = {"entities":[first, unrelated, second], "parcels":[parcel, duplicate_id, no_edges, empty]}
	var index: Dictionary = WorldgenDressing._frontage_index(data)
	_expect(index.size() == 2 and index["shared"].doors == [WorldLayout.point(first.door), WorldLayout.point(second.door)],
		"parcel grouping retains matching entity order without unrelated entities or duplicate-ID copies")
	var door: Vector2 = WorldLayout.point(first.door)
	var silhouette: Rect2 = WorldgenScale.visible_rect(first).grow(96.0)
	var points: Array[Vector2] = [door, WorldLayout.point(second.door), door + Vector2(176.0, 0), door + Vector2(176.001, 0),
		door + Vector2(-176.0, 0), door + Vector2(0, 176.0), door + Vector2(0, -176.001),
		silhouette.position, silhouette.end, Vector2(silhouette.end.x, silhouette.position.y),
		Vector2(silhouette.position.x, silhouette.end.y), silhouette.get_center(),
		Vector2(area.get_center().x, area.position.y + 144.0),
		Vector2(area.get_center().x, area.position.y + 144.001),
		Vector2(area.position.x + 144.0, area.get_center().y),
		Vector2(area.end.x - 144.0, area.get_center().y),
		Vector2(area.get_center().x, area.end.y - 144.0), area.position - Vector2.ONE]
	_expect(WorldgenDressing._near_frontage(data, no_edges, door + Vector2(176.0, 0), index[no_edges.id]),
		"exact 176-unit door radius is accepted without a road edge")
	_expect(not WorldgenDressing._near_frontage(data, no_edges, door + Vector2(176.001, 0), index[no_edges.id]),
		"point beyond door radius requires the original road-edge condition")
	_expect(not WorldgenDressing._near_frontage(data, empty, door, index[empty.id]),
		"unbuilt parcel cannot borrow an unrelated nearby door")
	for target: Dictionary in data.parcels:
		for point: Vector2 in points:
			var expected: bool = Oracle._near_frontage(data, target, point)
			_expect(WorldgenDressing._near_frontage(data, target, point, index[target.id]) == expected,
				"indexed door-distance / half-open silhouette / roadside boundary " + target.id)
			_expect(WorldgenDressing._near_frontage(data, target, point) == expected,
				"existing direct frontage helper preserves boundary result " + target.id)
		for parameters: Array in [[Vector2(140, 106), 192.0], [Vector2(60, 32), 112.0],
			[Vector2(40, 40), 224.0], [Vector2(112, 80), 128.0]]:
			var expected: Array[Vector2] = Oracle._frontage_anchors(data, target, parameters[0], parameters[1])
			_expect(WorldgenDressing._frontage_anchors(data, target, parameters[0], parameters[1], index[target.id]) == expected,
				"indexed candidate point sequence exactly matches " + target.id)
			_expect(WorldgenDressing._frontage_anchors(data, target, parameters[0], parameters[1]) == expected,
				"existing direct anchors entry retains complete point sequence " + target.id)
	# Input mutation between passes cannot retain the previous door position.
	first.door = [door.x + 1000.0, door.y + 1000.0]
	var refreshed: Dictionary = WorldgenDressing._frontage_index(data)
	_expect(refreshed["shared"].doors[0] == WorldLayout.point(first.door), "new invocation observes changed input door")
	for point: Vector2 in points:
		_expect(WorldgenDressing._near_frontage(data, parcel, point, refreshed["shared"]) == Oracle._near_frontage(data, parcel, point),
			"fresh projection retains exact mutated-input result")
